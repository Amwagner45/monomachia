# Plan: Authored animation and the dodge roll

Spec: `docs/specs/authored-animation.md` · branch `feature/authored-animation` · draft pull request #12 (into `feature/godot-rebuild`)

## Destination

Every fighter animates from authored clips. The attacks come from Kevin Iglesias's packs, with UAL2 Source filling the gaps, retargeted onto the Rogue and the Hunter. Hits are decided by paths baked from those same clips, and every move's frame data is retuned to its clip. The dodge is a roll, big hits knock the defender down, the Greatsword rides on the shoulder, and each weapon has a draw and a victory pose. The procedural swings, the guard shuffle, the hip-turn, the lean and the stick poses are gone. A fresh clone without the packs plays the committed CC0 fallback clips and says so. The rules still decide everything at 60 steps a second and never read a clip.

## Notes

- **One task at a time.** Since task 1's gate the owner's OK is needed only at the hard gates below (see Decisions, Pacing). Before each task, merge `origin/feature/godot-rebuild` in and run the full tests. After each task:
  - tick it here;
  - update Progress;
  - in the spec, update the status line, any numbers the task changed, and tick each user story the build now fully delivers.
- **Hard gates** (nothing after the gate starts until the owner says OK):
  - task 1, the retargeting prototype;
  - task 5, the catalogue sheet, which gates the first clip assignment (task 9);
  - each weapon's review (tasks 14, 20, 23, 25), and the reactions and movement review (31), in the spec's order: Katana, Greatsword, Daggers, bare hands, then reactions and movement, then the round flow.

  The rules tasks (15–17) sit right after the Katana's review so that work goes on while the owner looks at it.
- **Every task ends with** `npm test` and `npm run typecheck` passing, a commit and a push. Visual tasks also end with sheets reviewed by eye. Tasks that change rules data also end with a clean 40-match soak, and each weapon's review adds a 300-match `soak:tune`.
- **Licence.**
  - Never commit an Iglesias file or a clip converted from one. They live in the packs' folder (`.assets-src-path`) and in the gitignored clip libraries.
  - Committed: the bone map, the clip manifest, the baked swing files, the roll curve and the frame data.
  - Before each commit, check `git status` for anything under the gitignored library folder or with an Iglesias clip name.
- **CI has no packs.** Every test that needs them skips itself with a message when the libraries are missing, and every other test passes on the committed CC0 fallback.
- **The rules stay free of graphics** (`game/sim`): no clip, AnimationTree or node. The bake and the import tool are tools, outside `game/sim`, and they write data the rules read.
- **A move's retune goes in the same commit as its baked swing:** the frame data, `test_moves`' deliberate-differences tables, the reach tests, the sheets and the soak.
- Use the glossary's terms (Clip, Swing, Dodge, Knockdown, Shouldered…) in code names.

## Decisions so far

- [Spec](../specs/authored-animation.md), approved by the owner on Oct 3, 2026.
- PR #11 already committed the whole UAL2 Source and root-motion GLBs (`UAL2_Source.glb`, `UAL2_Source_RM.glb`, `UAL2_Standard_RM.glb`), the female mannequin and the CREDITS note on the Iglesias packs, and raised the art budget to 110 MB. The spec's first step, bringing over only the clips used, is therefore done differently: the files are in, and task 3 folds the clips the clip table names into the committed library. Its `assets/ual2-source-and-iglesias-refs` worktree (`add-3d-references-530c11`) is clean and can go (task 2, with the owner's OK).
- The godot-rebuild plan's tasks this feature retires are marked there:
  - 14b (the swing editor) and 7.16–7.38 (the hand-keyed swings);
  - 14.14 (blade lag) and 14.15 (the parry-bounce prototype);
  - all of task 15 (full fighter animation), 15.9's ghost trails included. The owner chose on Oct 3 to retire 15.1–15.16 as well as 15.9, since this plan covers them.

  - 14.16 (the saya) goes into task 11, and 14.17 (the review sheets) into task 14 (the owner's choice, Oct 3, at task 1).

  The godot-rebuild tasks that waited on a retired one now wait on this plan:
  - 12.2 on task 25;
  - 18.12 on task 36;
  - 25.7 no longer waits on the swing editor.
- While a weapon is between tasks, a move with a baked swing plays its clip, and a move without one keeps the stand-in poses and its cone. The stand-ins go in task 35.
- The Greatsword's recovery slide keeps running along the facing; the retired 7.24 would have taken its direction from the follow-through.
- The counters (stomp, leap, evade) keep their demo cones; the retired 7.37 would have measured them from the paths.
- Story 42, the email to Kevin Iglesias, is drafted in the spec's Licence section; the owner sends it. Until he answers, the baked paths are committed.
- **Task 1 passed** (Oct 3). The owner chose foot locking under every clip, not just locomotion: task 8 builds it, and task 29 reuses it.
- **Pacing** (owner, Oct 3): tasks run back to back with no OK between them, each still ending with its checks, a commit and a push; work stops only at the hard gates (5, 14, 20, 23, 25, 31, 36).
- The merge of `origin/feature/godot-rebuild` (PR #11) into this branch was done at the start of task 1, on the owner's go-ahead (Oct 3).

## Progress

Oct 3, 2026. Plan approved by the owner. Merged `origin/feature/godot-rebuild` (PR #11) in with the owner's go-ahead; tests and typecheck pass.

Oct 3, 2026. Task 1 built: `tools/build_iglesias_bone_map.gd` writes `assets/kevin_iglesias/iglesias_bone_map.tres` (52 of the 56 profile bones), the six clips retargeted onto both fighters, and the findings in `docs/research/retarget-prototype.md`. Bends and crossing pass; the off hand sits 7–16 cm from the Greatsword's off-hand grip (for task 4's IK); planted feet creep up to 6 cm in the 2H attack and the roll's getting-up (foot locking, beyond task 29's locomotion, would cure it). One fix made: the hips' travel scaled to the legs (×1.14), which task 2's import tool must repeat. Roll01 [RM]'s root reads cleanly; Dodge01 is a sway, usable as the backstep only as its back half. The owner passed the gate the same day, choosing to extend foot locking to every clip (task 8 builds it, for the attacks and the roll's getting-up as well as locomotion), and to run the tasks back to back between the hard gates, stopping only at them.

## Build order

1. **The gate:** 1.
2. **The pipeline:** 2, 3, 4, 5 (the catalogue goes to the owner), 6, 7, 8.
3. **The Katana** (after the catalogue's OK): 9, 10, 11, 12, 13, 14 (its review goes to the owner).
4. **The rule changes** (while the owner reviews the Katana): 15, 16, 17.
5. **The Greatsword** (after the Katana's OK): 18, 19, 20.
6. **The Daggers** (after the Greatsword's OK): 21, 22, 23.
7. **Bare hands** (after the Daggers' OK): 24, 25.
8. **Reactions and movement** (after the bare hands' OK): 26, 27, 28, 29, 30, 31.
9. **The round flow** (after 31's OK): 32, 33, 34.
10. **Finish:** 35, 36.

## Tasks

### Phase A: the gate

- [x] **1. The retargeting prototype on five clips.** A bone map for Kevin's 56-bone `B-` rig onto Godot's humanoid profile, made the way `ual_bone_map.tres` is. Five clips are read through Godot's FBX importer from both HumanM and HumanF and retargeted: CombatIdle1H01, Attack1H01_R, Attack2H01, Roll01 and CombatDeath01, plus Dodge01 to settle the backstep. The root, scale, `B-handProp` and jaw tracks are stripped. The Hunter plays HumanM and the Rogue HumanF, with the Katana or the Greatsword roughly fixed in the main hand.
  - Throwaway apart from the bone map and a short findings note in `docs/research/retarget-prototype.md`. The converted clips go only to a gitignored scratch folder.
  - Check: contact sheets of each clip on both fighters at four phases, from the gameplay camera, three-quarter and close. The note also answers:
    - whether Roll01 [RM]'s root track can be read for the roll's travel;
    - whether Dodge01 works as the backstep.
  - **Gate.** The prototype passes if, after any bone-map or rest-pose fixes made in the task:
    - the hands hold the grip;
    - the feet neither slide nor cross;
    - shoulders, elbows and knees bend the right way on both fighters.

    Owner: decides pass or fail. On a fail, this plan is rewritten for the spec's fallback (UAL2 Source clips as first candidates, the procedural swing player kept for moves without one) before anything else.
  - Blocked by: none · Stories: 48

### Phase B: the pipeline

- [ ] **2. The packs' folder, the clip manifest and the import tool.**
  - **The packs' folder.** An untracked `.assets-src-path` names the folder the packs are unzipped in; without it the tools look in `assets_src/`. Both are added to `.gitignore`, and `import_assets.gd` reads the same setting instead of its hard-coded folder.
  - **The clip manifest** is committed and holds no animation data. For each clip it gives the pack, file and set, whether it is mirrored, its loop mode and its four markers in source frames. It starts with task 1's clips.
  - **The import tool** converts only the manifest's clips, through task 1's bone map (with the hips' travel scaled to each fighter's legs, as task 1 found), into one animation library per set (HumanM, HumanF), in a gitignored folder inside the Godot project. It is deterministic. Without the packs it exits with a message naming the setting.
  - **The export.** `npm run build` carries the libraries, and `--smoke` plays a match with them.
  - Also, with the owner's OK, remove the clean `add-3d-references-530c11` worktree.
  - Check:
    - a content test that every manifest clip has its four markers;
    - a local-only test that the tool finds every manifest clip, and that two runs write identical files;
    - a test that the bone map maps every bone the tool uses;
    - `git status` is clean after an import;
    - the exported build plays a clip.
  - Blocked by: 1 (and the owner's pass) · Stories: 38, 39, 41, 49
- [x] **3. The fallback library and the soak baseline.**
  - **The fallback library.** `build_animation_library.gd` adds every UAL2 Source clip the spec's clip table names to the committed CC0 library, read from the already committed `UAL2_Source.glb`.
  - **The soak baseline.** A 300-match `soak:tune` and a 40-match soak, run before any rules change, recorded in Progress. Each weapon's review is measured against them (±5 points).
  - Check: a content test that the CC0 library holds every fallback clip in the table; the art stays inside its 110 MB budget.
  - Blocked by: none · Stories: 40, 44
- [ ] **4. The weapon in hand.** The weapon is fixed to the main hand at a per-weapon grip offset, measured on each fighter's hand. A two-handed weapon (Katana, Greatsword) puts the off hand on its `OffHandGrip` with IK on top of the clip. The Daggers sit one in each hand and can be turned 180° about the hand into the reverse grip. Fixing the weapon is used only while a clip drives the arms; the stand-in poses keep posing it until task 35.
  - Check:
    - a content test that each grip offset puts the handle inside the fist on both fighters;
    - the off hand lands within 1 cm of the off-hand grip through task 1's clips;
    - sheets of the five clips with each weapon in hand.
  - Blocked by: 2 · Stories: 2, 11
- [ ] **5. The catalogue sheet.** The manifest grows to every first candidate in the spec's clip table, with provisional markers, and the import tool converts them. A shot scene renders every candidate on both fighters at four phases with its weapon in hand, grouped by weapon, and captioned with the clip's name, length and set.
  - Check: one page per weapon and one for the states, with no candidate missing (a test counts them against the manifest).
  - **Owner:** reviews the catalogue and swaps any clip. Swaps go into the spec's clip table. This review gates task 9.
  - Blocked by: 4 · Stories: 45
- [ ] **6. The bake.** The bake is a pure function. It takes a sampled clip (or a chain of clips), its markers and a speed between 1.0 and 2.0. It gives back:
  - the clip retimed onto rules frames;
  - each striking part's grip, blade and edge, and the body's coil, in the fighter's own space, one key per rules frame;
  - the move's startup, active and recovery frames from the markers.

  The swing file format gains a `baked` flag on a track (one key per frame, no splining), and the reader refuses a baked track with a missing frame. A bake command writes `game/sim/moves/swings/<weapon>.json` for the moves it is given, and a report of each move's speed and frames against today's.
  - Check: tests on a committed CC0 UAL clip, so CI needs no packs:
    - the markers land on the right rules frames at a given speed;
    - the samples match the posed hand within 1 mm;
    - the output is deterministic;
    - a missing marker or a speed outside 1.0–2.0 is refused;
    - a baked file round-trips;
    - the existing swing tests pass.
  - Blocked by: 4 · Stories: 2, 3, 43, 49
- [ ] **7. The reach correction and the Rogue's paths.**
  - **The reach correction.** Where a clip's arm stops short of the reach rule, the bake adds an arm-IK offset toward it. The offset eases in over the wind-up and out over the recovery, is at most 15 cm, and is written with the swing. The fighter view plays the same correction from the same data.
  - **The Rogue's paths.** Paths are baked from HumanM on the Hunter. The Rogue's HumanF clip is pulled onto the shared path with hand IK. A move whose HumanF clip is more than 5 cm off at any active frame is flagged, and the Rogue plays HumanM for it.
  - Check:
    - the correction stays under 15 cm and is zero outside the attack;
    - a move that needs more is reported;
    - a flagged move resolves to HumanM for the Rogue;
    - on a CC0 clip, the visible blade and the baked path agree within 1 cm on every active frame.
  - Blocked by: 6 · Stories: 2, 36, 37
- [ ] **8. The clip director: idle and attacks.** The clip director is a pure function, like `HudState`. It takes a fighter's rules state and the frame's events, and gives back which clips play, at what times and with what weights. `FighterView` applies its answer to an `AnimationTree` that is advanced only on rules frames.
  - **Covered here:**
    - the free idle by weapon class;
    - an attack's clip time set from its attack frame (wind-up across the startup, strike across the active frames, follow-through across the recovery);
    - a charge holding at the end of its wind-up;
    - hit-stop and pause holding the time;
    - the crossfades: 3 frames into an attack, 4 for a follow-up, 2 for a dodge-cancel, a cut for hitstun, 6 for locomotion and 8 for stances;
    - foot locking (the owner's choice at task 1's gate): the leg IK holds a planted foot where it landed under every clip, so the retarget's creep of up to 6 cm goes; task 29 reuses it for locomotion.
  - **Without the Iglesias libraries** it plays the fallback table, shows a small "animation packs missing" note in the match, and logs the setting to fix.
  - Moves without a baked swing keep the stand-in poses.
  - Check:
    - director tests on the cases above, and that the fallback is chosen when the libraries are missing;
    - a shot of the note;
    - a sheet of the idle on both fighters for each weapon class;
    - planted feet move under 1 cm through task 1's clips on both fighters.
  - Blocked by: 3, 4 · Stories: 3, 4, 6, 7, 40, 43

### Phase C: the Katana

- [ ] **9. Right Cut from end to end.** The first move on the whole path:
  - its clip's markers set in the manifest;
  - baked at the chosen speed;
  - its retuned frames in `katana.gd` and `test_moves`' differences table;
  - its baked swing in `katana.json`;
  - the rules hitting with it;
  - the director playing it on both fighters, with the Rogue's path check.
  - Check:
    - the swing checks on the baked path;
    - `test_duel_reach` for Right Cut;
    - the Katana string tests pass or are updated with the reason;
    - a debug-view shot with the flash where the blade meets the capsule;
    - contact sheets;
    - a 40-match soak is clean.
  - Blocked by: 5 (and the owner's OK), 7, 8 · Stories: 1, 2, 3
- [ ] **10. The Katana's other lights.** Return Cut, Kesa Cut and Crown Cut, each following the previous swing from its pose. The first-key continuity test is dropped for baked tracks; the side continuity test stays.
  - Check:
    - the swing checks;
    - the duel reach test for all four lights;
    - a defender can still block or parry the second light;
    - sheets of the L-L-L-L string with each stop;
    - a 40-match soak is clean.
  - Blocked by: 9 · Stories: 1, 4, 5
- [ ] **11. The Katana's heavies.** Both Iai Slashes (Sheathe Hips01_R chained into Attack1H04 or Attack1H05), Rising Heaven, Returning Draw and Heaven Splitter. The manifest and the bake learn chained clips here. The Iai needs the saya, so this task builds it: a saya made in code at the left hip whenever the Katana is the weapon (godot-rebuild 14.16, retired into this task). The sheathe, the sheathed hold kept while walking and strafing at block speed, and the dodge cancel out of it play from clips.
  - Check:
    - the swing checks, with the sheathed frames carrying no blade;
    - the Iai enters a defender at 3.6 m and misses at 4.2 m;
    - task 9's Iai tests of the godot-rebuild plan pass;
    - sheets of the stance, both draws and each heavy chain;
    - a 40-match soak is clean.
  - Blocked by: 10 · Stories: 1, 8
- [ ] **12. The Katana's sprint, dodge, backstep and jump attacks.** Running Draw, Leaping Cleave, Wind Cut, Whirl Cut, Rising Cut, Lunging Cut, Aerial Cut and Falling Crown.
  - Check: the swing checks; each hits from its distance in the test-distance table; the dodge attacks still come up facing the opponent; sheets; a 40-match soak is clean.
  - Blocked by: 11 · Stories: 1, 13
- [ ] **13. The Katana's Counter Lunge, Flash, unblockables and Moonsplitter.**
  - Counter Lunge.
  - Flash, as a pose-only clip.
  - Piercing Thrust and Swallow Sweep, with the thick-blade bonus.
  - Moonsplitter, held then released, in time with the rules' wave.
  - Check:
    - the evade counter's lunge test and the unblockable combat tests pass;
    - an unblockable hits where the light misses;
    - sheets of slash, overhead, thrust and sweep side by side, telling them apart in the first third of the wind-up;
    - a 40-match soak is clean.
  - Blocked by: 12 · Stories: 5, 13
- [ ] **14. The before-and-after video, and the Katana's review.**
  - **The video tool.** It renders each move of a weapon with the procedural version from a `feature/godot-rebuild` checkout and the clip version from this branch, side by side.
  - **The review package:**
    - the video;
    - contact sheets of every Katana move on both fighters;
    - a list of moves that share or mirror a clip;
    - sheets of the guard and the trails, and a checklist mapping each of the animation spike critique's fixes and conditions that still applies to its sheet or test (from godot-rebuild 14.17, folded in here; godot-rebuild task 14 is ticked when this review passes);
    - a 300-match `soak:tune`, with the Katana's win rate within ±5 points of the baseline and rounds and disarms in their targets.
  - Check: the package is committed (the video stays local under `shots/`) and sent to the owner.
  - **Owner:** OKs the Katana. This gates task 18.
  - Blocked by: 13 · Stories: 44, 46, 47

### Phase D: the rule changes

- [ ] **15. The Greatsword's shoulder carry.**
  - A shouldered flag on an armed Greatsword fighter. It turns on after 20 frames of moving in the free state, and at every round start. It turns off on any attack, block, parry, dodge, backstep, hitstun, blockstun, knockdown, disarm or pick-up.
  - An attack from the shoulder adds `GS_SHOULDER_LIFT_FRAMES` (6) to its startup, and its dodge cancel opens 6 frames later.
  - The computer opponent's timing and reach estimates include the lift.
  - Check:
    - rules tests for each way on and off, and that standing still and jumping leave the flag alone;
    - an attack from the shoulder hits 6 frames later;
    - dodge attacks and follow-ups never pay;
    - the brain's estimate includes the lift;
    - a 40-match soak is clean.
  - Blocked by: none · Stories: 10
- [ ] **16. Knockdown.** A new fighter state.
  - **Causes:** a hit (not a block, a parry or a counter) from an unblockable, a heavy at full charge, or Mountain Slam, Meteor Drop or Leaping Smash. A knock-out plays the KO instead.
  - **Phases:** fall 20, ground 30 and stand-up 25 frames (provisional).
  - **Invulnerability:** from the fall's first frame to stand-up frame 10.
  - **The last 15 frames:** the fighter can block or parry, but can't attack, dodge or move.
  - **Events:** `knockdown` and `standup`.
  - It replaces the hitstun of those hits. Damage, posture and knockback are unchanged, and the stomp keeps its 70-frame stun.
  - The computer opponent doesn't attack a downed fighter before the guard window.
  - Until task 28 the view plays the fallback (Hit_Knockback, LayToIdle).
  - Check:
    - rules tests for each cause, and for no knockdown on a block, a parry or a KO;
    - the invulnerability window and the guard window;
    - free on the last frame;
    - the stomp stays 70;
    - the brain waits;
    - a 40-match soak is clean.
  - Blocked by: none · Stories: 18, 19, 20
- [ ] **17. The roll's travel.** The dodge's curve (today `ease_out_cubic` over 16 frames) becomes Roll01 [RM]'s ground travel. The import tool reads it once, normalised to 0–1 and resampled to 16 frames, and it is stored as 17 numbers in the rules' constants. The distance, frames, i-frames, recovery, the forward-dodge counter window and the backstep are unchanged.
  - Check:
    - the roll ends at the same distance in the same frames along the stored curve;
    - the curve rises from 0 to 1 and never falls;
    - the i-frames and the counter window are unchanged;
    - the backstep is unchanged;
    - a local-only test that the curve matches the pack's;
    - a 40-match soak is clean.
  - Blocked by: 2 · Stories: 26, 27

### Phase E: the Greatsword

- [ ] **18. The Greatsword's string, Piercing Lunge and the carry.** Heavy Swing, Backswing, Overhead Strike and Piercing Lunge, two-handed. The view adds the carry: CombatIdle2H01, ObjectGripShoulder masked onto the upper body over locomotion while shouldered, and the 6-frame lift as a crossfade from the shoulder into the attack's first frame.
  - Check:
    - the swing checks;
    - the duel reach test at 3.0 m;
    - task 10's tests of the godot-rebuild plan;
    - director tests that the carry shows when the flag is on;
    - sheets of the carry, the lift and each move;
    - a 40-match soak is clean.
  - Blocked by: 14 (and the owner's OK), 15 · Stories: 1, 9
- [ ] **19. The Greatsword's sprint, dodge, backstep and jump attacks, Guard Crusher and Counter Lunge.** Shoulder Charge, Leaping Smash, Rising Edge, Lunge Cleave, Aerial Chop, Guard Crusher and Counter Lunge. Shoulder Charge and Guard Crusher strike with a baked body track.
  - Check: the swing checks (body tracks exempt from the wrist check); each hits from its table distance; the posture-crush tests pass; sheets; a 40-match soak is clean.
  - Blocked by: 18 · Stories: 1, 13
- [ ] **20. The Greatsword's unblockables and Impaler, and its review.**
  - The moves: Reaping Sweep, Mountain Slam, Low Sweep (narrower and faster than Reaping Sweep, and low enough to jump), Skewer, Meteor Drop and Impaler.
  - The review package as in task 14.
  - Check:
    - Low Sweep misses a jumper;
    - the slams knock down;
    - the unblockable combat tests pass;
    - the review package, including the soak within ±5 points.
  - **Owner:** OKs the Greatsword. This gates task 21.
  - Blocked by: 16, 19 · Stories: 5, 13, 18, 44, 46, 47

### Phase F: the Daggers

- [ ] **21. The Daggers' string and heavies.** Quick Slice, Off-hand Slice, Twin Rip, Flurry Finisher, Twin Fang, Spinning Backhand and Passing Cut, with a baked track for each hand. The combat idle holds the daggers in reverse grip. They flip forward over the attack's 3-frame crossfade, and back over the last 6 recovery frames when no follow-up comes.
  - Check:
    - the swing checks for both blades;
    - the duel reach test at 2.0 m;
    - task 11's tests of the godot-rebuild plan;
    - a director test of the grip flip;
    - sheets;
    - a 40-match soak is clean.
  - Blocked by: 20 (and the owner's OK) · Stories: 1, 11
- [ ] **22. The Daggers' sprint, dodge, backstep and jump attacks, Shadow Step and Counter Lunge.**
  - Slide Slash, with Attack1H02 masked onto the upper body over RunSlide01.
  - Pounce, Reverse Spin, Flick, Rebound Lunge, Air Slash, Dive Stab and Counter Lunge.
  - Shadow Step: Roll01 sped up, with the body hidden in the blink.
  - Check: the swing checks; each hits from its table distance; the Shadow Step backstab tests pass; sheets; a 40-match soak is clean.
  - Blocked by: 21 · Stories: 1, 13
- [ ] **23. The Daggers' unblockables and Lightning Tempest, and their review.**
  - The moves: Serpent Sweep, Needle Thrust and Lightning Tempest (the chained spin and the final).
  - The review package as in task 14.
  - Check: the unblockable combat tests pass; the Tempest follows the rules' phases; the review package.
  - **Owner:** OKs the Daggers. This gates task 24.
  - Blocked by: 22 · Stories: 13, 44, 46, 47

### Phase G: bare hands

- [ ] **24. The punches.** Jab, Cross, Hook, Slip Jab, Spinning Backfist, Lunging Palm and Counter Lunge, striking with the fist.
  - Check:
    - the elbow checks;
    - the duel reach test at 1.6 m;
    - the disarmed tests pass (no block or redirect);
    - sheets;
    - a 40-match soak is clean.
  - Blocked by: 23 (and the owner's OK) · Stories: 1, 12
- [ ] **25. The kicks and Breaker Palm, and the bare hands' review.**
  - Roundhouse, Spinning Heel, Snap Kick, Flying Knee (a shin segment), Dragon Kick, Air Kick and Axe Kick, with baked foot tracks.
  - Breaker Palm.
  - The review package as in task 14.
  - Check: each hits from its table distance and misses from 6 m; the review package.
  - **Owner:** OKs bare hands. This gates task 26.
  - Blocked by: 24 · Stories: 12, 13, 44, 46, 47

### Phase H: reactions and movement

- [ ] **26. Hits, blocks and long stuns.**
  - Hitstun plays CombatDamage01 or 02, by the hit's side.
  - A held block holds the weapon class's Parry Loop, and blockstun plays its Parry Hit.
  - The stomp, leap, redirect, disarm-stagger and impaled stuns play Stun01, fitted to their length.
  - The procedural recoil and lean go.
  - Check: director tests for each state's clip and fit; sheets from the gameplay camera.
  - Blocked by: 25 (and the owner's OK) · Stories: 14, 15, 17
- [ ] **27. The parry.** The parrier plays Parry Hit. The parried attacker's own clip runs backwards from its contact frame over the rebound, then hands over to Stun01 for the rest of the recoil. Flash and redirect parries too. If the reversed clip looks wrong, the fallback is Stun01 from the contact frame.
  - Check: director tests for the reversed time and the handover; sheets of a parry for each weapon pairing.
  - Blocked by: 26 · Stories: 16
- [ ] **28. Knockdown and KO.** Knockdown01 Fall, Ground and StandUp fitted to the three phases. CombatDeath01–04 picked by the final blow's direction (front or back) and strength (light or heavy), slowed by the final-blow slow motion.
  - Check: director tests for the phase fit and the death pick; sheets; the phase lengths settled from the clips' markers and a soak, with the spec updated.
  - Blocked by: 16, 27 · Stories: 18, 21
- [ ] **29. Locomotion.**
  - A 2D blend space on velocity in the fighter's facing space:
    - Walk01 and Run01 forward, backward and on the diagonals;
    - StrafeWalk01 and StrafeRun01 sideways;
    - Sprint01 in its five forward directions;
    - Turn01 when the facing turns more than about 30° while standing.
  - The playback rate follows each clip's measured stride.
  - Foot locking keeps planted feet still.
  - The guard shuffle, the hip-turn, the reversed cycle and the lean go. Footsteps follow the clips' foot contacts.
  - Check: director tests for the blend weights by direction and speed; planted feet move under 1 cm; strips of running, strafing, backpedalling and sprinting; the footstep tests pass.
  - Blocked by: 28 · Stories: 22, 23, 24
- [ ] **30. The roll and the other states.**
  - **The roll** plays Roll01 with the body turned toward the roll's direction. The body turns back to face the opponent over the recovery, or over a dodge attack's first 3 frames.
  - **The backstep** plays Dodge01.
  - **A new roll sound** (cloth and a thump) plays on a dodge that isn't a backstep.
  - **The other states:** jump and land, the stomp, the leap, the evade lunge, the pick-up (Loot01) and the recall. On a disarm the weapon leaves the hand (its model on the ground is godot-rebuild 18.10's), and it returns on the pick-up or the recall.
  - Check:
    - director tests for the roll's turn and each state's clip;
    - a sound test that the roll and the backstep play different cues;
    - sheets.
  - Blocked by: 17, 29 · Stories: 13, 25, 28, 29, 30
- [ ] **31. The reactions and movement review.**
  - Contact sheets and strips of every state on both fighters.
  - A short playtest of the reactions, the roll and the knockdown.
  - **Owner:** OKs reactions and movement. This gates task 32.
  - Blocked by: 30 · Stories: 47

### Phase I: the round flow

- [ ] **32. The draw at the round intro.**
  - The Katana is drawn from its saya at the left hip (Unsheathe Hips01_R).
  - The Daggers are drawn from two leather sheaths at the small of the back (Unsheathe Hips01_Both, with IK onto the sheaths). The sheaths are new meshes built in code.
  - The Greatsword is lifted to the shoulder (CombatEnter2H01).
  - Bare hands play CombatEnter1H01.
  - Check: director tests for the intro clip by weapon; sheets of each draw; the scene smoke test loads the sheaths.
  - Blocked by: 31 (and the owner's OK) · Stories: 31
- [ ] **33. The victory poses from the packs.** The Katana sheathes into the saya (Sheathe Hips01_R) and bows (Reverence01); bare hands cheer (Cheer01).
  - Check: director tests for the victory clip by weapon; sheets.
  - Blocked by: 32 · Stories: 32, 35
- [ ] **34. The hand-keyed victories.** Both are keyed in Blender on the Quaternius rig, CC0 and committed:
  - the Daggers' toss, flip and catch;
  - the Greatsword planted in the ground, with both hands on the pommel (hand IK locks them to it).
  - Check: the clips are in the committed library; sheets; the art budget holds.
  - Blocked by: 33 · Stories: 33, 34

### Phase J: finish

- [ ] **35. Retire the procedural animation.**
  - Removed: `SwingPlayer`, `StickPose` and the WeaponHold idles, the guard shuffle's and stance's leftovers, the demo swings (`katana_demo.json` and `scripts/swings`), and the posing of weapons in space.
  - Added: a director test that every move of every weapon resolves to a clip, and a local-only test that re-bakes every move and fails if a committed swing file differs.
  - Check:
    - the full tests and the typecheck pass;
    - CI passes without the packs;
    - the scene smoke test loads every scene;
    - a 40-match soak is clean.
  - Blocked by: 34 · Stories: 37, 43, 49
- [ ] **36. The final playtest and the hand-over.**
  - A playtest of cancels, hitstun interrupts, the roll, knockdowns and the shoulder carry.
  - The final sheets and soak.
  - The spec and the godot-rebuild docs brought up to date, and the pull request marked ready.
  - **Owner:** plays the build and approves the pull request.
  - Blocked by: 35 · Stories: 1–49
