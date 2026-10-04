// Tests for tools/second-brain/vault.mjs, the builder of the second brain
// (docs/specs/second-brain.md): its parsers, and the vault it builds.

import { describe, expect, it } from 'vitest';
import {
  buildVault, linksIn, parseGlossary, parsePlan, parseScriptSummary, resolveLinks, safeName, splitSections, taskIdsInSubject,
} from '../tools/second-brain/vault.mjs';

/** A source over in-memory files and commit subjects. */
function memorySource(files, subjects = []) {
  return { list: () => Object.keys(files), read: (p) => files[p], subjects: () => subjects };
}

const GLOSSARY = `# Monomachia

Intro.

## Attacking

**Light attack** / **Heavy attack**:
The two attack buttons' moves.

**String**:
A sequence of attacks.
_Avoid_: Combo, chain

## Defending

**Parry**:
Tapping block just before an attack lands,
so the weapons bounce.
`;

const PLAN = `# Plan: test

## Build order

1. **Foundations:** 1.1–1.3, 2.1.
2. **Later** (after the owner's OK): 2.2, then 2.3.

## Tasks

### Phase A: start

- [x] **1. Group one.** Lead text.
  - [x] **1.1 First thing.** Does a thing.
    - Check: it works.
    - Blocked by: none (built after 9.9 in the build order) · Stories: 4
  - [x] **1.2 Second thing.**
    - Blocked by: 1.1 · Stories: 5
  - [ ] **1.3 Third thing.**
    - Blocked by: 1.1, 1.2 (and the owner's OK)

### Phase B: more

- [ ] **2. Group two.**
  - [ ] **2.1 A.**
    - Blocked by: 1.1–1.3
  - [ ] **2.2 B.**
  - [ ] **2.3 C.**

## Out of scope

- [ ] **9.9 Not a task here.**
`;

describe('safeName', () => {
  it('keeps names Obsidian accepts as files and link targets', () => {
    expect(safeName('Spec: Monomachia rebuilt in Godot')).toBe('Spec - Monomachia rebuilt in Godot');
    expect(safeName('Game Design Document: *Monomachia*')).toBe('Game Design Document - Monomachia');
    expect(safeName('a/b [c] #d | e?')).toBe('a-b -c- -d - e');
    expect(safeName('Ends with a dot.')).toBe('Ends with a dot');
  });
});

describe('taskIdsInSubject', () => {
  it('reads task ids, lists and ranges from commit subjects', () => {
    expect(taskIdsInSubject('Step the feet in time with a lunge (task 14.13)')).toEqual(['14.13']);
    expect(taskIdsInSubject('Build screens (godot-rebuild 22.6, 22.8-22.10, first step)')).toEqual(['22.6', '22.8', '22.9', '22.10']);
    expect(taskIdsInSubject('Open Settings (godot-rebuild 22.9, 22.10)')).toEqual(['22.9', '22.10']);
    expect(taskIdsInSubject('Port the swing editor (task 14b.2)')).toEqual(['14b.2']);
  });

  it('ignores other parentheses and untagged subjects', () => {
    expect(taskIdsInSubject('Merge pull request #16 from Arod231/godot/menus-22.6-22.10')).toEqual([]);
    expect(taskIdsInSubject('Add UAL2 clips (v1.2 files)')).toEqual([]);
  });
});

describe('parseGlossary', () => {
  it('gives an entry per term with its section, definition and avoid words', () => {
    const g = parseGlossary(GLOSSARY);
    expect(g.map((e) => e.term)).toEqual(['Light attack', 'Heavy attack', 'String', 'Parry']);
    expect(g[0]).toMatchObject({ section: 'Attacking', definition: "The two attack buttons' moves.", also: ['Heavy attack'] });
    expect(g[2]).toMatchObject({ avoid: 'Combo, chain', also: [] });
    expect(g[3]).toMatchObject({ section: 'Defending', definition: 'Tapping block just before an attack lands, so the weapons bounce.' });
  });
});

describe('splitSections', () => {
  it('splits at ## below the title and keeps the intro', () => {
    const s = splitSections('# Title *here*\n\nIntro line.\n\n## One\n\nA\n\n### Sub\n\nB\n\n## Two\n\nC\n');
    expect(s.title).toBe('Title here');
    expect(s.intro).toBe('Intro line.');
    expect(s.sections.map((x) => x.heading)).toEqual(['One', 'Two']);
    expect(s.sections[0].body).toBe('A\n\n### Sub\n\nB');
  });

  it('splits at ### in a doc with no ## headings, and ignores headings in code fences', () => {
    const s = splitSections('# T\n\n### A\n\n```\n## not a heading\n```\n\n### B\n\nx\n');
    expect(s.sections.map((x) => x.heading)).toEqual(['A', 'B']);
  });
});

describe('parseScriptSummary', () => {
  it('reads the class, base and the first sentence of the doc comment', () => {
    const s = parseScriptSummary('class_name PadStyle\nextends RefCounted\n## Which button names a controller gets. More text\n## here.\n\nconst A = 1\n');
    expect(s).toMatchObject({ className: 'PadStyle', base: 'RefCounted', summary: 'Which button names a controller gets.' });
  });

  it('skips a leading "Port of" line and notes the port', () => {
    const s = parseScriptSummary('class_name Fighter\nextends RefCounted\n## Port of src/sim/fighter.ts.\n##\n## A fighter: position, health. Pure.\n');
    expect(s.summary).toBe('A fighter: position, health. (port of src/sim/fighter.ts)');
  });

  it('falls back to plain # comments, and to nothing', () => {
    expect(parseScriptSummary('extends Node\n# Plays swings on a fighter.\nvar f\n').summary).toBe('Plays swings on a fighter.');
    expect(parseScriptSummary('extends Node\nvar f\n# late comment\n').summary).toBe('');
  });
});

describe('parsePlan', () => {
  const plan = parsePlan(PLAN);

  it('reads every task under Tasks with its done mark, parent and phase', () => {
    expect(plan.tasks.map((t) => t.id)).toEqual(['1', '1.1', '1.2', '1.3', '2', '2.1', '2.2', '2.3']);
    expect(plan.tasks[0]).toMatchObject({ title: 'Group one', lead: 'Lead text.', done: true, parent: null, phase: 'Phase A: start' });
    expect(plan.tasks[1]).toMatchObject({ title: 'First thing', done: true, parent: '1' });
    expect(plan.tasks[1].text).toContain('- Check: it works.');
    expect(plan.tasks[3]).toMatchObject({ done: false, phase: 'Phase A: start' });
    expect(plan.tasks[5]).toMatchObject({ parent: '2', phase: 'Phase B: more' });
  });

  it('reads blockers, leaving out notes in parentheses, and the owner gate', () => {
    expect(plan.tasks[1].blockedBy).toEqual([]);
    expect(plan.tasks[2].blockedBy).toEqual(['1.1']);
    expect(plan.tasks[3]).toMatchObject({ blockedBy: ['1.1', '1.2'], waitsOnOwner: true });
    expect(plan.tasks[5].blockedBy).toEqual(['1.1', '1.2', '1.3']);
  });

  it('reads the build order with en-dash ranges expanded in plan order', () => {
    expect(plan.stages).toEqual([
      { n: 1, name: 'Foundations', ids: ['1.1', '1.2', '1.3', '2.1'] },
      { n: 2, name: 'Later', ids: ['2.2', '2.3'] },
    ]);
  });
});

describe('linksIn and resolveLinks', () => {
  it('finds wikilinks with labels and headings, not embeds or code', () => {
    expect(linksIn('See [[A]], [[B|label]], [[C#Part]], [[dir/D]] and ![[E]] or `[[F]]`.')).toEqual(['A', 'B', 'C', 'dir/D']);
  });

  it('resolves by name, ignoring case and folders, and reports misses', () => {
    const notes = [{ name: 'Alpha', text: '[[beta]] [[x/Beta]] [[Gamma]]' }, { name: 'Beta', text: '' }];
    expect(resolveLinks(notes).map((l) => l.to)).toEqual(['Beta', 'Beta', null]);
  });
});

describe('buildVault', () => {
  const source = memorySource({
    'GLOSSARY.md': GLOSSARY,
    'docs/plans/godot-rebuild.md': PLAN,
    'docs/design.md': '# Game Design Document: *Monomachia*\n\nIntro, see [the plan](plans/godot-rebuild.md).\n\n## Combat\n\nA **parry** or a string.\n\n## Look\n\nArt.\n',
    'brain/Home.md': '# Home\n\n[[Glossary]] · [[Design doc]] · [[Code map]] · [[Rebuild plan]]\n',
    'brain/.obsidian/app.json': '{}',
    'brain/generated/stale.md': 'old',
    'game/sim/fighter.gd': 'class_name Fighter\nextends RefCounted\n## A fighter: position and posture (task 2.2).\n',
    'game/sim/moves/katana.gd': 'extends RefCounted\n## The Katana\'s moves.\n',
    'game/addons/gut/gut.gd': '## Not ours.\n',
    'src/old.ts': 'x',
  }, [
    { subject: 'Add the fighter (task 1.2)', files: ['game/sim/fighter.gd', 'docs/plans/godot-rebuild.md'] },
    { subject: 'Tidy (godot-rebuild 2.1, 77.1)', files: ['game/sim/moves/katana.gd'] },
    { subject: 'Untagged change', files: ['game/sim/fighter.gd'] },
  ]);
  const { notes } = buildVault(source);
  const note = (name) => notes.find((n) => n.name === name);

  it('keeps hand-written notes and leaves out stale generated files and settings', () => {
    expect(note('Home').path).toBe('brain/Home.md');
    expect(notes.some((n) => n.path === 'brain/generated/stale.md' || n.path.includes('.obsidian'))).toBe(false);
  });

  it('gives every note a unique name and every link a target', () => {
    const names = notes.map((n) => n.name.toLowerCase());
    expect(new Set(names).size).toBe(names.length);
    expect(resolveLinks(notes).filter((l) => !l.to)).toEqual([]);
  });

  it('writes a note per glossary term, linking the terms it names', () => {
    expect(note('Heavy attack').text).toContain('**See also:** [[Light attack]]');
    expect(note('String').text).toContain('**Avoid:** Combo, chain');
    expect(note('Glossary').text).toContain('- [[Parry]]: Tapping block just before an attack lands, so the weapons bounce.');
  });

  it('writes doc hubs and section notes with doc links rewritten and terms mentioned', () => {
    expect(note('Design doc').text).toContain('Intro, see [[Rebuild plan|the plan]].');
    expect(note('Design doc').text).toContain('- [[Design doc - Combat|Combat]]');
    const combat = note('Design doc - Combat');
    expect(combat.path).toBe('brain/generated/docs/Design doc/Design doc - Combat.md');
    expect(combat.text).toContain('**Next:** [[Design doc - Look]]');
    expect(combat.text).toContain('**Mentions:** [[String]] · [[Parry]]');
  });

  it('writes stage and task notes with blockers, what they block, and their code', () => {
    expect(note('Stage 1 - Foundations').text).toContain('2 of 4 tasks done');
    const t12 = note('Task 1.2');
    expect(t12.path).toBe('brain/generated/plan/Rebuild plan/tasks/Task 1.2.md');
    expect(t12.text).toContain('**Status:** done ✓ · **Stage:** [[Stage 1 - Foundations]] · **Part of:** [[Task 1]]');
    expect(t12.text).toContain('**Blocked by:** [[Task 1.1]]');
    expect(t12.text).toContain('**Blocks:** [[Task 1.3]] · [[Task 2.1]]');
    expect(t12.text).toContain('**Code:** [[game.sim]]');
    expect(note('Task 1.3').text).toContain("**Blocked by:** [[Task 1.1]] · [[Task 1.2]] · the owner's OK");
    expect(note('Task 1').text).toContain('**Subtasks:** ✓ [[Task 1.1]] · ✓ [[Task 1.2]] · ○ [[Task 1.3]]');
    expect(note('Rebuild plan').text).toContain('- ✓ [[Task 1]]: Group one');
    expect(note('Rebuild plan').text).not.toContain('[[Rebuild plan - Tasks');
  });

  it('writes a code note per folder with script summaries and the tasks that touched it', () => {
    const sim = note('game.sim');
    expect(sim.text).toContain('- `fighter.gd` (Fighter): A fighter: position and posture (task 2.2).');
    expect(sim.text).toContain('**Tasks:** [[Task 1.2]] · [[Task 2.2]]');
    expect(sim.text).toContain('**In:** [[game]] · **Folders:** [[game.sim.moves]]');
    expect(note('game.sim.moves').text).toContain('**Tasks:** [[Task 2.1]]');
    expect(notes.some((n) => n.name.includes('addons'))).toBe(false);
    expect(note('Code map').text).toContain('  - [[game.sim]] (2 scripts)');
  });

  it('is deterministic', () => {
    expect(buildVault(source)).toEqual({ notes });
  });
});

describe('safeName length', () => {
  it('cuts long names at a parenthesis, then at a word, and keeps raw names raw', () => {
    expect(safeName('Plan task 8 - Fluid combat rules and more words (arena radius 15 m and the values tied to it, and so on)')).toBe('Plan task 8 - Fluid combat rules and more words');
    expect(safeName('word '.repeat(30)).length).toBeLessThanOrEqual(80);
    expect(safeName('game.arenas.moonlit_shrine', true)).toBe('game.arenas.moonlit_shrine');
  });
});

describe('parseScriptSummary ports', () => {
  it('keeps a "Port of" sentence that says what the script is', () => {
    expect(parseScriptSummary('## Port of the AttackState interface in src/sim/fighter.ts: the attack in progress.\n').summary)
      .toBe('Port of the AttackState interface in src/sim/fighter.ts: the attack in progress.');
    expect(parseScriptSummary('## Port of src/sim/match.ts. Round and match flow.\n').summary).toBe('Round and match flow. (port of src/sim/match.ts)');
  });
});

describe('sources', async () => {
  const { fsSource, gitSource } = await import('../tools/second-brain/sources.mjs');
  const ROOT = new URL('..', import.meta.url).pathname.replace(/^\/(\w:)/, '$1');
  // These spawn git and read the whole repo. Alone they take 1-3 s, but in a full
  // run, under load from the other test files, they have gone past Vitest's 5 s default.
  const SLOW = 30_000;

  it('reads the same tracked doc from the working tree and from HEAD', () => {
    const fs = fsSource(ROOT);
    const head = gitSource(ROOT, 'HEAD');
    expect(fs.list()).toContain('GLOSSARY.md');
    expect(head.list()).toContain('GLOSSARY.md');
    expect(head.read('GLOSSARY.md').replace(/\r\n/g, '\n')).toBe(fs.read('GLOSSARY.md').replace(/\r\n/g, '\n'));
    expect(head.read('README.md').length).toBeGreaterThan(0);
    expect(JSON.parse(head.read('package.json')).name).toBe(JSON.parse(fs.read('package.json')).name);
    expect(head.subjects()[0]).toEqual({ subject: expect.any(String), files: expect.any(Array) });
  }, SLOW);

  it('builds the real vault with no broken links and no duplicate names', () => {
    const { notes } = buildVault(fsSource(ROOT));
    const names = notes.map((n) => n.name.toLowerCase());
    expect(names.filter((n, i) => names.indexOf(n) !== i)).toEqual([]);
    expect(resolveLinks(notes).filter((l) => !l.to).map((l) => `${l.from} -> ${l.target}`)).toEqual([]);
    expect(notes.find((n) => n.name === 'Rebuild plan')).toBeTruthy();
  }, SLOW);
});

describe('brainHandler', async () => {
  const { brainHandler } = await import('../tools/second-brain/serve.mjs');
  const call = async (handle, path, method = 'GET') => {
    let status = 0, headers = {}, body = '';
    const res = { writeHead: (s, h = {}) => { status = s; headers = h; }, end: (b = '') => { body = String(b); } };
    await handle({ method }, res, path);
    return { status, headers, body };
  };
  const source = memorySource({ 'brain/Home.md': '# Home\n\n[[Glossary]]\n', 'GLOSSARY.md': GLOSSARY });

  it('serves the viewer page, its script and the notes', async () => {
    let asked = 0;
    const handle = brainHandler({ getSource: () => { asked++; return { key: 'abc', source }; }, label: 'test' });
    const page = await call(handle, '/');
    expect(page.status).toBe(200);
    expect(page.body).toContain('<title>Second brain</title>');
    expect((await call(handle, 'vendor/marked.umd.js')).body).toContain('marked');
    const notes = await call(handle, 'notes.json?x=1');
    const data = JSON.parse(notes.body);
    expect(data).toMatchObject({ label: 'test', key: 'abc' });
    expect(data.notes.map((n) => n.name)).toContain('Parry');
    await call(handle, 'notes.json');
    expect(asked).toBe(2);
  });

  it('refuses unknown paths and other methods', async () => {
    const handle = brainHandler({ getSource: () => ({ key: null, source }) });
    expect((await call(handle, '../package.json')).status).toBe(404);
    expect((await call(handle, 'notes.json', 'POST')).status).toBe(405);
  });
});
