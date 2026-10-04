// Tests for tools/lanes-board/access.mjs: who may reach the board (this PC and
// the owner's tailnet), which names it answers to, and which page a phone gets.

import { describe, expect, it } from 'vitest';
import {
  fromTailnetOrLocal, knownHost, pageFor, sameOrigin, tailnetIPv4s, tailscaleSelf, wantsGzip,
} from '../tools/lanes-board/access.mjs';

const IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
const ANDROID = 'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36';
const ANDROID_TABLET = 'Mozilla/5.0 (Linux; Android 15; Pixel Tablet) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';
const DESKTOP = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';

const NAMES = new Set(['localhost', '127.0.0.1', '100.120.241.100', 'pc', 'pc.tail1234.ts.net']);

describe('fromTailnetOrLocal', () => {
  it('lets in loopback, in IPv4 and IPv6 forms', () => {
    for (const a of ['127.0.0.1', '::1', '::ffff:127.0.0.1']) expect(fromTailnetOrLocal(a)).toBe(true);
  });

  it('lets in Tailscale addresses: 100.64.0.0/10 and fd7a:115c:a1e0::/48', () => {
    for (const a of ['100.64.0.1', '100.120.241.100', '100.127.255.254', '::ffff:100.100.1.2', 'fd7a:115c:a1e0::1']) {
      expect(fromTailnetOrLocal(a)).toBe(true);
    }
  });

  it('refuses the rest of 100.x, the LAN and everything else', () => {
    for (const a of ['100.63.255.255', '100.128.0.1', '192.168.1.20', '10.0.0.5', '8.8.8.8', 'fe80::1', '', undefined]) {
      expect(fromTailnetOrLocal(a)).toBe(false);
    }
  });
});

describe('knownHost', () => {
  it('answers to its own names, with or without the port, in any case', () => {
    for (const h of ['localhost:5197', '127.0.0.1:5197', '100.120.241.100:5197', 'PC:5197', 'pc.tail1234.ts.net']) {
      expect(knownHost(h, NAMES)).toBe(true);
    }
  });

  it('refuses any other name, so a DNS-rebinding page gets nothing', () => {
    for (const h of ['evil.example:5197', '192.168.1.20:5197', '', undefined]) expect(knownHost(h, NAMES)).toBe(false);
  });
});

describe('sameOrigin', () => {
  const post = (origin, host, contentType = 'application/json') => sameOrigin({ origin, host, contentType }, NAMES);

  it('accepts the board posting to itself under any name it answers to', () => {
    expect(post('http://localhost:5197', 'localhost:5197')).toBe(true);
    expect(post('http://100.120.241.100:5197', '100.120.241.100:5197')).toBe(true);
    expect(post('http://pc:5197', 'pc:5197', 'application/json; charset=utf-8')).toBe(true);
  });

  it('refuses a page from anywhere else, a name it does not know, or a form post', () => {
    expect(post('http://evil.example', 'localhost:5197')).toBe(false);
    expect(post('http://localhost:5197', 'pc:5197')).toBe(false);
    expect(post('http://evil.example:5197', 'evil.example:5197')).toBe(false);
    expect(post('https://localhost:5197', 'localhost:5197')).toBe(false);
    expect(post(undefined, 'localhost:5197')).toBe(false);
    expect(post('null', 'localhost:5197')).toBe(false);
    expect(post('http://localhost:5197', 'localhost:5197', 'text/plain')).toBe(false);
  });
});

describe('pageFor', () => {
  it('gives phones the mobile page and computers the desktop one', () => {
    expect(pageFor('/', IPHONE).file).toBe('m.html');
    expect(pageFor('/', ANDROID).file).toBe('m.html');
    expect(pageFor('/', ANDROID_TABLET).file).toBe('index.html');
    expect(pageFor('/', DESKTOP).file).toBe('index.html');
    expect(pageFor('/?x=1', IPHONE).file).toBe('m.html');
  });

  it('lets /m and /desktop pick a page by hand', () => {
    expect(pageFor('/m', DESKTOP).file).toBe('m.html');
    expect(pageFor('/desktop', IPHONE).file).toBe('index.html');
    expect(pageFor('/desktop?from=m', IPHONE).file).toBe('index.html');
  });

  it('serves the web app manifest and the home-screen icon', () => {
    expect(pageFor('/manifest.webmanifest', IPHONE)).toEqual({ file: 'manifest.webmanifest', type: 'application/manifest+json' });
    expect(pageFor('/icon.png', IPHONE)).toEqual({ file: 'icon.png', type: 'image/png' });
    expect(pageFor('/apple-touch-icon.png', IPHONE)).toEqual({ file: 'icon.png', type: 'image/png' });
    expect(pageFor('/', DESKTOP).type).toBe('text/html; charset=utf-8');
  });
});

describe('wantsGzip', () => {
  it('gzips only for a client that says it takes gzip', () => {
    expect(wantsGzip('gzip, deflate, br')).toBe(true);
    expect(wantsGzip('br')).toBe(false);
    expect(wantsGzip('x-gzipped')).toBe(false);
    expect(wantsGzip(undefined)).toBe(false);
  });
});

describe('the PC\'s Tailscale identity', () => {
  it('reads its IPv4 addresses and MagicDNS names from tailscale status --json', () => {
    const status = { Self: { TailscaleIPs: ['100.120.241.100', 'fd7a:115c:a1e0::1'], DNSName: 'PC.tail1234.ts.net.' } };
    expect(tailscaleSelf(status)).toEqual({ ips: ['100.120.241.100'], names: ['pc.tail1234.ts.net', 'pc'] });
    expect(tailscaleSelf({})).toEqual({ ips: [], names: [] });
  });

  it('finds the Tailscale IPv4 address among the network interfaces, skipping loopback and the LAN', () => {
    const interfaces = {
      Ethernet: [{ family: 'IPv4', address: '192.168.1.20' }, { family: 'IPv6', address: 'fe80::1' }],
      Tailscale: [{ family: 'IPv4', address: '100.120.241.100' }, { family: 'IPv6', address: 'fd7a:115c:a1e0::1' }],
      'Loopback Pseudo-Interface 1': [{ family: 'IPv4', address: '127.0.0.1' }],
    };
    expect(tailnetIPv4s(interfaces)).toEqual(['100.120.241.100']);
  });
});
