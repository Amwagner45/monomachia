# Golden replays

Frame-by-frame recordings of the web demo's TypeScript rules (`src/sim`), used to check that the GDScript port of the rules behaves exactly the same (plan task 4 in `docs/plans/godot-rebuild.md`).

- One compact JSON file per scenario, and `index.json` listing the scenario names.
- 29 scripted duels (kind `world`), sampled every frame. Together they cover every mechanic the web tests cover.
- 6 computer-vs-computer matches (kind `match`), sampled every 40 steps, with every event.
- Each file holds the inputs, any direct field writes (`setup`), fighter and world samples, and every event.
- The format is documented at the top of `scripts/golden/record.ts`.

## Regenerating

```
npm run golden:record
```

The recorder is deterministic: every run writes byte-identical files. `tests/golden.test.ts` replays every file on the TypeScript rules and fails if anything differs. To see one scripted scenario's events, run `npx tsx scripts/golden/record.ts --trace <name>`.

**Do not regenerate these files after the Godot rules deliberately change** (phase C of the plan). They record the web demo's rules exactly. They are the reference for the faithful port, not a snapshot of whatever the rules currently do.

## Replaying on the Godot rules

`game/tests/sim/test_golden_replay.gd` (part of `npm test`) replays every file on the GDScript rules, one GUT test per scenario. Each test stops at its first difference and reports the step, the world frame, the field and both sides' events for that step. Names, ints and bools must match exactly; floats must be within 1e-6. Floats need that margin because Godot's JSON reader is not correctly rounded: it reads some recorded numbers a unit in the last place off. The rules themselves are bit-identical (`game/sim/js_math.gd` gives V8's `Math.hypot`, `sin`, `cos` and `atan2`, and `test_port_regressions.gd` checks whole runs bit for bit). Over a full match the drift stays around 1e-13.

A new scenario needs its own `test_<name>` function in that file; a guard test fails until it has one. To run one scenario:

```
node scripts/godot.mjs test -gselect=test_golden_replay -gunit_test_name=<name>
```
