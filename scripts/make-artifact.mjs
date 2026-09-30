// Post-build step.
// 1. Adds the three.js license notice to the built game (the minifier strips it).
// 2. Writes dist/monomachia.html: the same game as page content for a Claude
//    artifact. That publisher wraps the page in its own <html>/<head>/<body>
//    and supplies the charset and viewport meta tags, so we emit the remaining
//    head items plus the body.
//
// IMPORTANT: never run broad regexes over the whole file. The inline bundle
// contains three.js shader source such as "#include <metalnessmap_fragment>",
// which a pattern like /<meta[^>]*>/ would silently destroy.
import fs from 'fs';

let html = fs.readFileSync('dist/index.html', 'utf8');

// --- license notice for the bundled three.js code
const license = fs.readFileSync('node_modules/three/LICENSE', 'utf8').trim().replaceAll('--', '—');
const notice = `<!--\nMonomachia bundles three.js (https://threejs.org), used under this license:\n\n${license}\n-->`;
if (!html.includes('Monomachia bundles three.js')) {
  // after <title>: the charset tag must stay within the first 1024 bytes
  const at = html.indexOf('</title>');
  if (at < 0) throw new Error('no <title> in build');
  const withNotice = html.slice(0, at + '</title>'.length) + '\n' + notice + html.slice(at + '</title>'.length);
  fs.writeFileSync('dist/index.html', withNotice);
  html = withNotice;
}

// --- artifact page content
const headOpen = html.indexOf('<head>');
const headClose = html.lastIndexOf('</head>');
const bodyOpen = html.lastIndexOf('<body>');
const bodyClose = html.lastIndexOf('</body>');
if (headOpen < 0 || headClose < headOpen || bodyOpen < headClose || bodyClose < bodyOpen) {
  throw new Error('unexpected build layout');
}
let head = html.slice(headOpen + '<head>'.length, headClose);
const body = html.slice(bodyOpen + '<body>'.length, bodyClose);

// remove exactly the two meta tags we wrote in index.html (first occurrence only)
for (const tag of ['<meta charset="utf-8" />', '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />']) {
  const i = head.indexOf(tag);
  if (i < 0) throw new Error('meta tag not found: ' + tag);
  head = head.slice(0, i) + head.slice(i + tag.length);
}

// keep <title> first so it sits inside the first 8KB
const tStart = head.indexOf('<title>');
const tEnd = head.indexOf('</title>') + '</title>'.length;
const title = head.slice(tStart, tEnd);
const rest = (head.slice(0, tStart) + head.slice(tEnd)).trim();
const out = `${title}\n${rest}\n${body.trim()}\n`;

// safety check: the inline script must survive byte for byte
const scriptOf = (s) => {
  const a = s.indexOf('<script type="module"');
  const b = s.indexOf('</script>', a);
  return s.slice(a, b);
};
if (scriptOf(out) !== scriptOf(html) || scriptOf(out).length < 100000) throw new Error('inline script was altered');

fs.writeFileSync('dist/monomachia.html', out);
console.log('wrote dist/monomachia.html', (out.length / 1024).toFixed(0) + ' KB', '| title at', out.indexOf('<title>'), '| script intact | license notice added');
