# Milestone 1: inputs for the spec

The owner's answers from the milestone-1 grilling (Oct 4, 2026), with the defaults to propose and the facts found while preparing it. `/to-spec` turns these into `docs/specs/milestone-1.md`; delete this file then. The design-level answers are already in `docs/design.md`'s "(Oct 4)" lines; this file holds the rest.

Milestone 1 is the Hunter (both palettes) with the Katana and bare hands on the Moonlit Shrine, brought to final quality, including everything inside a round (`docs/design.md`, Order of work; `docs/adr/0001-animation-leads-realistic-look.md`).

## Decisions (the owner's answers)

### Before milestone 1

- **Consolidate first.** In the owner's words: "I want to consolidate before starting on the new design and development path. The html can be retired and the rebuild should be the master branch." The order is in `docs/plans/godot-rebuild.md` under Triage and consolidation: the finished lanes merge into the rebuild (PRs #21, #25 and #19; #7 was closed as superseded by the lanes board), stage 14 retires the web version, CI goes green, and the rebuild merges into `master`. Milestone 1 branches from `master`.

### Order and scope

- **Work order:** the pipeline first (the asset repository, the Blender-to-game export, the frame-data generator with its timing-band test, and the replay and save-and-restore tests), then a pilot family, the Katana's light string, all the way to final quality (keyed into its band, with its deflect pairs, hit reactions, sound and effects) and the owner's review. The other move families follow one at a time.
- **Roster:** the Rogue, the Greatsword and the Twin Daggers are hidden from the menus during milestone 1; a dev flag still shows them, and their code and tests stay.
- **Katana moves:** every move a milestone-1 match can reach is re-keyed. The evade's paired clip and both Counter Lunges (the Katana's and bare hands') wait for the Greatsword's slams in milestone 2.
- **Weather:** only the clear night, with one wind moving the clouds, branches, petals, grass, banners and cloth. The weather system and the other four states come after sign-off, and both performance gates are measured on the clear night.
- **Black-and-white mode:** after milestone 1. Milestone 1 adds a test that the crimson and indigo palettes read apart in grey.
- **Menus:** the HUD, the round calls, the finisher prompt and Warrior Slain get the full redesign; the menus take the new theme (colours, fonts, panels) so nothing looks ink-wash, and their layouts are redone later.

### Timing

- **Bands:** Claude drafts one timing band per move kind (light, string heavy, Iai draw and follow-ups, unblockable, each movement attack, block ability, ultimate) for the Katana and bare hands, scaled from the 400–500 ms anchor for the Katana's lights and checked against For Honor footage. Distance bands start from today's duelling distances. The owner approves the table in the spec.
- **Protected timings:** retuned once at the start, then frozen (now in `docs/design.md`).
- **Momentum:** guarded starts and stops within about 6 frames (0.1 s); run stops and plant-and-reverse pivots about 12–15 frames (0.2–0.25 s, up to about 0.5 m); a sprint stop about 20 frames and 1 m (now in `docs/design.md`).
- **Gait speeds:** the rules' walk, run, strafe and sprint speeds become each clip's own measured speed, committed with the frame data (now in `docs/design.md`). This replaces PR #21's stride-matched playback rate.

### Making the clips and art

- **Who keys:** Claude makes first passes by script in Blender (longer wind-ups, re-gripped hands, travel, block-outs of new clips); the owner polishes the signature moves (the Iai, the deflect pairs, the finishers) in Cascadeur, bought when the first polish starts.
- **Katana grip:** two hands for every cut (now in `docs/design.md`), so most Katana clips are re-keyed.
- **Asset repository:** a private GitHub repository with Git LFS holding the packs, Blender sources and exports (about 2 GB). The raw Sonniss zips stay outside it; only processed sounds are committed, as today.
- **Art source:** CC0 scanned materials and models (Poly Haven, ambientCG) plus models built in Blender, partly by script.
- **The Hunter's look:** realistic crimson- and indigo-dyed materials with wear and oriental patterns; the tricorn and scarf remodelled in Blender with oriental touches, the scarf's ends on spring bones. Faces stay neutral. Cloth simulation and faces wait for milestone 2's models.

### Presentation

- **Finisher prompt:** heavy, within about a second of slow motion (now in `docs/design.md`).
- **Katana finisher cut:** diagonal, shoulder to opposite hip (now in `docs/design.md`).
- **Bare-hands finisher:** turn the attack aside, then a crushing strike (now in `docs/design.md`).
- **Round end:** round KOs on the gameplay camera with a short beat; the authored KO shot and the bow or cheer only for the match-winning KO (now in `docs/design.md`).
- **Ultimate shot:** only once it connects (now in `docs/design.md`).
- **Rendering:** Ultra may upscale to 4K (about 1440p–1800p with FSR 2.2); Low may drop atmosphere but keeps what reads the fight (now in `docs/design.md`).

### Sound

- **Music:** extend the code-generated score with the new instruments (taiko, shakuhachi, biwa, low choir, with electronic and metal layers at match point) for the sign-off build. The owner did not pick free-licence tracks.
- **Vocals:** placeholders until after milestone 1; a pack is bought after milestone 1's spending review. The owner did not pick recording their own voice.

### Checks

- **Balance run (mirror matches):** no failures, rounds of 60–90 s, 0.3–0.6 disarms per round, finishers in some rounds (the share set after the first run), and the stomp, the leap, Flash, both ultimates and a pick-up all appear. Per-weapon win rates are off until milestone 2.
- **Godot check:** judged at the pilot family and the look test scene against written criteria, and confirmed at sign-off.

## Defaults to propose in the spec (not yet confirmed by the owner)

- Bare hands stay the disarmed state, not a loadout: there's no bare-hands draw, and the cheer plays when a disarmed fighter wins.
- Clip work starts at once; only art conversion (materials, models, the arena, how effects look, the UI style) waits for the mood board and the look test.
- Training plays the finisher, then refills HP. The computer lands finishers more often on higher difficulties.
- After a Katana finisher, which already re-sheathes, the victory pose skips its own sheathe.
- The Blood setting ships in milestone 1 and defaults to On.
- In matches an unblockable's reach shows only through the red 危, its sound and the blade's glint; labels and floor markers appear only in Training.
- The dropped-weapon beam retires and the stuck weapon gets a faint glint; the HUD's off-screen marker stays, restyled; the reduce-flashes option stays and covers the new effects.
- Every parry, Flash and redirect gets a short camera push-in, which Reduce flashes turns off.
- Deflect pairs follow the attack directions; when a blade parries a fist or a foot, the attacker recoils without being cut.
- The Greatsword's and Daggers' frame data come from their current clips through the same generator, with no band test until milestone 2.
- Inertial blending and the physical reaction layer are custom skeleton modifiers that only change the picture.
- Markers set in the slimmed Animation Studio give active frames, cancels and branch points. CI checks the committed frame-data table and its bands; a local-only test re-bakes every move from the clips and fails on any drift.
- Each attack's travel is baked per frame from the hips and foot plants, and swings are sampled relative to the moving body, so travel isn't counted twice.
- An attack started out of a run keeps none of the run's speed in the rules (`ATTACK_MOMENTUM_KEEP` retires); the leftover shows only in the blend.
- A longer disarmed roll clip covers the disarmed dodge's 1.5× distance inside the same protected frames.
- The disarmed weapon's flight is deterministic, along the knock or deflect direction and inside the walls, and its landing angle is rules state. The pull-out pick-up takes as long as its clip.
- The computer reads the generated frame-data table; 12.2–12.5 run after the frame-data change.
- Replay test: a seeded match run twice gives matching state hashes. Save-and-restore test: save mid-match, restore, step again and compare. Both cover the finisher and the stuck weapon.
- "Holds 60 fps" means 99% of frames take 16.7 ms or less in a scripted worst-case replay (both ultimates, a finisher, blood and petals, at the wall), with shaders warmed up first. Training and Watch meet the Duel's gate; Versus split screen gets its own target (60 fps at High on the RTX 3090).
- The ultimates' energy (element and colour) and the gameplay camera's framing are settled on the mood board and in the look test scene.
- The upgraded Shrine gains banners, and grass in the broken paving, for the wind and the arena reactions to move. Footsteps are stone only.
- Moves come to the owner family by family, each with sheets, a side-by-side video and a play session; footage of the reference games stays on the owner's machine.
- The spec proposes size budgets per place (public repository, per asset, shipped game) for the owner to adjust.
- `soak.gd`'s round-length target changes from 35–60 s to 60–90 s.
- The laptop stays available for benchmarking the Low preset.

## Facts found (Oct 4)

- The Katana has 21 moves plus Moonsplitter, with light and heavy versions of each movement attack. Bare hands have 15: a three-hit light string (Jab, Cross, Hook), two heavies, eight movement attacks, Counter Lunge, and Breaker Palm as the ultimate. Neither has an overhead slam, so no milestone-1 move can be evaded.
- Bare hands can't be picked as a loadout (`PLAYABLE_WEAPONS` is katana, greatsword and daggers).
- Each side already wears its own palette (`match_selection.gd`), but the Hunter's two palettes are "Umber and tobacco" and "Ash and rust", so both are re-dyed crimson and indigo.
- Protected timings today: light hitstun 14, heavy 26, ultimate 40; blockstun 10 (light) and 16 (heavy); hit-stop 4 and 7; knockdown 20 frames falling, 30 down and 25 rising. The roll takes 16 frames (12 invincible) plus 9 of recovery over 2.8 m; the backstep 14 (10) plus 9 over 2.1 m. Parry windows are 9 frames for the Katana and 8 for the redirect; the input buffer is 8.
- At their own speed the Katana lights' source clips land in 233–300 ms, against the 400–500 ms band (24–30 frames). Today they play 1.15–1.86× fast, and Right Cut lands on frame 11. Knockdown01 plays at 2×, and PR #21's roll plays Roll01 at about 2.75× (tumbling) and 3.8× (getting up). About 100 clips need keying or re-keying.
- Movement today: run speed 3.9 m/s forward, 3.5 sideways and 3.0 back, sprint 7.2, and 0.6× the run speed while blocking. Acceleration 38 m/s² (full run in about 0.1 s), deceleration 30 m/s², turning 14 rad/s; a tap step covers 0.55 m in 8 frames. Disarmed: speed ×1.2, dodge ×1.5, jump ×1.35.
- Round flow today: the round intro lasts 100 frames, with "Fight!" at frame 62; the round end lasts 170 frames, the winner's victory pose starting at frame 70. A KO triggers 50 frames of slow motion at 0.3×. Moonsplitter is a 36-frame wind-up (the stick picks the variant) and then a wave that crosses the stage. The disarmed ultimate opens a 40-frame choice at 0.35×.
- Max HP is 100, so a finisher needs 5 HP or less plus a full posture meter. A Katana light deals 6 HP and its heavies 12–15, and a disarm deals no HP damage, so finishers may be rare.
- `soak.gd` targets rounds of 35–60 s, 0.3–0.6 disarms per round and 45–55% win rates per weapon; the last runs averaged 39.4–39.9 s and 0.74–0.75 disarms. There is no replay or save-and-restore test yet.
- Laptop bench at 1080p on the Ryzen 7 4700U: the toon Low preset ran at 99.9–102 fps and High at 66.8–69.
- Asset sizes: `Desktop/Monomachia-assets` is about 1.9 GB (Iglesias 1.1 GB, Quaternius 0.8 GB, effects 37 MB); the Sonniss GDC 2026 zips are 6.5 GB. GitHub Free includes 10 GiB of LFS storage and 10 GiB of LFS downloads a month.
- Cascadeur Indie allows commercial use only while revenue or funding stays under $100,000 a year. Claude can script Blender but can't operate Cascadeur.
- The Sonniss bundle holds only a few male effort vocals (a warrior's "Ai yah" and a yell, male panting) and no pain or death cries. Today's music is a code-generated placeholder at 110, 140 and 160 BPM.
- Godot 4.5 and later have a stencil buffer, so the black-and-white mode's colour mask is feasible. Godot has no skinned-cloth solver, and the build uses no spring bones or soft bodies yet.
- The Shrine has no banners or grass today. Its props are lanterns, torii, pillars, pines, dead trees, floating rocks, pagodas and a temple hall, with a lake and waterfalls in the backdrop. Its wind is a fixed vector that moves only embers and ash, and footsteps have no surface types.
- Today's Katana, built in code, has a 0.72 m blade; its duelling distance is 2.5 m and its reach 2.1 m. Bare hands' are 1.6 m and 1.2 m.
- Task 31's review found that the weapon in the free state is still posed by `StickPose`, a likely cause of the "weapon leaves the hands" complaint. Nothing brings an edited clip back into the game yet, and `import_clips` reads only the packs' FBX paths.
