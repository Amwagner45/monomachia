// Tests for tools/lanes-board/ui.mjs: the pure pieces both board pages draw
// with, the context gauge, its chart and the roadmap's summary tiles.

import { describe, expect, it } from 'vitest';
import {
  fallbackPhases, fmtTokens, gaugeHtml, gaugeLevel, phaseState, planAsPhase, roadmapKpis, sparkPoints, sparkSvg,
} from '../tools/lanes-board/ui.mjs';
import { pageFor } from '../tools/lanes-board/access.mjs';

const ctx = (tokens, window = 200_000, extra = {}) => ({
  model: 'claude-sonnet-4-6', tokens, window, pct: Math.round((tokens / window) * 1000) / 10,
  autoCompactAt: window, updated: 0, series: [], compactions: [], ...extra,
});

describe('fmtTokens', () => {
  it('writes token counts the short way', () => {
    expect(fmtTokens(0)).toBe('0');
    expect(fmtTokens(950)).toBe('950');
    expect(fmtTokens(1500)).toBe('1.5k');
    expect(fmtTokens(9000)).toBe('9k');
    expect(fmtTokens(143_210)).toBe('143k');
    expect(fmtTokens(967_000)).toBe('967k');
    expect(fmtTokens(1_000_000)).toBe('1M');
    expect(fmtTokens(1_250_000)).toBe('1.3M');
  });
});

describe('gaugeLevel', () => {
  it('is calm under 60%, amber from 60% to 85%, red above 85%', () => {
    expect(gaugeLevel(null)).toBe(null);
    expect(gaugeLevel(ctx(100_000))).toBe('calm');
    expect(gaugeLevel(ctx(119_000))).toBe('calm');
    expect(gaugeLevel(ctx(120_000))).toBe('warn');
    expect(gaugeLevel(ctx(170_000))).toBe('warn');
    expect(gaugeLevel(ctx(171_000))).toBe('high');
  });

  it('is red past the auto-compact line, wherever that is', () => {
    expect(gaugeLevel(ctx(130_000, 200_000, { autoCompactAt: 120_000 }))).toBe('high');
  });
});

describe('gaugeHtml', () => {
  it('draws nothing for a session with no context yet', () => {
    expect(gaugeHtml(null)).toBe('');
  });

  it('draws a compact meter with the rounded percent', () => {
    const html = gaugeHtml(ctx(57_400, 200_000), { live: true });
    expect(html).toContain('class="gauge calm fresh"');
    expect(html).toContain('width:28.7%');
    expect(html).toContain('>29%<');
    expect(html).toContain('title="Context: 57k of 200k tokens (28.7%)');
  });

  it('mutes a session that is no longer at work', () => {
    expect(gaugeHtml(ctx(57_400), { live: false })).toContain('class="gauge calm stale"');
  });

  it('draws the full meter with tokens, the exact percent and the auto-compact tick', () => {
    const html = gaugeHtml(ctx(287_495, 1_000_000, { autoCompactAt: 967_000, model: 'claude-opus-5-5' }), { live: true, full: true });
    expect(html).toContain('gauge full calm fresh');
    expect(html).toContain('287k / 1M');
    expect(html).toContain('28.7%');
    expect(html).toContain('left:96.7%');
    expect(html).toContain('auto-compacts at 967k');
    expect(html).toContain('claude-opus-5-5');
  });

  it('keeps the bar inside the meter past 100%', () => {
    expect(gaugeHtml(ctx(260_000), {})).toContain('width:100%');
  });

  it('says 100% on the compact meter only when the window is full', () => {
    expect(gaugeHtml(ctx(199_000), {})).toContain('>99%<');
    expect(gaugeHtml(ctx(200_000), {})).toContain('>100%<');
    expect(gaugeHtml(ctx(199_000), { full: true })).toContain('<b>99.5%</b>');
  });

  it('shows a session compacted since its last reply as just compacted, with an empty, calm meter', () => {
    const c = ctx(0, 200_000, { tokens: null, pct: null, compacted: true, before: 190_000 });
    expect(gaugeLevel(c)).toBe('calm');
    const html = gaugeHtml(c, { live: true });
    expect(html).toContain('width:0%');
    expect(html).toContain('>compacted<');
    expect(html).toContain('title="Context: compacted from 190k of 200k tokens; the next reply shows the new fill');
    const full = gaugeHtml(c, { full: true });
    expect(full).toContain('<b>Compacted</b> from 190k / 200k');
    expect(full).not.toContain('NaN');
    expect(full).not.toContain('null');
  });

  it('escapes the model name', () => {
    expect(gaugeHtml(ctx(1000, 200_000, { model: '<x>' }), { full: true })).not.toContain('<x>');
  });
});

describe('sparkPoints', () => {
  it('spreads the turns over the width by time and scales the height to the window', () => {
    const c = ctx(100_000, 200_000, { series: [{ t: 1000, tokens: 0 }, { t: 2000, tokens: 100_000 }, { t: 5000, tokens: 200_000 }] });
    const pts = sparkPoints(c, 100, 40);
    expect(pts.map((p) => p.x)).toEqual([0, 25, 100]);
    expect(pts.map((p) => p.y)).toEqual([40, 20, 0]);
    expect(pts[1]).toMatchObject({ t: 2000, tokens: 100_000 });
  });

  it('spaces turns evenly when they share one time, and keeps a point above the window on the chart', () => {
    const c = ctx(0, 200_000, { series: [{ t: 5, tokens: 300_000 }, { t: 5, tokens: 50_000 }] });
    const pts = sparkPoints(c, 100, 40);
    expect(pts.map((p) => p.x)).toEqual([0, 100]);
    expect(pts[0].y).toBe(0);
  });

  it('has no points without a series', () => {
    expect(sparkPoints(null, 100, 40)).toEqual([]);
    expect(sparkPoints(ctx(1), 100, 40)).toEqual([]);
  });
});

describe('sparkSvg', () => {
  const series = [{ t: 1000, tokens: 40_000 }, { t: 2000, tokens: 150_000 }, { t: 3000, tokens: 30_000 }, { t: 4000, tokens: 60_000 }];

  it('draws a scalable chart with a hover title on each turn', () => {
    const svg = sparkSvg(ctx(60_000, 200_000, { series }));
    expect(svg).toMatch(/^<svg[^>]*viewBox="0 0 \d+ \d+"[^>]*preserveAspectRatio="none"/);
    expect(svg).toContain('width="100%"');
    expect(svg.match(/<title>/g)).toHaveLength(4);
    expect(svg).toContain('150k');
  });

  it('marks each compaction with a small vertical tick', () => {
    const svg = sparkSvg(ctx(60_000, 200_000, { series, compactions: [2500] }));
    expect(svg.match(/class="sc"/g)).toHaveLength(1);
  });

  it('says when the session has just compacted', () => {
    const svg = sparkSvg(ctx(0, 200_000, { series, tokens: null, pct: null, compacted: true, before: 60_000 }));
    expect(svg).toContain('aria-label="Context turn by turn, just compacted"');
  });

  it('draws the auto-compact line', () => {
    expect(sparkSvg(ctx(60_000, 200_000, { series, autoCompactAt: 150_000 }))).toContain('class="sa"');
  });

  it('draws nothing without at least one turn', () => {
    expect(sparkSvg(null)).toBe('');
    expect(sparkSvg(ctx(1))).toBe('');
  });
});

// /data plans and lanes, cut down.
const t = (title, status) => ({ title, status, blockers: [], ownerOk: [], gate: false, moved: null, movedTo: null, replaces: [] });
const plan = (key, name, tasks, extra = {}) => ({
  key, short: key.toUpperCase(), name, kind: 'flat', closed: false, branch: 'b', file: `${key}.md`,
  stages: [{ n: 1, name: 'All', ids: Object.keys(tasks) }], tasks,
  counts: Object.values(tasks).reduce((c, x) => ({ ...c, [x.status]: (c[x.status] ?? 0) + 1 }), {}),
  total: Object.values(tasks).filter((x) => !['moved', 'retired'].includes(x.status)).length, ...extra,
});
const GR = plan('gr', 'Godot rebuild', {
  '25.4': t('Credits', 'ready'), '25.5': t('Release', 'blocked'), '26.1': t('Node tests', 'done'),
  '18.4': t('Moved one', 'moved'), '12.9': t('Retired one', 'retired'), '18.11': t('Flashes', 'ready'),
});
const AA = plan('aa', 'Authored animation', { 1: t('Old', 'done') }, { closed: true });
const lane = (extra) => ({ folder: 'wt', branch: 'lane/gr-25.4', plan: 'gr', task: '25.4', scope: ['25.4'], working: true, ended: false, activity: 'active', ...extra });

describe('planAsPhase', () => {
  it('stands a plan in for a phase: its live tasks in build order, counts, ready tasks next and its lanes', () => {
    const ph = planAsPhase(GR, [lane(), lane({ plan: 'aa', folder: 'other' }), lane({ ended: true, folder: 'gone' })]);
    expect(ph.name).toBe('Godot rebuild');
    expect(ph.refs).toEqual(['gr:25.4', 'gr:25.5', 'gr:26.1', 'gr:18.11']);
    expect(ph.total).toBe(4);
    expect(ph.counts).toMatchObject({ done: 1, open: 3, ready: 2, blocked: 1 });
    expect(ph.next.map((x) => x.ref)).toEqual(['gr:25.4', 'gr:18.11']);
    expect(ph.lanes.map((l) => l.folder)).toEqual(['wt']);
    expect(ph.lanes[0]).toMatchObject({ task: 'gr:25.4', working: true });
  });
});

describe('fallbackPhases', () => {
  it('lists the open plans as phases until the roadmap is written, the first with open tasks current', () => {
    const done = plan('m1', 'Milestone 1', { 1: t('Done', 'done') });
    const phases = fallbackPhases({ plans: [done, GR, AA], lanes: [] });
    expect(phases.map((p) => p.name)).toEqual(['Milestone 1', 'Godot rebuild']);
    expect(phases.map((p) => p.current)).toEqual([false, true]);
  });
});

describe('phaseState', () => {
  const ph = (extra) => ({ current: false, total: 3, counts: { open: 1 }, waiting: [], ...extra });
  it('tells current, done, later and unwritten phases apart', () => {
    expect(phaseState(ph({ current: true }))).toBe('current');
    expect(phaseState(ph({ counts: { open: 0 } }))).toBe('done');
    expect(phaseState(ph({}))).toBe('later');
    expect(phaseState(ph({ total: 0, counts: { open: 0 }, waiting: ['m1:*'] }))).toBe('unwritten');
    expect(phaseState(ph({ total: 0, counts: { open: 0 } }))).toBe('empty');
  });

  it('keeps a phase whose plan is still unwritten open even when its written tasks are done', () => {
    expect(phaseState(ph({ total: 2, counts: { open: 0 }, waiting: ['m1:*'] }))).toBe('later');
  });
});

describe('roadmapKpis', () => {
  const phase = (n, name, refs, extra = {}) => ({ n, name, alongside: null, current: false, refs, unknown: [], waiting: [], total: refs.length, counts: {}, next: [], lanes: [], ...extra });

  it('sums the current phases, an alongside one with its partner, without counting a task twice', () => {
    const data = {
      plans: [GR], lanes: [lane(), lane({ working: false, activity: 'recent', folder: 'b' })],
      roadmap: { phases: [
        phase(1, 'Consolidation', ['gr:26.1'], {}),
        phase(2, 'Milestone 1', ['gr:25.4', 'gr:25.5'], { current: true }),
        phase(3, 'Master follow-ups', ['gr:18.11', 'gr:25.4'], { current: true, alongside: 2 }),
      ] },
    };
    const k = roadmapKpis(data);
    expect(k.current).toMatchObject({ names: ['Milestone 1', 'Master follow-ups'], done: 0, total: 3, open: 3, ready: 2, blocked: 1, fallback: false });
    expect(k.readyRefs).toEqual(['gr:25.4', 'gr:18.11']);
    expect(k.m1).toBe(null);
    expect(k.activeLanes).toBe(1);
    expect(k.onTask).toBe(1);
  });

  it('counts milestone 1 from its plan once it has a copy', () => {
    const m1 = plan('m1', 'Milestone 1', { 1: t('A', 'done'), 2: t('B', 'ready'), 3: t('C', 'moved') });
    const k = roadmapKpis({ plans: [m1, GR], lanes: [], roadmap: { phases: [phase(1, 'M1', ['m1:1', 'm1:2'], { current: true })] } });
    expect(k.m1).toEqual({ done: 1, total: 2, ready: 1 });
  });

  it('falls back to the first open plan while the roadmap has no copy', () => {
    const k = roadmapKpis({ plans: [GR, AA], lanes: [], roadmap: null });
    expect(k.current).toMatchObject({ names: ['Godot rebuild'], fallback: true, total: 4, done: 1 });
  });

  it('has no current phase when everything is done', () => {
    const k = roadmapKpis({ plans: [AA], lanes: [], roadmap: null });
    expect(k.current).toMatchObject({ names: [], total: 0 });
  });
});

describe('the board serves ui.mjs to its pages', () => {
  it('as JavaScript', () => {
    expect(pageFor('/ui.mjs', '')).toEqual({ file: 'ui.mjs', type: 'text/javascript; charset=utf-8' });
  });
});
