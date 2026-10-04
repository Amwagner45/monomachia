// The lanes board: a live page of every plan and every worktree in the
// Monomachia repo. It reads the plans from every branch and worktree, each
// worktree's git state and its Claude Code session's last activity, so it
// follows the other sessions without anyone asking. From the page you can queue
// tasks and launch a desktop-app session to build them, end a launched
// session's work, and open the second brain. It never fetches or takes git locks.
//   npm run board   ->   http://localhost:5197
// State shared by every checkout (launch records, the stop list) lives outside
// the repo: ~/.claude/lanes-board/ and ~/.claude/lanes-stop.json.
import { createServer } from 'node:http';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, readdir, stat, access, writeFile, open, mkdir } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import os from 'node:os';
import path from 'node:path';
import { PLANS, PLAN_BY_KEY, parsePlan, mergeCopies, goalFor } from './plans.mjs';

const run = promisify(execFile);
const HERE = path.dirname(fileURLToPath(import.meta.url));
const STATE = process.env.LANES_STATE ?? path.join(os.homedir(), '.claude', 'lanes-board');
const PORT = Number(process.env.PORT || 5197);
const CACHE_MS = 4000;
const ACTIVE_MS = 3 * 60 * 1000; // a session that wrote its transcript this recently is at work
const RECENT_MS = 60 * 60 * 1000;
const PROJECTS = path.join(os.homedir(), '.claude', 'projects');
// Files that don't mean a worktree is mid-task: local tooling, and Godot's
// re-save of the bus layout on a test run.
const IGNORED_DIRTY = [/^\.claude\//, /^game\/default_bus_layout\.tres$/];

async function git(cwd, ...args) {
  const { stdout } = await run('git', ['--no-optional-locks', ...args], { cwd, maxBuffer: 64 << 20, windowsHide: true });
  return stdout;
}
async function tryGit(cwd, ...args) {
  try { return await git(cwd, ...args); } catch { return null; }
}
async function pool(items, n, fn) {
  const out = new Array(items.length);
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    while (i < items.length) { const k = i++; out[k] = await fn(items[k], k); }
  }));
  return out;
}

// The main checkout is the parent of the shared .git folder, wherever this runs from.
const REPO = process.env.REPO
  ?? path.dirname(path.resolve(HERE, (await git(HERE, 'rev-parse', '--git-common-dir')).trim()));

// ---------- plan parsing (rules in plans.mjs) ----------

const parseCache = new Map(); // `${plan}:${blob sha}` -> parsed
function parse(plan, text, blob) {
  const key = blob && `${plan.key}:${blob}`;
  if (key && parseCache.has(key)) return parseCache.get(key);
  const parsed = parsePlan(plan, text);
  if (key) parseCache.set(key, parsed);
  return parsed;
}

// ---------- git state ----------

async function worktrees() {
  const out = await git(REPO, 'worktree', 'list', '--porcelain');
  const list = [];
  let cur = null;
  for (const line of out.split(/\r?\n/)) {
    if (line.startsWith('worktree ')) list.push(cur = { path: path.normalize(line.slice(9)), branch: null, head: null, locked: false });
    else if (!cur) continue;
    else if (line.startsWith('HEAD ')) cur.head = line.slice(5);
    else if (line.startsWith('branch ')) cur.branch = line.slice(7).replace('refs/heads/', '');
    else if (line.startsWith('locked')) cur.locked = true;
  }
  return list;
}

const blobCache = new Map(); // `${commit}:${file}` -> { blob, time } | null
async function planAt(commit, file) {
  const key = `${commit}:${file}`;
  if (!blobCache.has(key)) {
    const blob = (await tryGit(REPO, 'rev-parse', '-q', '--verify', `${commit}:${file}`))?.trim() || null;
    const time = blob ? Number((await tryGit(REPO, 'log', '-1', '--format=%ct', commit, '--', file))?.trim()) || 0 : 0;
    blobCache.set(key, blob ? { blob, time } : null);
  }
  return blobCache.get(key);
}
const textCache = new Map();
async function blobText(blob) {
  if (!textCache.has(blob)) textCache.set(blob, (await tryGit(REPO, 'cat-file', 'blob', blob)) ?? '');
  return textCache.get(blob);
}

// Things that only change when HEAD moves are cached by commit.
const historyCache = new Map();
async function history(dir, head) {
  const key = `${dir}:${head}`;
  if (!historyCache.has(key)) {
    const out = (await tryGit(dir, 'log', '--first-parent', '-40', '--format=%x1e%ct%x09%s', '--name-only')) ?? '';
    historyCache.set(key, out.split('\x1e').filter(Boolean).map((chunk) => {
      const [line, ...files] = chunk.split(/\r?\n/).filter(Boolean);
      const [time, ...subj] = line.split('\t');
      return { time: Number(time), subject: subj.join('\t'), files };
    }));
  }
  return historyCache.get(key);
}
let refTips = new Map();
const countCache = new Map();
async function aheadBehind(head, target) {
  const tip = refTips.get(target);
  if (!head || !tip) return [null, null];
  const key = `${head}:${tip}`;
  if (!countCache.has(key)) {
    const c = (await tryGit(REPO, 'rev-list', '--left-right', '--count', `${head}...${tip}`))?.trim().split(/\s+/).map(Number);
    countCache.set(key, c?.length === 2 ? c : [null, null]);
  }
  return countCache.get(key);
}
// A worktree's .git is a file naming its git folder; the main checkout's is the folder.
async function isMerging(dir) {
  let gitDir = path.join(dir, '.git');
  try {
    const m = (await readFile(gitDir, 'utf8')).match(/^gitdir:\s*(.+)$/m);
    if (m) gitDir = path.resolve(dir, m[1].trim());
  } catch { /* a folder, not a file */ }
  return access(path.join(gitDir, 'MERGE_HEAD')).then(() => true, () => false);
}

// A Claude Code session's transcripts live in a folder named after its working directory.
const transcriptDir = (dir) => path.join(PROJECTS, dir.replace(/[^A-Za-z0-9]/g, '-'));
async function sessionActivity(dir) {
  const folder = transcriptDir(dir);
  try {
    const names = (await readdir(folder)).filter((n) => n.endsWith('.jsonl'));
    const times = await Promise.all(names.map((n) => stat(path.join(folder, n)).then((s) => s.mtimeMs, () => 0)));
    return Math.max(0, ...times) || null;
  } catch { return null; }
}

// The desktop app keeps one record per Code session, naming its worktree.
const APP_SESSIONS = path.join(process.env.APPDATA ?? path.join(os.homedir(), 'AppData', 'Roaming'), 'Claude', 'claude-code-sessions');
async function appSessions() {
  const out = [];
  const walk = async (dir, depth) => {
    let entries;
    try { entries = await readdir(dir, { withFileTypes: true }); } catch { return; }
    for (const e of entries) {
      const p = path.join(dir, e.name);
      if (e.isDirectory() && depth < 2) await walk(p, depth + 1);
      else if (e.isFile() && /^local_.*\.json$/.test(e.name)) {
        try {
          const r = JSON.parse(await readFile(p, 'utf8'));
          out.push({ id: r.sessionId, cli: r.cliSessionId, title: r.title ?? '', archived: !!r.isArchived,
            dir: path.normalize(r.worktreePath ?? r.cwd ?? '').toLowerCase(), activity: r.lastActivityAt ?? 0, created: r.createdAt ?? 0 });
        } catch { /* being written */ }
      }
    }
  };
  await walk(APP_SESSIONS, 0);
  return out;
}

// A session is waiting on you when its transcript ends on a question with no answer yet.
async function waitingQuestion(dir, cli) {
  if (!cli) return null;
  const file = path.join(transcriptDir(dir), `${cli}.jsonl`);
  try {
    const { size } = await stat(file);
    const fh = await open(file, 'r');
    const len = Math.min(size, 256 * 1024);
    const buf = Buffer.alloc(len);
    await fh.read(buf, 0, len, size - len);
    await fh.close();
    const text = buf.toString('utf8');
    const asks = [...text.matchAll(/"type":"tool_use","id":"(toolu_[A-Za-z0-9]+)","name":"AskUserQuestion","input":\{"questions":\[\{"question":"((?:[^"\\]|\\.)*)"/g)];
    const ask = asks.at(-1);
    if (!ask) return null;
    if (text.includes(`"tool_use_id":"${ask[1]}"`)) return null;
    return JSON.parse(`"${ask[2]}"`);
  } catch { return null; }
}

// Launches the board started, kept in the state folder so every checkout's board shares them.
const LAUNCHES = path.join(STATE, 'launches.json');
await mkdir(STATE, { recursive: true });
let launches = [];
try { launches = JSON.parse(await readFile(LAUNCHES, 'utf8')); } catch { launches = []; }
const LAUNCH_FRESH_MS = 48 * 60 * 60 * 1000;

let prs = [];
let prsAt = 0;
let prsBusy = false;
function refreshPrs() {
  if (prsBusy || Date.now() - prsAt < 60_000) return;
  prsBusy = true;
  run('gh', ['pr', 'list', '--state', 'open', '--json', 'number,title,headRefName,baseRefName,isDraft,url'], { cwd: REPO, windowsHide: true, timeout: 20_000 })
    .then(({ stdout }) => { prs = JSON.parse(stdout); }, () => {})
    .finally(() => { prsAt = Date.now(); prsBusy = false; });
}

// ---------- the board ----------

const SUBJECT_TASK = { gr: /\(task (\d+b?\.\d+)\)/, aa: /\((?:authored animation )?task (\d+)\)/ };

async function collect() {
  refreshPrs();
  const refsOut = (await tryGit(REPO, 'for-each-ref', '--format=%(objectname) %(refname:short)', 'refs/heads', 'refs/remotes/origin')) ?? '';
  const refs = refsOut.split(/\r?\n/).filter(Boolean).map((l) => { const [sha, name] = l.split(' '); return { sha, name }; })
    .filter((r) => r.name !== 'origin/HEAD' && r.name !== 'origin');
  refTips = new Map(refs.map((r) => [r.name, r.sha]));
  const trees = await worktrees();

  // Every committed copy of every plan, on every branch.
  const shas = [...new Set(refs.map((r) => r.sha))];
  const copies = {};
  for (const plan of PLANS) {
    const found = await pool(shas, 8, async (sha) => ({ sha, at: await planAt(sha, plan.file) }));
    copies[plan.key] = found.filter((f) => f.at);
  }

  // Worktree files, for ticks not committed yet.
  const treeFiles = await pool(trees, 6, async (w) => {
    const files = {};
    for (const plan of PLANS) {
      try { files[plan.key] = await readFile(path.join(w.path, plan.file), 'utf8'); } catch { /* not on this branch */ }
    }
    return files;
  });

  const plans = [];
  const status = new Map(); // 'gr:12.2' -> status
  for (const plan of PLANS) {
    const list = copies[plan.key];
    if (!list.length) continue;
    const parsed = await Promise.all(list.map(async (c) => ({ time: c.at.time, p: parse(plan, await blobText(c.at.blob), c.at.blob) })));
    const { tasks, stages, done, retired } = mergeCopies(parsed);
    const base = { tasks, stages };
    const working = new Set();
    for (const files of treeFiles) {
      if (!files[plan.key]) continue;
      for (const t of parse(plan, files[plan.key]).tasks.values()) {
        if (t.mark === 'x' && !done.has(t.id)) working.add(t.id);
        if (plan.kind === 'steps' && t.ticked > 0 && t.mark !== 'x') {
          const committed = base.tasks.get(t.id);
          if (!committed || t.ticked > committed.ticked) working.add(t.id);
        }
      }
    }
    plans.push({ plan, base, done, retired, working });
  }

  const isDone = (ref) => {
    const [k, id] = ref.split(':');
    const p = plans.find((x) => x.plan.key === k);
    return !!p && (p.done.has(id) || p.retired.has(id));
  };

  // Lanes: every worktree.
  const now = Date.now();
  const sessions = await appSessions();

  // Each launch's session is the app session created just after it, wherever it
  // opened (the app sometimes puts it in a scratch folder).
  let linked = false;
  for (const l of launches) {
    if (l.session) continue;
    const taken = new Set(launches.map((x) => x.session?.id).filter(Boolean));
    const s = sessions.filter((x) => !taken.has(x.id) && x.created >= l.time - 10_000 && x.created <= l.time + 180_000)
      .sort((a, b) => a.created - b.created)[0];
    if (s) { l.session = { id: s.id, cli: s.cli }; linked = true; }
  }
  if (linked) await writeFile(LAUNCHES, JSON.stringify(launches, null, 2));
  const stops = await readStops();
  const lanes = await pool(trees, 10, async (w, i) => {
    const st = (await tryGit(w.path, 'status', '--porcelain')) ?? '';
    const dirty = st.split(/\r?\n/).filter(Boolean).map((l) => l.slice(3).replace(/^"|"$/g, ''))
      .filter((f) => !IGNORED_DIRTY.some((r) => r.test(f)));
    const merging = await isMerging(w.path);
    const log = await history(w.path, w.head);
    const last = log[0] ?? { time: null, subject: '' };

    // Which plan the worktree works on: its branch name, else the newest own
    // commit that touched a plan or named a task.
    let planKey = null;
    let claims = true; // only worktrees on a plan's own branches take its tasks
    const b = w.branch ?? '';
    // A launched lane names its plan and tasks in its branch: lane/gr-22.2-22.3.
    const launched = b.match(/^lane\/(gr|aa|st)-(.+)$/);
    let scope = null;
    if (launched) { planKey = launched[1]; scope = launched[2].split('-').filter(Boolean); }
    else if (b === 'tools/session-tracker') planKey = 'st';
    else if (/authored-animation/.test(b)) planKey = 'aa';
    else if (b === 'feature/godot-rebuild' || /^godot\//.test(b)) planKey = 'gr';
    if (!planKey) {
      claims = false;
      for (const c of log) {
        const hit = PLANS.find((p) => c.files.includes(p.file)) ?? (SUBJECT_TASK.gr.test(c.subject) ? PLAN_BY_KEY.gr : null);
        if (hit) { planKey = hit.key; break; }
      }
    }
    let lastTask = null;
    if (planKey && SUBJECT_TASK[planKey]) {
      for (const c of log) { const m = c.subject.match(SUBJECT_TASK[planKey]); if (m) { lastTask = m[1]; break; } }
    }

    // Commits not yet on the plan's branch on GitHub (or master for other work).
    const target = planKey ? `origin/${PLAN_BY_KEY[planKey].branch}` : 'origin/master';
    const [ahead, behind] = await aheadBehind(w.head, target);
    const session = await sessionActivity(w.path);
    const pr = prs.find((p) => p.headRefName === w.branch) ?? null;
    const app = sessions.filter((s) => s.dir === path.normalize(w.path).toLowerCase())
      .sort((x, y) => (x.archived - y.archived) || (y.activity - x.activity))[0] ?? null;
    const question = app && !app.archived ? await waitingQuestion(w.path, app.cli) : null;
    const own = treeFiles[i];

    let activity = 'idle';
    if (session && now - session < ACTIVE_MS) activity = 'active';
    else if ((session && now - session < RECENT_MS) || (last.time && now - last.time * 1000 < RECENT_MS)) activity = 'recent';

    let state;
    if (merging) state = 'merging';
    else if (dirty.length) state = 'dirty';
    else if (ahead) state = 'ahead';
    else state = 'clean';

    return {
      folder: path.relative(REPO, w.path) || path.basename(w.path),
      path: w.path, main: w.path === path.normalize(REPO), branch: w.branch, head: w.head?.slice(0, 7), locked: w.locked,
      plan: planKey, claims, scope, lastTask,
      app: app && { id: app.id, title: app.title, archived: app.archived }, question, target, ahead, behind, dirty: dirty.length, merging, state, activity,
      session, last: { time: last.time, subject: last.subject },
      pr: pr && { number: pr.number, url: pr.url, draft: pr.isDraft, base: pr.baseRefName },
      // Plan ticks in this worktree's file that no branch has committed yet.
      uncommittedTicks: planKey && own[planKey]
        ? [...parse(PLAN_BY_KEY[planKey], own[planKey]).tasks.values()].filter((t) => t.mark === 'x').map((t) => t.id)
        : [],
    };
  });

  // Each plan lane's current or next task.
  for (const lane of lanes) {
    const p = plans.find((x) => x.plan.key === lane.plan);
    if (!p) continue;
    lane.uncommittedTicks = lane.uncommittedTicks.filter((id) => !p.done.has(id));
    const order = p.base.stages.flatMap((s) => s.ids).filter((id) => !lane.scope || lane.scope.includes(id));
    const open = (id) => !p.done.has(id) && !p.retired.has(id);
    const ready = (id) => (p.base.tasks.get(id)?.blockers ?? []).every(isDone);
    const from = lane.lastTask ? order.indexOf(lane.lastTask) : -1;
    const pick = (from >= 0 ? order.slice(from + 1) : order).find((id) => open(id) && ready(id))
      ?? order.find((id) => open(id) && ready(id)) ?? order.find(open) ?? null;
    lane.task = pick;
    lane.taskTitle = pick ? p.base.tasks.get(pick)?.title ?? '' : '';
    const t = pick && p.base.tasks.get(pick);
    lane.taskWaits = t ? (t.gatedBy ?? []).filter((g) => isDone(g)).map((g) => g.split(':')[1]) : [];
    lane.taskBlocked = t ? t.blockers.filter((x) => !isDone(x)) : [];
    // A lane with uncommitted work, or a live session with commits of its own,
    // is taken to be on its next task. (A session that only reads, like a
    // chart, has neither.)
    // A launched lane's session counts from its first answer to wayfinder's questions.
    const busy = lane.uncommittedTicks.length > 0 || (lane.claims
      && (lane.state === 'dirty' || lane.state === 'merging' || (lane.activity === 'active' && (lane.ahead > 0 || !!lane.scope))));
    // Launching a task is the owner's OK, so a launched lane doesn't wait on it.
    // A lane whose launch was ended from the board takes no task.
    lane.ended = launches.find((l) => l.endedAt && l.branch === lane.branch) ? true : false;
    lane.working = !lane.ended && !!(pick && busy && ready(pick) && (!lane.taskWaits.length || lane.scope));
    if (lane.working) p.working.add(pick);
  }

  // A launched task stays marked until a lane starts it, for two days at most.
  const launchOf = (ref) => launches.find((l) => !l.endedAt && now - l.time < LAUNCH_FRESH_MS && l.tasks.includes(ref)) ?? null;
  // The launch a task belongs to, ended or not, for the board's End menu.
  const launchView = (l) => {
    const stop = stops.find((s) => s.id === l.id);
    return { id: l.id, time: l.time, branch: l.branch, tasks: l.tasks, session: l.session?.id ?? null,
      endedAt: l.endedAt ?? null, stoppedAt: stop?.firedAt ?? null };
  };

  // Task statuses.
  const out = [];
  for (const p of plans) {
    const tasks = {};
    for (const t of p.base.tasks.values()) {
      const ref = `${p.plan.key}:${t.id}`;
      let s;
      if (p.retired.has(t.id)) s = 'retired';
      else if (p.done.has(t.id)) s = 'done';
      else if (p.working.has(t.id)) s = 'working';
      else if (launchOf(ref)) s = 'launched';
      else if (!t.blockers.every(isDone)) s = 'blocked';
      else if ((t.gatedBy ?? []).length) s = 'owner';
      else s = 'ready';
      status.set(ref, s);
      tasks[t.id] = {
        title: t.title, status: s, gate: t.gate,
        blockers: t.blockers.map((x) => ({ ref: x, label: x.startsWith(`${p.plan.key}:`) ? x.split(':')[1] : `${PLAN_BY_KEY[x.split(':')[0]]?.name ?? x.split(':')[0]} ${x.split(':')[1]}`, done: isDone(x) })),
        ownerOk: (t.gatedBy ?? []).map((g) => g.split(':')[1]),
        launchedAt: s === 'launched' ? launchOf(ref).time : null,
      };
    }
    const inStages = new Set(p.base.stages.flatMap((s) => s.ids));
    const stages = p.base.stages.map((s) => ({ n: s.n, name: s.name, ids: s.ids }));
    const extra = [...p.base.tasks.keys()].filter((id) => !inStages.has(id));
    if (extra.length && p.plan.kind !== 'steps') stages.push({ n: null, name: 'Not in the build order', ids: extra });
    const counts = { done: 0, working: 0, launched: 0, ready: 0, owner: 0, blocked: 0, retired: 0 };
    for (const t of Object.values(tasks)) counts[t.status]++;
    out.push({ key: p.plan.key, name: p.plan.name, branch: p.plan.branch, file: p.plan.file, stages, tasks, counts,
      total: Object.keys(tasks).length - counts.retired });
  }

  return { updated: Date.now(), repo: REPO, plans: out, lanes, prs, launches: launches.map(launchView) };
}

// Collect in a loop, so a page's request is answered at once from the last pass.
let cached = null;
let lastError = null;
async function loop() {
  const started = Date.now();
  try { cached = { ...(await collect()), took: Date.now() - started }; lastError = null; }
  catch (err) { lastError = String(err?.stack ?? err); console.error(lastError); }
  setTimeout(loop, Math.max(500, CACHE_MS - (Date.now() - started)));
}
const first = loop();
async function data() {
  if (!cached) await first;
  return cached ? { ...cached, error: lastError } : { error: lastError ?? 'no data yet' };
}

// ---------- launching sessions ----------

// The desktop app opens claude:// links: code/new starts a Code session in a
// folder (the app makes its worktree) with the prompt in its box.
function openInApp(url) {
  // LANES_DRY_RUN=1 prints the link instead, for testing the board.
  if (process.env.LANES_DRY_RUN) { console.log(`[dry run] ${url}`); return Promise.resolve(); }
  return run('rundll32.exe', ['url.dll,FileProtocolHandler', url], { windowsHide: true });
}

async function launch(body) {
  const d = cached;
  if (!d) throw new Error('The board has no data yet');
  const refs = [...new Set((body?.tasks ?? []).map(String))];
  if (!refs.length) throw new Error('Nothing queued');
  const groups = new Map();
  for (const ref of refs) {
    const [key, id] = ref.split(':');
    const plan = d.plans.find((p) => p.key === key);
    const t = plan?.tasks[id];
    if (!t) throw new Error(`Unknown task ${ref}`);
    if (!['ready', 'blocked', 'owner'].includes(t.status)) throw new Error(`${ref} has already started (${t.status})`);
    if (!groups.has(key)) groups.set(key, { plan, ids: [] });
    groups.get(key).ids.push(id);
  }
  const done = [];
  for (const [key, { plan, ids }] of groups) {
    // Plan order, so the session works them in the order the plan builds them.
    const order = plan.stages.flatMap((s) => s.ids);
    ids.sort((a, b) => order.indexOf(a) - order.indexOf(b));
    const branch = `lane/${key}-${ids.join('-')}`.slice(0, 120);
    const goal = goalFor({ plan: PLAN_BY_KEY[key], ids, tasks: plan.tasks, branch, repo: REPO });
    const url = `claude://code/new?folder=${encodeURIComponent(REPO)}&q=${encodeURIComponent(`/goal ${goal}`)}`;
    await openInApp(url);
    const record = { id: `${Date.now().toString(36)}-${key}`, time: Date.now(), plan: key, tasks: ids.map((id) => `${key}:${id}`), branch, goal };
    launches.push(record);
    done.push(record);
  }
  launches = launches.filter((l) => Date.now() - l.time < 14 * 24 * 60 * 60 * 1000);
  await writeFile(LAUNCHES, JSON.stringify(launches, null, 2));
  // Mark them at once rather than on the next pass.
  try { cached = { ...(await collect()), took: 0 }; } catch { /* the loop will */ }
  return done;
}

// Ending a lane: the stop list that ~/.claude/hooks/lanes-stop/hook.mjs reads
// before every tool call and when a turn ends. A matching session (by its
// session id, or by working inside the lane's worktree) stops at its next step.
const STOPS = process.env.LANES_STOP_FILE ?? path.join(os.homedir(), '.claude', 'lanes-stop.json');
async function readStops() {
  try { return JSON.parse(await readFile(STOPS, 'utf8')).entries ?? []; } catch { return []; }
}
async function endLaunch(body) {
  const l = launches.find((x) => x.id === body?.launch);
  if (!l) throw new Error('Unknown launch');
  if (l.endedAt) throw new Error('That lane was already ended');
  const trees = await worktrees();
  const tree = trees.find((t) => t.branch === l.branch);
  const sessions = await appSessions();
  const ids = new Set();
  if (l.session?.cli) ids.add(l.session.cli);
  if (tree) for (const s of sessions) if (s.dir === path.normalize(tree.path).toLowerCase() && s.cli) ids.add(s.cli);
  const [k] = l.plan ? [l.plan] : l.tasks[0].split(':');
  const label = `${{ gr: 'GR', aa: 'AA', st: 'ST' }[k] ?? k} ${l.tasks.map((t) => t.split(':')[1]).join(', ')}`;
  const entries = (await readStops()).filter((e) => Date.now() - e.requestedAt < 14 * 24 * 60 * 60 * 1000);
  entries.push({ id: l.id, label, branch: l.branch, worktree: tree?.path ?? null, sessions: [...ids], requestedAt: Date.now(), firedAt: null });
  await writeFile(STOPS, JSON.stringify({ entries }, null, 2));
  l.endedAt = Date.now();
  await writeFile(LAUNCHES, JSON.stringify(launches, null, 2));
  try { cached = { ...(await collect()), took: 0 }; } catch { /* the loop will */ }
  return { label, worktree: tree?.path ?? null, sessions: ids.size };
}

// ---------- the second brain ----------
// The board's "Second brain" button opens /brain/: the viewer and vault from
// tools/second-brain (docs/specs/second-brain.md), imported from this checkout.
// The notes are built from git, never a working tree: the newest rebuild-branch
// tip that has the vault (brain/Home.md), so plan ticks show once they're pushed.
const BRAIN_REFS = ['origin/feature/godot-rebuild', 'feature/godot-rebuild'];
let brain = null; // { handle, gitSource, set }

async function newestRef(refs, needs) {
  let best = null;
  for (const ref of refs) {
    const line = (await tryGit(REPO, 'log', '-1', '--format=%H %ct', ref, '--'))?.trim();
    if (!line) continue;
    const [commit, t] = line.split(' ');
    if (needs && (await tryGit(REPO, 'cat-file', '-e', `${commit}:${needs}`)) === null) continue;
    if (!best || Number(t) > best.t) best = { ref, commit, t: Number(t) };
  }
  return best;
}

async function brainTool() {
  if (brain) return brain;
  const dir = path.join(HERE, '..', 'second-brain');
  const { brainHandler } = await import(pathToFileURL(path.join(dir, 'serve.mjs')).href);
  const { gitSource } = await import(pathToFileURL(path.join(dir, 'sources.mjs')).href);
  let current = null; // { key, source, label }, set before each notes.json
  brain = { gitSource, handle: brainHandler({ getSource: () => current, viewerDir: dir }), set: (c) => { current = c; } };
  return brain;
}

async function serveBrain(req, res, sub) {
  const ref = await newestRef(BRAIN_REFS, 'brain/Home.md');
  let tool = null;
  try { tool = ref && await brainTool(); } catch { /* this checkout has no tools/second-brain */ }
  if (!tool) { res.writeHead(404, { 'content-type': 'text/plain' }); res.end('No second brain here yet (tools/second-brain).'); return; }
  if (sub.split('?')[0] === 'notes.json') tool.set({ key: ref.commit.slice(0, 7), source: tool.gitSource(REPO, ref.commit), label: ref.ref });
  await tool.handle(req, res, sub);
}

// Only this page may launch: the request must come from the board's own origin.
function sameOrigin(req) {
  const ok = [`http://localhost:${PORT}`, `http://127.0.0.1:${PORT}`];
  return ok.includes(req.headers.origin) && ok.some((o) => o.endsWith(`//${req.headers.host}`))
    && (req.headers['content-type'] ?? '').startsWith('application/json');
}
async function readJson(req) {
  let s = '';
  for await (const chunk of req) { s += chunk; if (s.length > 64 * 1024) throw new Error('Too large'); }
  return JSON.parse(s || '{}');
}

createServer(async (req, res) => {
  try {
    if (req.method === 'POST') {
      if (!sameOrigin(req)) { res.writeHead(403); res.end('{"error":"Refused: not from the board"}'); return; }
      const body = await readJson(req);
      let result;
      if (req.url === '/launch') result = { launched: await launch(body) };
      else if (req.url === '/end') result = { ended: await endLaunch(body) };
      else if (req.url === '/open') {
        if (!/^local_[0-9a-f-]{36}$/.test(body.session ?? '')) throw new Error('Bad session id');
        await openInApp(`claude://code/needs-input?session=${body.session}`);
        result = { ok: true };
      } else { res.writeHead(404); res.end('{}'); return; }
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify(result));
      return;
    }
    if (req.url === '/brain') { res.writeHead(302, { location: '/brain/' }); res.end(); return; }
    if (req.url.startsWith('/brain/')) { await serveBrain(req, res, req.url.slice('/brain/'.length)); return; }
    if (req.url.startsWith('/data')) {
      const body = JSON.stringify(await data());
      res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' });
      res.end(body);
      return;
    }
    const html = await readFile(path.join(HERE, 'index.html'));
    res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' });
    res.end(html);
  } catch (err) {
    console.error(err);
    res.writeHead(req.method === 'POST' ? 400 : 500, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: String(err?.message ?? err) }));
  }
}).listen(PORT, '127.0.0.1', () => {
  console.log(`All-lanes board on http://localhost:${PORT} (repo ${REPO})`);
});
