# Plan: Monomachia rebuilt in Godot

Spec: `docs/specs/godot-rebuild.md` · branch `feature/godot-rebuild` · pull request #2

## Destination

The Godot build plays everything the web demo plays, on the new direction in the spec: weapon-path hits and animation, the two first fighters, the new Katana, Greatsword and Daggers strings, the For Honor camera, the floating Moonlit Shrine, the toon and ink-wash look, sound and placeholder music, all four modes, and remappable controls. CI builds it for Windows, and the web version is deleted.

## Notes

- Work task by task in the order below; a task starts only when everything it's blocked by is ticked. Independent tasks in the same phase may run in parallel.
- Every task ends with `npm test` and `npm run typecheck` passing (once task 1 makes them call Godot), a commit and a push. Visual tasks also end with screenshots reviewed by eye.
- The rules layer (`game/sim`) stays free of nodes, rendering, input devices and sound.
- Use the glossary's terms (Fighter, Weapon, Loadout, String, Follow-up, Posture…) in code names.
- When a task changes tuning or rules, update the spec's numbers and add or update a test in the same commit.

## Decisions so far

- [Destination](../specs/godot-rebuild.md): MVP parity in Godot on the new foundation; the rest of the design update comes later.
- Engine and language: Godot 4.7.2 standard build, typed GDScript.
- Any fighter can wield any weapon; the rebuild ships the Rogue and the Hunter.
- Arenas are walled and floating; the sci-fi themes are dropped.
- No directional guard, no combo breaker; light hitstun drops to 14 frames instead.
- Hits come from weapon paths; the same paths drive the animation.
- The web version is tagged `v0.1-web-mvp` and deleted at the end.
- Tracker: local Markdown in `docs/` (see `docs/agents/issue-tracker.md`).

## Not yet specified

- The full character select (model on the right, loadout on the left, lock-in, gate opening), the match intros and victory poses, with their animations.
- How the other six fighters get bodies and outfits (budget, packs, or commissioned art), and how the Orc and Skeleton Knight differ in size and hurt capsule.
- The other six weapons' movesets in frame data, and the open questions the design review raised about them: which hammer, scythe and staff moves are unblockable, the whip's normal heavy, and what "good blocking" means for Sword & Shield.
- The sourcing and licensing of real music.
- The additional arenas and a stage select.

## Out of scope

- Online play, progression and cosmetics (the design's later phases), and Mac and Linux builds.

## Tasks

### Phase A: foundation and a faithful port

- [ ] **1. Godot project and tooling.**
  - Delivers:
    - a Godot 4.7 project in `game/` (Forward+, 60 physics ticks, 1600×900 window, the autoload and folder layout from the spec);
    - GUT vendored in `game/addons`;
    - `scripts/godot.mjs`, which finds Godot through `GODOT` or known paths;
    - npm scripts `test`, `typecheck`, `soak`, `build`, `dev` and `shots`, which run the old Vitest tests and the Godot tests side by side until the web code is deleted;
    - `.gitignore` and `.gitattributes` updates (the `.godot/` cache, exports, LF line endings);
    - a CI job that installs Godot 4.7.2 and runs the Godot tests.
  - Blocked by: none.
  - Check: a trivial GUT test passes from `npm test` locally and in CI, and `npm run typecheck` catches a deliberately broken script.
- [ ] **2. Port the rules foundations.** Constants, math, the Mulberry32 random generator (bit-exact), the input tracker, events, the move schema with its defaults, and the four weapons' move data, all faithful.
  - Blocked by: 1.
  - Check: the ported input tests (step, sprint latch, slow second push, buffering) pass; the random generator matches the TypeScript output for 1,000 draws; every move loads with the same values as `finalizeMoves` produces.
- [ ] **3. Port the fighter, the world and the match.** The full state machine, the hit evaluation and application, dropped weapons, the Moonsplitter wave, scripted ultimate hits, the round flow, and the test helpers.
  - Blocked by: 2.
  - Check: all 47 demo tests ported to GUT and passing.
- [ ] **4. Golden replays against the TypeScript rules.**
  - Delivers:
    - a Node script that runs the TypeScript rules on scripted scenarios (every test scenario plus six computer-vs-computer matches with fixed seeds) and writes per-frame event and state logs to `game/tests/golden/`;
    - a GUT test that replays them on the Godot rules and compares them.
  - Blocked by: 3 (and 5 for the computer-vs-computer goldens).
  - Check: every golden matches, events exactly and positions within 1e-6.
- [ ] **5. Port the computer opponent, the training dummy and the tools.** The brain with its three difficulties, the training behaviours, and headless `soak` and `counterlab` runners.
  - Blocked by: 3.
  - Check: `npm run soak -- 40` finishes with no errors, and its numbers are within noise of the TypeScript soak run on the same seeds; computer-vs-computer goldens match.

### Phase B: a playable skeleton

- [ ] **6. Playable duel with stand-in fighters.**
  - Delivers:
    - the fixed-step host (accumulator, slow motion, hit-stop freeze, interpolation);
    - capsule fighters with stick weapons posed from the move data;
    - the For Honor camera;
    - keyboard, mouse and controller input for player 1;
    - a flat stand-in arena at the rules' radius;
    - a minimal HUD;
    - Duel against the computer from launch to results.
  - Blocked by: 5.
  - Check: a scripted run plays a full match headless; screenshots of the duel from the gameplay camera.

### Phase C: the rule changes

- [ ] **7. Weapon swings drive hits.**
  - Delivers:
    - the swing shapes library;
    - arc interpolation;
    - a swing on every move (current moves only);
    - blade-sweep versus hurt-capsule hit tests in the rules;
    - reach and arc derived from the swings;
    - a debug view drawing blade sweeps and capsules in the stand-in scene.
  - Blocked by: 6.
  - Check: the new swing-hit tests from the spec pass; the old tests pass or are updated with a reason in the commit; the soak run is clean; debug screenshots show sweeps matching hits.
- [ ] **8. Fluid combat rules.** Arena radius 15 m, with the hard-coded values tied to it; blocking walk 60%; momentum carry; eased lunges; the colossal recovery slide; heavy dodge-cancel; light hitstun 14.
  - Blocked by: 7.
  - Check: the new tests from the spec pass; the soak run is clean.
- [ ] **9. Katana strings.** The four-light string, the Iai stance (walk while sheathed, direction at release, auto-release, dodge cancels it) and the follow-ups.
  - Blocked by: 8.
  - Check: the Katana tests from the spec pass.
- [ ] **10. Greatsword strings.** Momentum lights, Overhead Strike into the unblockable Low Sweep, and the dodge thrusts.
  - Blocked by: 8.
  - Check: the Greatsword tests from the spec pass.
- [ ] **11. Daggers strings.** The alternating string, dodge-cancel from the first recovery frame, Twin Fang into Spinning Backhand, the removed loop, and the Passing Cut.
  - Blocked by: 8.
  - Check: the Daggers tests from the spec pass.
- [ ] **12. Computer opponent and balance pass.** The brain and dummy learn the Iai, the new unblockables and the dodge cancels; tuning follows soak data; the spec's numbers are updated.
  - Blocked by: 9, 10, 11.
  - Check: soak targets from the spec (rounds 35–60 s, 0.3–0.6 disarms per round, each weapon 45–55%); the counterlab shows every counter reachable.

### Phase D: fighters and animation

- [ ] **13. Assets and fighter models.**
  - Delivers:
    - the chosen Quaternius files copied into `game/assets`, with textures scaled down;
    - humanoid bone-map import settings;
    - the head-only body cut at import;
    - Rogue and Hunter scenes with outfits, hair and two palettes each;
    - weapon models with grip and tip markers (Greatsword and Daggers from the pack; a Katana built in code);
    - a credits file.
  - Blocked by: 1.
  - Check: screenshots of both fighters in rest pose, with each weapon; no missing textures; import is clean in headless.
- [ ] **14. Animation spike.** One fighter with the Katana:
  - locomotion (idle, walk, jog, sprint by speed; hip-turn strafing; backpedal; lean);
  - the guard pose with hand IK on the grip;
  - the four-light string played from its swings, with spine and hip follow-through.
  - Blocked by: 6, 7, 13.
  - Check: a pose-gallery screenshot sheet reviewed for hands on the grip, believable arcs and no clipping. If it doesn't hold up, adjust the approach here before task 15.
- [ ] **15. Full fighter animation.**
  - Delivers:
    - every move of the three weapons and bare hands;
    - two-handed grips for the Greatsword;
    - both hands for the Daggers;
    - the Iai sheathe;
    - block and guard;
    - the parry deflect with both weapons rebounding;
    - flinches by hit direction;
    - stun and daze;
    - disarm and weapon pickup;
    - dodge and backstep poses with ghost trails;
    - jump and land;
    - stomp and leap counters;
    - KO, death and victory;
    - the three ultimates' presentation.
  - Blocked by: 9, 10, 11, 14.
  - Check: the pose-gallery sheet for every move on both fighters; a match screenshot series.

### Phase E: look, arena and effects

- [ ] **16. Toon, outline and ink-wash look.** The toon material, inverted-hull outlines, the ink-wash post pass, and graphics presets.
  - Blocked by: 13.
  - Check: side-by-side screenshots of each preset; no shader errors in headless loading.
- [ ] **17. The floating Moonlit Shrine.**
  - Delivers:
    - the platform at radius 15 with its parapet, torii, lanterns and pillars;
    - the rocky underside;
    - the sky, moon and clouds;
    - the background mountains, pagodas, waterfalls and water;
    - drifting embers and ash.
  - Blocked by: 8, 16.
  - Check: screenshots from the gameplay, Watch and menu cameras; frame time within budget.
- [ ] **18. Combat effects and game feel.**
  - Delivers:
    - brush-stroke trails in three colours;
    - sparks and ink splashes;
    - the parry ring and camera push-in;
    - the warning mark with a reach effect for unblockables;
    - the ultimate aura;
    - the dropped-weapon beam and marker;
    - shake, field-of-view kicks, hit-stop and slow motion;
    - the reduce-flashes option.
  - Blocked by: 15, 16.
  - Check: screenshots of each event; every event in the demo's event table has its effect.

### Phase F: sound and music

- [ ] **19. Sound effects.** The Sonniss extraction and processing script with its sources list; generated gap-fill sounds; the event-to-sound table with variations; buses; 3D impacts; footsteps; arena ambience.
  - Blocked by: 6.
  - Check: every event in the demo's audio table has a sound; a headless run logs no missing sound files; the committed audio is under 40 MB.
- [ ] **20. Placeholder music.** Generated menu (110 BPM), battle (140 BPM) and match-point (160 BPM) tracks; a music director that switches at the round call; volume settings.
  - Blocked by: 19.
  - Check: tempos measured from the files; switching happens when a fighter reaches two wins.

### Phase G: screens and modes

- [ ] **21. Input devices and controls.** Per-player devices (keyboard and mouse, arrow-key layout, controllers 1 and 2), profiles with rebinding, PlayStation and Xbox names, the fight-stick preset, and saving.
  - Blocked by: 6.
  - Check: tests for the profile mapping and saving; rebinding every action works on keyboard and controller.
- [ ] **22. Menus.**
  - Delivers:
    - the title with a live background duel;
    - the main menu;
    - fighter and loadout select;
    - settings;
    - how to play and a move list generated from the data;
    - pause;
    - results;
    - the ink-wash UI theme and bundled fonts.
  - Blocked by: 21.
  - Check: screenshots of every screen; the whole flow is navigable with keyboard only and with controller only.
- [ ] **23. Training, Watch and Versus.** The training panel with dummy behaviours, refill and parry timing feedback; Watch with the side-on camera; Versus split screen with per-player cameras and prompts.
  - Blocked by: 22.
  - Check: screenshots of each mode; Versus runs smoothly with two controllers or a shared keyboard.
- [ ] **24. The full HUD.** Bars with a lag bar, posture hot and full states, pips, the ultimate badge, announcements timed on the rules' frames, toasts, prompts and the dropped-weapon marker.
  - Blocked by: 22.
  - Check: screenshots of each HUD state; announcements freeze during pause.

### Phase H: ship

- [ ] **25. Windows build and docs.**
  - Delivers:
    - the export preset;
    - the CI export job and the Release workflow uploading the zipped build;
    - the Pages workflow removed;
    - README, CLAUDE.md commands and code notes rewritten for Godot;
    - credits and licence notices;
    - `mvp-spec.md` marked as the web demo's record.
  - Blocked by: 12, 17, 18, 20, 23, 24.
  - Check: CI produces a Windows zip; the exported game launches and plays a match.
- [ ] **26. Retire the web version and verify.** Delete the TypeScript sources, web tests and scripts, the Vite config, the built `Monomachia.html` and the web dependencies, keeping npm only as the task runner. Run the full test suite, a 40-match soak and the whole screenshot set.
  - Blocked by: 25.
  - Check: all tests pass, the soak run is clean, and the screenshots are reviewed; the pull request is marked ready.
