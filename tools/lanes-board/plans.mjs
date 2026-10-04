// The lanes board's view of the plans: which plans it follows, how it reads
// their tasks, blockers and build order, how it merges the copies on different
// branches, and the /goal a launched session starts with. Pure functions, no
// git or disk, so tests/lanes-board.test.mjs can run them on fixtures.
import path from 'node:path';

export const PLANS = [
  { key: 'gr', name: 'Godot rebuild', file: 'docs/plans/godot-rebuild.md', kind: 'nested', branch: 'feature/godot-rebuild',
    names: { 1: 'Resume and safety nets', 2: 'The look, real fighters', 3: 'The shrine', 4: 'Fluid rules', 5: 'Sound and music',
      6: 'The new strings', 7: 'Swing foundations', 8: 'Fighter animation core', 9: 'Katana swings, anim review',
      10: 'Editor, HUD, effects, menus', 11: "Other weapons' swings", 12: 'Computer and balance', 13: 'Full animation', 14: 'Ship' } },
  { key: 'aa', name: 'Authored animation', file: 'docs/plans/authored-animation.md', kind: 'flat', branch: 'feature/authored-animation' },
  { key: 'st', name: 'Session tracker', file: 'docs/plans/session-tracker.md', kind: 'steps', branch: 'tools/session-tracker' },
];
export const PLAN_BY_KEY = Object.fromEntries(PLANS.map((p) => [p.key, p]));

// "8.4–8.9", "14b.1–14b.6", "13.1" -> ids.
export function expandIds(text) {
  const out = [];
  const re = /(\d+b?)\.(\d+)(?:\s*[–-]\s*(?:(\d+b?)\.)?(\d+))?/g;
  for (const [, major, from, , to] of text.matchAll(re)) {
    if (to === undefined) { out.push(`${major}.${from}`); continue; }
    for (let i = Number(from); i <= Number(to); i++) out.push(`${major}.${i}`);
  }
  return out;
}
const section = (text, heading) => text.split(new RegExp(`^## ${heading}`, 'm'))[1]?.split(/^## /m)[0] ?? '';

// The godot-rebuild plan: nested "- [x] **7.1 Title.**" tasks, "- [-] ~~**7.16 …**~~"
// when retired, a "Blocked by:" line that may name another plan's task, and a
// "## Build order" list of stages.
export function parseNested(text, plan) {
  const tasks = new Map();
  let cur = null;
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^\s*- \[([ x-])\] (?:~~)?\*\*(\d+b?\.\d+)\s+(.*?)\*\*/);
    if (m) {
      cur = { id: m[2], title: m[3].replace(/[.;:]\s*$/, ''), mark: m[1], blockers: [], gate: false };
      tasks.set(cur.id, cur);
      continue;
    }
    if (/^\s*- \[[ x-]\] /.test(line) || line.startsWith('#')) { cur = null; continue; }
    const b = cur && !cur.seenBlockers && line.match(/Blocked by:\s*(.*)/);
    if (b) {
      cur.seenBlockers = true;
      const frag = b[1].split(' · ')[0];
      const ext = [...frag.matchAll(/authored-animation\.md`?\s+task\s+(\d+)/g)].map((x) => `aa:${x[1]}`);
      const local = /^\s*none/i.test(frag) ? [] : expandIds(frag.replace(/`[^`]*`\s*task\s*\d+/g, '').replace(/\([^)]*\)/g, ''));
      cur.blockers = [...ext, ...local.map((id) => `${plan.key}:${id}`)];
    }
  }
  const stages = [];
  for (const line of section(text, 'Build order').split(/\r?\n/)) {
    const m = line.match(/^(\d+)\.\s+\*\*(.+?)\*\*(.*)$/);
    if (!m) continue;
    const rest = m[3].replace(/\([^)]*\)/g, '');
    const list = rest.includes(':') ? rest.slice(rest.indexOf(':') + 1) : rest;
    stages.push({ n: Number(m[1]), name: plan.names?.[m[1]] ?? m[2].replace(/:$/, ''), ids: expandIds(list).filter((id) => tasks.has(id)) });
  }
  return { tasks, stages };
}

// The authored-animation plan: top-level "- [x] **9. Title.**" tasks; a blocker
// written "14 (and the owner's OK)" makes 14 a review gate.
export function parseFlat(text, plan) {
  const tasks = new Map();
  const gates = new Set();
  let cur = null;
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^- \[([ x-])\] (?:~~)?\*\*(\d+)\.\s+(.*?)\*\*/);
    if (m) {
      cur = { id: m[2], title: m[3].replace(/[.;:]\s*$/, ''), mark: m[1], blockers: [], gate: false, gatedBy: [] };
      tasks.set(cur.id, cur);
      continue;
    }
    if (/^- \[/.test(line) || line.startsWith('#')) { cur = null; continue; }
    if (!cur) continue;
    if (/\*\*Owner:\*\*/.test(line)) cur.gate = true;
    const b = !cur.seenBlockers && line.match(/Blocked by:\s*(.*)/);
    if (b) {
      cur.seenBlockers = true;
      const frag = b[1].split(' · ')[0];
      for (const g of frag.matchAll(/(\d+)\s*\(and the owner's OK\)/g)) { cur.gatedBy.push(`${plan.key}:${g[1]}`); gates.add(g[1]); }
      cur.blockers = /^\s*none/i.test(frag) ? [] : (frag.replace(/\([^)]*\)/g, '').match(/\d+/g) ?? []).map((id) => `${plan.key}:${id}`);
    }
  }
  for (const id of gates) if (tasks.has(id)) tasks.get(id).gate = true;
  const stages = [];
  for (const line of section(text, 'Build order').split(/\r?\n/)) {
    const m = line.match(/^(\d+)\.\s+\*\*(.+?)\*\*(.*)$/);
    if (!m) continue;
    const rest = m[3].replace(/\([^)]*\)/g, '');
    const list = rest.includes(':') ? rest.slice(rest.indexOf(':') + 1) : rest;
    stages.push({ n: Number(m[1]), name: m[2].replace(/:$/, ''), ids: (list.match(/\d+/g) ?? []).filter((id) => tasks.has(id)) });
  }
  return { tasks, stages };
}

// The session-tracker plan: "### Task N: Title" with "- [x] **Step k" lines;
// a task is done when all its steps are, and each waits on the one before.
// Code fences are skipped (the plan quotes task lines in its test code).
export function parseSteps(text, plan) {
  const tasks = new Map();
  let cur = null;
  let prev = null;
  let fence = false;
  for (const line of text.split(/\r?\n/)) {
    if (/^\s*```/.test(line)) { fence = !fence; continue; }
    if (fence) continue;
    const t = line.match(/^### Task (\d+):\s*(.*)$/);
    if (t) {
      cur = { id: t[1], title: t[2].replace(/`/g, ''), steps: 0, ticked: 0, blockers: prev ? [`${plan.key}:${prev}`] : [], gate: false };
      tasks.set(cur.id, cur);
      prev = cur.id;
      continue;
    }
    if (line.startsWith('## ')) cur = null;
    const s = cur && line.match(/^\s*- \[([ x])\] \*\*Step/);
    if (s) { cur.steps++; if (s[1] === 'x') cur.ticked++; }
  }
  for (const t of tasks.values()) t.mark = t.steps && t.ticked === t.steps ? 'x' : ' ';
  return { tasks, stages: [{ n: 1, name: 'Tasks', ids: [...tasks.keys()] }] };
}

const PARSERS = { nested: parseNested, flat: parseFlat, steps: parseSteps };
export const parsePlan = (plan, text) => PARSERS[plan.kind](text, plan);

/**
 * One plan from its copies on every branch, each { time, p } (p from parsePlan,
 * time when that branch last changed the file). Stages come from the newest
 * copy. Branches change different tasks (one re-points 12.2's blockers while
 * another ticks 22.2), so each task's text comes from the newest copy that
 * changed it from the oldest copy, and from the newest copy otherwise. A task
 * is done or retired when any copy says so.
 */
export function mergeCopies(copies) {
  const newest = copies.reduce((a, b) => (b.time > a.time ? b : a));
  const oldest = copies.reduce((a, b) => (b.time < a.time ? b : a));
  const sig = (t) => JSON.stringify([t.title, t.blockers, t.gatedBy ?? []]);
  const tasks = new Map();
  for (const t of newest.p.tasks.values()) {
    const o = oldest.p.tasks.get(t.id);
    let best = null;
    for (const c of copies) {
      const v = c.p.tasks.get(t.id);
      if (v && o && sig(v) !== sig(o) && (!best || c.time > best.time)) best = { time: c.time, v };
    }
    tasks.set(t.id, best ? { ...t, title: best.v.title, blockers: best.v.blockers, gatedBy: best.v.gatedBy, gate: t.gate || best.v.gate } : t);
  }
  const done = new Set();
  const retired = new Set();
  for (const { p } of copies) {
    for (const t of p.tasks.values()) {
      if (t.mark === 'x') done.add(t.id);
      if (t.mark === '-') retired.add(t.id);
    }
  }
  return { tasks, stages: newest.p.stages, done, retired };
}

export const GOAL_LIMIT = 4000; // /goal refuses a longer condition

/**
 * The /goal a launched session starts with. The desktop app sometimes drops the
 * launch link's folder and opens the session in a scratch folder, so the goal
 * itself brings the session into the repository. Work stays on a lane branch
 * with a pull request into the plan's branch (the owner chose to keep the PRs).
 */
export function goalFor({ plan, ids, tasks, branch, repo }) {
  const list = (n) => ids.map((id) => `${id} ${tasks[id].title.slice(0, n)}`).join('; ');
  const worktree = path.win32.join(repo, '.claude', 'worktrees', branch.replace(/[^A-Za-z0-9-]/g, '-'));
  const target = plan.key === 'gr' ? `the Godot rebuild branch, ${plan.branch}` : `${plan.branch} (which merges into feature/godot-rebuild)`;
  const body = (n) => [
    `Finish implementation of the queued ${plan.name} tasks: ${list(n)} (${plan.file}), in the Monomachia repository at ${repo}, with every change built on and merged into ${target}.`,
    `Done when each queued task is built with its checks passing, ticked in ${plan.file}, committed and pushed on ${branch}, with a pull request into ${plan.branch}, never master.`,
    `Setup, before anything else: work only in a worktree of ${repo}, never in a scratch or other folder. If your working directory is not inside ${repo}, run git -C "${repo}" fetch origin, then git -C "${repo}" worktree add "${worktree}" -b ${branch} origin/${plan.branch} (or check out ${branch} there if it exists), and move this session into it with the change_directory tool (find it with ToolSearch). Otherwise run git fetch origin and git switch -c ${branch} origin/${plan.branch} in this worktree.`,
    `Before any edit, check that git branch --show-current prints ${branch} and that git merge-base --is-ancestor origin/${plan.branch} HEAD succeeds. If missing, copy .godot-path and .assets-src-path from ${repo} and junction its node_modules.`,
    'Before implementing, run wayfinder for questions only: read ~/.claude/skills/wayfinder/SKILL.md (it cannot be called as a tool) and follow its questioning to find every open decision these tasks need, but write no map or ticket files.',
    'Ask each decision with the AskUserQuestion tool as clickable multiple choice, recommended option first, and wait for my answers. Record the answers in the tasks\' blocks in the plan.',
    `Then implement the tasks one at a time in plan order, per CLAUDE.md (tests first; npm test and npm run typecheck before each commit; push after each; a draft PR into ${plan.branch}), ticking each in the plan as it lands. Follow the plan's Notes and the side-lane rules in memory, and stop to ask me at any owner gate.`,
  ].join(' ');
  for (const n of [120, 60, 30, 0]) {
    const text = body(n);
    if (text.length <= GOAL_LIMIT) return text;
  }
  return body(0).slice(0, GOAL_LIMIT);
}
