#!/usr/bin/env node
// Task runner for the Godot project in game/. Finds the Godot executable, runs
// it with a watchdog (a GDScript runtime error in a --script run hangs Godot
// instead of exiting), and scans the output for script errors.
//
// usage: node scripts/godot.mjs <command> [args...]
//   import                 re-import assets and refresh the script class cache
//   test [gut args...]     run the GUT tests headless
//   typecheck              load every script; fail on parse or type errors
//   soak [matches]         computer-vs-computer matches with balance numbers
//   script <res://path.gd> [-- user args]   run a SceneTree tool script headless
//   shots <scene> [out.png] [frames]        render a scene in an off-screen window
//   run                    play the game
//   dev                    open the editor
//   build                  export the Windows build to build/windows/
//
// Godot is found through the GODOT environment variable, then `godot` or
// `godot4` on PATH, then common install folders (including Downloads).

import { spawn, spawnSync } from 'node:child_process';
import { existsSync, readdirSync, statSync, mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const PROJECT = join(ROOT, 'game');
const WIN = process.platform === 'win32';

function onPath(name) {
  const r = spawnSync(WIN ? 'where' : 'which', [name], { encoding: 'utf8' });
  if (r.status !== 0) return null;
  const first = r.stdout.split(/\r?\n/).find((l) => l.trim());
  return first ? first.trim() : null;
}

/** Depth-limited search for a Godot 4.7 executable under a folder. */
function searchDir(dir, depth) {
  if (!existsSync(dir) || depth < 0) return null;
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return null;
  }
  const hits = [];
  for (const e of entries) {
    if (!/godot/i.test(e)) continue;
    const p = join(dir, e);
    let st;
    try {
      st = statSync(p);
    } catch {
      continue;
    }
    if (st.isFile() && /^Godot_v4\.7[^/\\]*(_console\.exe|\.exe|\.x86_64)$/i.test(e) && !/\.zip$/i.test(e)) hits.push(p);
    else if (st.isDirectory()) {
      const inner = searchDir(p, depth - 1);
      if (inner) hits.push(inner);
    }
  }
  // Prefer the console wrapper on Windows: it forwards stdout and the exit code.
  hits.sort((a, b) => Number(/_console\.exe$/i.test(b)) - Number(/_console\.exe$/i.test(a)));
  return hits[0] ?? null;
}

export function findGodot() {
  if (process.env.GODOT && existsSync(process.env.GODOT)) return process.env.GODOT;
  for (const name of ['godot', 'godot4']) {
    const p = onPath(name);
    if (p) return p;
  }
  const home = homedir();
  const dirs = [
    join(home, 'Downloads'),
    join(home, 'Desktop'),
    join(home, 'Documents'),
    join(home, 'AppData', 'Local', 'Programs'),
    join(home, 'AppData', 'Local'),
    'C:\\Program Files',
    'C:\\Program Files (x86)',
    join(home, 'scoop', 'apps'),
    join(home, 'Applications'),
    '/Applications',
    '/usr/local/bin',
  ];
  for (const d of dirs) {
    const p = searchDir(d, 2);
    if (p) return p;
  }
  return null;
}

function die(msg) {
  console.error(msg);
  process.exit(1);
}

const ERROR_PATTERNS = [/SCRIPT ERROR/, /Parse Error/, /Failed to load script/, /^ERROR: .*\.gd/m];

/**
 * Run Godot with a timeout. Resolves with {code, output}. Output is streamed
 * through unless quiet is set.
 */
function runGodot(godot, args, { timeoutMs = 600000, quiet = false, cwd = PROJECT } = {}) {
  return new Promise((res) => {
    const child = spawn(godot, args, { cwd, stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    const onData = (stream) => (buf) => {
      const s = buf.toString();
      output += s;
      if (!quiet) stream.write(s);
    };
    child.stdout.on('data', onData(process.stdout));
    child.stderr.on('data', onData(process.stderr));
    const timer = setTimeout(() => {
      console.error(`\ngodot.mjs: timed out after ${Math.round(timeoutMs / 1000)} s; stopping Godot.`);
      child.kill('SIGKILL');
    }, timeoutMs);
    child.on('close', (code, signal) => {
      clearTimeout(timer);
      res({ code: code ?? (signal ? 124 : 1), output });
    });
  });
}

const hasScriptErrors = (out) => ERROR_PATTERNS.some((re) => re.test(out));

async function importProject(godot) {
  const r = await runGodot(godot, ['--headless', '--path', PROJECT, '--import'], { quiet: true, timeoutMs: 900000 });
  if (r.code !== 0) {
    process.stderr.write(r.output);
    die(`godot.mjs: import failed (exit ${r.code}).`);
  }
}

async function main() {
  const [cmd = 'help', ...rest] = process.argv.slice(2);
  if (cmd === 'help' || cmd === '--help') {
    console.log('usage: node scripts/godot.mjs import|test|typecheck|soak|script|shots|run|dev|build');
    return;
  }
  const godot = findGodot();
  if (!godot) {
    die(
      'godot.mjs: Godot 4.7 not found. Install it, then either put it on PATH as `godot` or set the GODOT ' +
        'environment variable to the executable (on Windows, the *_console.exe file).',
    );
  }

  switch (cmd) {
    case 'path':
      console.log(godot);
      return;
    case 'import':
      await importProject(godot);
      console.log('godot.mjs: import done.');
      return;
    case 'test': {
      await importProject(godot);
      const r = await runGodot(godot, ['--headless', '--path', PROJECT, '-s', 'res://addons/gut/gut_cmdln.gd', ...rest], {
        timeoutMs: 900000,
      });
      if (r.code !== 0) process.exit(r.code);
      if (/Failing Tests|\[Failed\]/.test(r.output)) process.exit(1);
      return;
    }
    case 'typecheck': {
      await importProject(godot);
      const r = await runGodot(godot, ['--headless', '--path', PROJECT, '--script', 'res://tools/typecheck.gd'], {
        timeoutMs: 300000,
      });
      if (r.code !== 0 || hasScriptErrors(r.output)) die('godot.mjs: typecheck failed.');
      return;
    }
    case 'soak': {
      await importProject(godot);
      const r = await runGodot(godot, ['--headless', '--path', PROJECT, '--script', 'res://tools/soak.gd', '--', ...rest], {
        timeoutMs: 3600000,
      });
      process.exit(r.code);
      return;
    }
    case 'script': {
      const [scriptPath, ...userArgs] = rest;
      if (!scriptPath) die('usage: node scripts/godot.mjs script res://tools/x.gd [-- args]');
      await importProject(godot);
      const r = await runGodot(godot, ['--headless', '--path', PROJECT, '--script', scriptPath, ...userArgs], {
        timeoutMs: 3600000,
      });
      if (r.code === 0 && hasScriptErrors(r.output)) die('godot.mjs: script reported errors.');
      process.exit(r.code);
      return;
    }
    case 'shots': {
      // Renders a scene in a real (off-screen) window: Movie Maker and viewport
      // capture do not work with --headless.
      const [scene = 'res://scenes/main.tscn', out = join(ROOT, 'shots', 'shot.png'), frames = '30'] = rest;
      mkdirSync(dirname(resolve(out)), { recursive: true });
      await importProject(godot);
      const r = await runGodot(
        godot,
        [
          '--path', PROJECT, '--position', '-3000,-3000', '--resolution', '1600x900', '--fixed-fps', '60',
          '--script', 'res://tools/shot.gd', '--', `--scene=${scene}`, `--out=${resolve(out)}`, `--frames=${frames}`,
        ],
        { timeoutMs: 300000 },
      );
      process.exit(r.code);
      return;
    }
    case 'run':
      spawn(godot, ['--path', PROJECT, ...rest], { stdio: 'inherit', detached: true }).unref();
      return;
    case 'dev':
      spawn(godot, ['--path', PROJECT, '-e', ...rest], { stdio: 'inherit', detached: true }).unref();
      return;
    case 'build': {
      await importProject(godot);
      const outDir = join(ROOT, 'build', 'windows');
      mkdirSync(outDir, { recursive: true });
      const r = await runGodot(
        godot,
        ['--headless', '--path', PROJECT, '--export-release', 'Windows Desktop', join(outDir, 'Monomachia.exe')],
        { timeoutMs: 1800000 },
      );
      if (r.code !== 0 && /No export template found/.test(r.output)) {
        die(
          'godot.mjs: Windows export templates are not installed. In the Godot editor, open Editor → Manage Export ' +
            'Templates and download 4.7.2 (about 1.3 GB), or let CI build the Windows version.',
        );
      }
      process.exit(r.code);
      return;
    }
    default:
      die(`godot.mjs: unknown command "${cmd}".`);
  }
}

main();
