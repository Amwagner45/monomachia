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
