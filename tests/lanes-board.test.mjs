// Tests for tools/lanes-board: how the board reads the plans (plans.mjs), the
// goal a launched session starts with, and the stop hook that ends a lane's work.

import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it } from 'vitest';
import {
  GOAL_LIMIT, PLAN_BY_KEY, expandIds, goalFor, mergeCopies, parseFlat, parseNested, parseSteps,
} from '../tools/lanes-board/plans.mjs';

const GR = PLAN_BY_KEY.gr;
const AA = PLAN_BY_KEY.aa;
const ST = PLAN_BY_KEY.st;

const REBUILD = `# Plan

## Build order

1. **Resume:** 13.1, 25.1–25.2.
2. **Effects** (begun early: on the owner's word): 18.1, 18.2.

## Tasks

- [ ] **18. Effects.**
  - [x] **13.1 Merge the fighters.** Text.
    - Blocked by: none · Stories: 1
  - [-] ~~**25.1 Size guard.**~~
    - Retired on Oct 3.
  - [ ] **25.2 Export preset.** Text.
    - Blocked by: 13.1, 25.1 (when it lands) · Stories: 2
  - [ ] **18.1 The effects layer.** Text.
    - Blocked by: \`docs/plans/authored-animation.md\` task 36, 25.2 · Stories: 3
  - [ ] **18.2 Trail rules;** Text.
    - Blocked by: 18.1
`;

describe('expandIds', () => {
  it('reads single ids, ranges and lettered majors', () => {
    expect(expandIds('13.1, 8.4–8.6, 14b.1-14b.2')).toEqual(['13.1', '8.4', '8.5', '8.6', '14b.1', '14b.2']);
  });
});

describe('parseNested', () => {
  const { tasks, stages } = parseNested(REBUILD, GR);

  it('reads ticks, open tasks and retired ones, but not the parent heading', () => {
    expect([...tasks.keys()]).toEqual(['13.1', '25.1', '25.2', '18.1', '18.2']);
    expect(tasks.get('13.1').mark).toBe('x');
    expect(tasks.get('25.1').mark).toBe('-');
    expect(tasks.get('25.2').mark).toBe(' ');
    expect(tasks.get('18.2').title).toBe('Trail rules');
  });

  it('reads blockers, dropping notes in brackets and naming other plans', () => {
    expect(tasks.get('13.1').blockers).toEqual([]);
    expect(tasks.get('25.2').blockers).toEqual(['gr:13.1', 'gr:25.1']);
    expect(tasks.get('18.1').blockers).toEqual(['aa:36', 'gr:25.2']);
  });

  it('reads the build order, with the plan\'s short stage names', () => {
    expect(stages).toEqual([
      { n: 1, name: 'Resume and safety nets', ids: ['13.1', '25.1', '25.2'] },
      { n: 2, name: 'The look, real fighters', ids: ['18.1', '18.2'] },
    ]);
  });
});

describe('parseFlat', () => {
  const PLAN = `# Plan

## Build order

1. **The Katana** (after the catalogue's OK): 9, 14.
2. **The Greatsword:** 18.

## Tasks

- [x] **9. Right Cut.** Text.
  - Blocked by: 5 (and the owner's OK), 7 · Stories: 1
- [ ] **14. The Katana's review.**
  - **Owner:** OKs the Katana.
  - Blocked by: 9
- [ ] **18. The Greatsword's string.**
  - Blocked by: 14 (and the owner's OK), 15
`;
  const { tasks, stages } = parseFlat(PLAN, AA);

  it('reads tasks, blockers and the owner gates', () => {
    expect(tasks.get('9').mark).toBe('x');
    expect(tasks.get('9').blockers).toEqual(['aa:5', 'aa:7']);
    expect(tasks.get('18').blockers).toEqual(['aa:14', 'aa:15']);
    expect(tasks.get('18').gatedBy).toEqual(['aa:14']);
    expect(tasks.get('14').gate).toBe(true);
    expect(tasks.get('9').gate).toBe(false);
  });

  it('reads the build order past a note in brackets', () => {
    expect(stages.map((s) => s.ids)).toEqual([['9', '14'], ['18']]);
  });
});

describe('parseSteps', () => {
  const PLAN = `# Plan

### Task 1: Move it
- [x] **Step 1: Copy**
- [x] **Step 2: Test**

### Task 2: Read \`transcripts\`
- [x] **Step 1: Test**
\`\`\`js
- [ ] **Step 9: quoted in test code, not a step**
\`\`\`
- [ ] **Step 2: Write**

## After
- [ ] **Step 1: not part of any task**
`;
  const { tasks } = parseSteps(PLAN, ST);

  it('marks a task done only when every step is, skipping code fences', () => {
    expect(tasks.get('1')).toMatchObject({ mark: 'x', steps: 2, ticked: 2 });
    expect(tasks.get('2')).toMatchObject({ mark: ' ', steps: 2, ticked: 1, title: 'Read transcripts' });
  });

  it('makes each task wait on the one before', () => {
    expect(tasks.get('1').blockers).toEqual([]);
    expect(tasks.get('2').blockers).toEqual(['st:1']);
  });
});

describe('mergeCopies', () => {
  // The main branch's copy is newest (it ticked 25.2); the animation branch's is
  // older but re-pointed 18.2's blockers. Both changes must survive.
  const original = parseNested(REBUILD, GR);
  const repointed = parseNested(REBUILD.replace('    - Blocked by: 18.1\n', '    - Blocked by: `docs/plans/authored-animation.md` task 25\n'), GR);
  const ticked = parseNested(REBUILD.replace('- [ ] **25.2', '- [x] **25.2'), GR);
  const merged = mergeCopies([{ time: 1, p: original }, { time: 2, p: repointed }, { time: 3, p: ticked }]);

  it('takes each task from the newest copy that changed it', () => {
    expect(merged.tasks.get('18.2').blockers).toEqual(['aa:25']);
    expect(merged.tasks.get('18.1').blockers).toEqual(['aa:36', 'gr:25.2']);
  });

  it('counts a task done or retired when any copy says so', () => {
    expect([...merged.done].sort()).toEqual(['13.1', '25.2']);
    expect([...merged.retired]).toEqual(['25.1']);
  });

  it('takes the stages from the newest copy', () => {
    expect(merged.stages).toBe(ticked.stages);
  });
});

describe('goalFor', () => {
  const repo = 'C:\\Users\\me\\Monomachia';
  const tasks = { '22.15': { title: 'Pause menu' }, '23.1': { title: 'Training upkeep in the rules' } };
  const goal = goalFor({ plan: GR, ids: ['22.15', '23.1'], tasks, branch: 'lane/gr-22.15-23.1', repo });

  it('names the tasks, the repository and the Godot rebuild branch', () => {
    expect(goal).toContain('22.15 Pause menu; 23.1 Training upkeep in the rules');
    expect(goal).toContain(`in the Monomachia repository at ${repo}`);
    expect(goal).toContain('the Godot rebuild branch, feature/godot-rebuild');
  });

  it('keeps the work on a lane branch with a pull request into the plan branch, never master', () => {
    expect(goal).toContain('pushed on lane/gr-22.15-23.1, with a pull request into feature/godot-rebuild, never master');
    expect(goal).toContain('git switch -c lane/gr-22.15-23.1 origin/feature/godot-rebuild');
  });

  it('brings a session that opened elsewhere into a worktree of the repository', () => {
    expect(goal).toContain('never in a scratch or other folder');
    expect(goal).toContain(`worktree add "${repo}\\.claude\\worktrees\\lane-gr-22-15-23-1" -b lane/gr-22.15-23.1 origin/feature/godot-rebuild`);
  });

  it('asks wayfinder\'s questions before implementing', () => {
    expect(goal).toMatch(/wayfinder for questions only.*AskUserQuestion.*Then implement/);
  });

  it('stays within /goal\'s limit by shortening the titles', () => {
    const many = Object.fromEntries(Array.from({ length: 40 }, (_, i) => [`18.${i}`, { title: 'x'.repeat(200) }]));
    const long = goalFor({ plan: GR, ids: Object.keys(many), tasks: many, branch: 'lane/gr-many', repo });
    expect(long.length).toBeLessThanOrEqual(GOAL_LIMIT);
    expect(long).toContain('18.39');
  });
});

describe('stop hook', () => {
  const HOOK = fileURLToPath(new URL('../tools/lanes-board/stop-hook.mjs', import.meta.url));
  const dir = mkdtempSync(path.join(os.tmpdir(), 'lanes-stop-'));
  const file = path.join(dir, 'lanes-stop.json');
  const worktree = path.join(dir, 'worktrees', 'lane-gr-1');
  const run = (input) => execFileSync(process.execPath, [HOOK], {
    input: JSON.stringify(input), env: { ...process.env, LANES_STOP_FILE: file },
  }).toString();
  const stopList = (entry) => writeFileSync(file, JSON.stringify({ entries: [{
    id: 't', label: 'GR 1.1', worktree, sessions: ['listed'], requestedAt: Date.now(), firedAt: null, ...entry,
  }] }));

  afterEach(() => rmSync(file, { force: true }));

  it('does nothing without a stop list, or for a session it does not name', () => {
    expect(run({ session_id: 'listed', cwd: worktree, hook_event_name: 'PreToolUse' })).toBe('');
    stopList();
    expect(run({ session_id: 'other', cwd: dir, hook_event_name: 'PreToolUse' })).toBe('');
    expect(run({ session_id: 'other', cwd: `${worktree}-2`, hook_event_name: 'PreToolUse' })).toBe('');
  });

  it('stops a listed session before its next tool, wherever it runs', () => {
    stopList();
    const out = JSON.parse(run({ session_id: 'listed', cwd: os.tmpdir(), hook_event_name: 'PreToolUse' }));
    expect(out.continue).toBe(false);
    expect(out.hookSpecificOutput.permissionDecision).toBe('deny');
    expect(out.stopReason).toContain('GR 1.1');
    expect(JSON.parse(readFileSync(file, 'utf8')).entries[0].firedBy).toBe('listed');
  });

  it('stops any session working inside the lane\'s worktree when its turn ends', () => {
    stopList();
    const out = JSON.parse(run({ session_id: 'other', cwd: path.join(worktree, 'game'), hook_event_name: 'Stop' }));
    expect(out.continue).toBe(false);
    expect(out.hookSpecificOutput).toBeUndefined();
  });

  it('lets the session go on two minutes after it first stopped it', () => {
    stopList({ firedAt: Date.now() - 3 * 60 * 1000 });
    expect(run({ session_id: 'listed', cwd: worktree, hook_event_name: 'PreToolUse' })).toBe('');
  });

  it('never blocks on a broken stop list', () => {
    writeFileSync(file, '{not json');
    expect(run({ session_id: 'listed', cwd: worktree, hook_event_name: 'PreToolUse' })).toBe('');
  });
});
