# Spec: Monomachia rebuilt in Godot

Oct 1, 2026 · status: in build, one task at a time. Tasks 1–6, 13 and 21 are done, and of the broken-down tasks 13.1, 25.1–25.3 and 16.1–16.3; next is 16.4 (see the plan's build order and Progress) · branch `feature/godot-rebuild`

The playable duel from the web demo, rebuilt in Godot 4.7 as a PC game on the new direction from `docs/design.md`. Real fighters replace the block puppets, weapons swing along authored paths that also decide what they hit, the camera sits over the shoulder like For Honor, and the fight takes place on a larger floating shrine drawn in a toon and ink-wash style. The rules, the three weapons, the four modes, the computer opponent and the remappable controls carry over; the web version is retired once the Godot build matches it.

## Problem Statement

The demo proves the duel works, but it doesn't feel or look like the game in `docs/design.md`:

- Combat is stiff. Weapons are held out in front, each swing pops through 2–6 frames of motion with the hands moving in straight lines, and consecutive swings don't continue from where the last one ended, so they feel random.
- The rules add to the stiffness: attacks root the fighter in place, almost nothing can be cancelled, and hits are decided by an invisible cone around the attacker rather than by where the blade actually goes.
- Fighters are block puppets, the look is generic, and the arena is small.
- A browser game built with three.js is the wrong base for a PC fighter with eight fighters, nine weapons and real art.

## Solution

A Godot 4.7 PC game (Windows) that plays the same duel with the same rules and content (Katana, Greatsword, Twin Daggers; Duel, Training, Watch, Versus; posture, parry, disarm, counters and ultimates), rebuilt on the foundations the design update asks for:

- the rules layer ported line for line to GDScript and checked against the original, then changed on purpose for fluid combat;
- weapon swings authored as paths that drive both the animation and the hit detection;
- rigged fighters from the Quaternius packs (two fighters to start: the Rogue and the Hunter), with locomotion clips plus procedural animation for everything the packs lack;
- the new strings for the three weapons from the design doc;
- a For Honor-style camera, a larger walled floating Moonlit Shrine, and a toon, outline and ink-wash look;
- recorded sound where the Sonniss bundle has it, generated sound and placeholder music at the target tempos where it doesn't.

## User Stories

A ticked story works in the Godot build today. The plan names the tasks that deliver each of the others.

### Playing a duel

1. [ ] As a player, I want to start Monomachia as a Windows program, so that I can play without a browser.
2. [ ] As a player, I want a title screen with a live duel playing behind it, so that the game feels alive the moment it opens.
3. [ ] As a player, I want to choose Duel, Training, Versus or Watch from the main menu, so that I can play the way I want.
4. [ ] As a player, I want to pick my fighter, my weapon and my two block abilities before a match, so that I fight with the loadout I prefer.
5. [ ] As a player, I want to pick the computer's fighter, weapon and difficulty (Easy, Normal, Hard), or leave its weapon random, so that I control the challenge.
6. [x] As a player, I want the match to be first to three rounds with a clear round call and "Fight", so that I always know where the match stands.
7. [ ] As a player, I want health bars with the posture bar underneath, round pips and an ultimate badge, so that I can read the state of the fight at a glance.
8. [ ] As a player, I want a results screen with rounds won and match stats, and options to rematch, change fighters or go to the main menu, so that I can play again quickly.
9. [ ] As a player, I want to pause at any time and reach the move list, controls and settings from the pause menu, so that I can check things mid-match.
10. [x] As a player, I want the game to pause itself when the window loses focus, so that I don't lose a round while tabbed out.

### Camera and movement

11. [ ] As a player, I want the camera over my fighter's shoulder, slightly more zoomed out than For Honor, and always locked on to my opponent, so that I see my fighter, my opponent and the space between us.
12. [x] As a player, I want to move in eight directions around my opponent, step with a tap, sprint with a double-tap and hold, dodge with a direction, backstep with no direction, and jump, as in the demo, so that the controls I learned still work.
13. [ ] As a player, I want my fighter to lean into runs and turns, and to dash evasively when dodging, so that movement looks real.
14. [ ] As a player, I want to walk noticeably faster while blocking than in the demo, so that I can reposition while guarding.
15. [ ] As a player, I want a larger arena with walls at the edge, so that there's room to manoeuvre and nobody falls off.

### Attacking

16. [ ] As a player, I want each swing to continue from where the last one ended (a right-to-left cut followed by a left-to-right cut), so that strings flow.
17. [ ] As a player, I want every follow-up to be optional, so that I can stop after any hit and recover normally.
18. [ ] As a player, I want two lights to flow into a heavy as the third hit with every weapon, so that I have a standard finisher.
19. [ ] As a player, I want attacks to feel heavy: a visible wind-up, a strike that lands with hit-stop, and a follow-through, so that hits have weight.
20. [ ] As a player using a colossal weapon, I want the swing to pull my fighter along with its momentum, so that the weapon feels heavy.
21. [ ] As a player, I want a hit to register only when the blade actually reaches my opponent, and a swing to miss when it visibly misses, so that I trust what I see.
22. [ ] As a player, I want unblockable attacks to reach further than normal ones and to show their reach with a red ink trail and warning mark, so that I can read them and pick the right counter.
23. [ ] As a player, I want to dodge out of the late recovery of my heavies, not only my lights, so that I'm never fully stuck after committing.
24. [ ] As a player facing a string, I want to be able to block or parry the later hits after taking the first one, so that one mistake doesn't cost me a whole string (there is no combo breaker).

### Katana

25. [ ] As a Katana player, I want a string of four lights, alternating sides and ending in a crown cut, so that the Katana is the slashing weapon the design describes.
26. [ ] As a Katana player, I want my heavy to be the Iai Slash: pressing heavy sheathes the blade, I can strafe while holding it, and releasing draws a long-range slash, so that the Katana has its signature quick-draw.
27. [ ] As a Katana player, I want the Iai Slash to be vertical (from above) unless I'm holding left or right when I release, which makes it horizontal (right to left), so that I choose its shape.
28. [ ] As a Katana player, I want an optional heavy follow-up after each Iai Slash: a rising cut from below after the vertical one, and a left-to-right cut after the horizontal one, so that I can extend the string or stop.
29. [ ] As a Katana player, I want a fully held Iai (2.5 s) to release by itself as a power attack, as other charged heavies do, so that the charge rules stay consistent.
30. [ ] As a Katana player, I want Flash, Piercing Thrust and Swallow Sweep as block abilities and Moonsplitter as the ultimate, as in the demo, so that the Katana keeps its identity.

### Greatsword

31. [ ] As a Greatsword player, I want side-to-side light swings that ride the sword's momentum, with the second swing starting faster than the first, so that the weight shows.
32. [ ] As a Greatsword player, I want my heavy string to be an overhead strike followed by an optional unblockable low sweep, so that the greatsword has a feared finisher.
33. [ ] As a Greatsword player, I want my dodge attacks to be thrusts (a quick blockable stab on light, an unblockable skewer on heavy), so that attacking out of a dodge matches the design.
34. [ ] As a Greatsword player, I want Reaping Sweep, Mountain Slam and Guard Crusher as block abilities and Impaler as the ultimate, as in the demo.

### Twin Daggers

35. [ ] As a Daggers player, I want a four-light string that alternates hands (right slash, left slash, crossing cut, double stab), so that the continuity rule holds for two blades.
36. [ ] As a Daggers player, I want to dodge out of any light as soon as it connects or whiffs, so that the daggers slip in and out.
37. [ ] As a Daggers player, I want my heavy to be a dashing double stab that can flow into a spinning backhand, so that the daggers have a committal option.
38. [ ] As a Daggers player, I want my dodge light to be a passing cut that carries me along my dodge direction, so that I can outmanoeuvre the opponent.
39. [ ] As a Daggers player, I want Serpent Sweep, Shadow Step and Needle Thrust as block abilities and Lightning Tempest as the ultimate, as in the demo.

### Defending

40. [ ] As a player, I want parries to look cinematic, with both weapons visibly bouncing off each other, sparks, a ring and a distinct clang, as in Sekiro, so that a parry feels like a reward.
41. [x] As a player, I want the parry, block, posture, disarm, counter (stomp, leap, evade) and ultimate rules to work exactly as in the demo, so that what I learned still applies.
42. [ ] As a player, I want the warning mark and attack type (thrust, sweep, slam) to appear over an unblockable's attacker during the wind-up, so that I know which counter to use.

### Fighters and look

43. [ ] As a player, I want real fighters with clothing, hair and a silhouette I can recognise, so that the game looks like the dark fantasy it's meant to be.
44. [ ] As a player, I want to choose between at least two fighters (the Rogue and the Hunter), each able to wield any of the three weapons, so that fighter and weapon are separate choices.
45. [ ] As a player in a mirror match, I want the second fighter in a different colour scheme, so that I can tell us apart.
46. [ ] As a player, I want a toon look with ink outlines and a painted, ink-wash finish, so that the game has its own style.
47. [ ] As a player, I want the arena to float above a dark fantasy, ancient oriental landscape of mountains, buildings and water, so that the setting feels grand.
48. [ ] As a player, I want weapon trails (white for normal attacks, red for unblockables, gold for ultimates), sparks on clangs, a glowing aura when an ultimate is ready and a marker on a dropped weapon, so that the fight stays readable.
49. [ ] As a player, I want hit-stop, camera shake on heavy blows and slow motion on the final blow, so that big moments land.

### Sound

50. [ ] As a player, I want metal clangs on blocks, a distinct ringing clang on parries, slicing hits, bone-and-rock crunches for the Greatsword, whooshes on swings and dodges, footsteps and arena ambience, so that combat sounds physical.
51. [ ] As a player, I want menu music at 100–120 BPM, battle music at 130–150 BPM and a faster match-point version at 150–170 BPM, so that the music matches the design.
52. [ ] As a player, I want master, effects and music volume settings, so that I can balance the mix.

### Modes and controls

53. [ ] As a player, I want Training against a dummy whose behaviour I choose (idle, block, lights, heavies, thrust, sweep, slam, random, spar), with optional health refill and early/late parry feedback, so that I can practise.
54. [ ] As a player, I want Watch mode with a side-on cinematic camera, so that I can learn the moves by watching the computer duel.
55. [ ] As two players on one PC, I want Versus in a vertical split screen, each with our own camera and device (keyboard and mouse, the arrow-key layout, or a controller), so that we can play head to head.
56. [ ] As a player, I want to remap every action for keyboard, mouse and controller, save named profiles, and see PlayStation or Xbox button names, so that the controls suit me.
57. [ ] As a player, I want graphics presets, a reduce-flashes-and-shaking option and a button-hints option, so that the game runs and reads well for me.
58. [ ] As a player, I want a move list generated from the actual move data, so that it's always correct.

### Building and maintaining

59. [x] As the developer, I want the combat rules in plain GDScript with no graphics, stepped at a fixed 60 per second, so that they can be tested headlessly and later run online.
60. [x] As the developer, I want the rule tests to run from the command line and in CI, so that every change is checked.
61. [x] As the developer, I want the ported rules checked frame by frame against the original TypeScript rules on recorded inputs, so that I know the port is faithful before changing anything.
62. [x] As the developer, I want a soak run of computer-vs-computer matches that prints balance numbers, so that tuning rests on data.
63. [ ] As the developer, I want fighters, weapon models, sounds and music referenced by data, so that replacing an asset means replacing a file and one entry.
64. [ ] As the developer, I want a Windows build produced by CI and attached to GitHub releases, so that the game is easy to share.
65. [x] As the developer, I want to capture screenshots of any scene from the command line, so that visual changes can be reviewed without clicking through the game.

## Implementation Decisions

### Decisions in plain English

| Decision | What we chose | Why | What it costs |
|---|---|---|---|
| Engine and language | Godot 4.7.2 (standard build), typed GDScript | Already installed; the engine's own language, with the best docs and tooling; plenty fast for a two-fighter duel | No C#; if online play ever needs it, the rules can use integer math |
| Where the code lives | A Godot project in a `game/` folder of this repo, beside the web version until the Godot build matches it; then the web code is deleted (tag `v0.1-web-mvp` keeps it) | The web rules act as the reference while porting | The repo briefly holds both |
| Rules layer | Ported line for line to GDScript first, proven identical on recorded inputs, and only then changed | A faithful port gives a safety net; changes are then deliberate and tested | The port is done twice over: once faithful, then changed |
| What decides a hit | The weapon's path: each attack says where the weapon travels, frame by frame, and a hit lands only when the blade's sweep touches the opponent's body | "Hitboxes as tight as possible to the weapon"; what you see is what hits | Every move needs a path; ranges and arcs change a little, so tuning follows |
| How attacks are animated | The same weapon path moves the weapon on screen; the arms reach for the grip, and the torso and hips turn and lean with it | The free animation packs have no two-handed or weapon-specific attacks; one path for both hits and visuals keeps them in sync | Procedural animation is less expressive than hand-keyed animation; it can be replaced move by move with authored clips later |
| Movement animation | Walk, jog, sprint, idle, jump, flinch, knockdown and death clips from the Quaternius packs, with procedural strafing, backpedalling, leaning and dodge poses on top | The packs cover forward movement only | Strafing is an approximation until strafe clips are added |
| Fighters | Two of the eight to start: the Rogue (female Ranger outfit without the pauldrons, dark colours, hood, a cloth mask over the lower face, idling with her daggers in a reverse grip, though her attacks use a forward grip) and the Hunter (male Ranger outfit, dark brown with muted ochre, a tricorn hat and neck scarf instead of the hood, a scar). The mask, scarf and hat are built in code, since the packs have none. Any fighter can wield any weapon | They are the two fighters the free packs can dress convincingly; the tricorn is the Hunter's strongest Bloodborne cue and stops the two reading as the same hooded figure | The other six wait for their own bodies and outfits. Nothing flows yet: the packs have no capes or coats |
| Weapon models | Quaternius Medieval Weapons for the Greatsword (rebuilt at 1.72 m with a broader blade) and the Daggers, and a Katana built in code (curved single edge, round guard). Every blade has a dark body and a bright edge band, so it reads at any angle and at gameplay distance | The pack has no katana | Flat-colour weapons next to painted characters, softened by the shared toon shader |
| Look | Toon lighting in three bands, ink outlines, and an ink-wash finish (paper grain, soft edge darkening, muted palette with red accents) | The art direction in the design doc | Shader work up front |
| Camera | Over the right shoulder, about 4.6 m back, 1.3–1.4 m to the side (0.9 m hid the opponent in the spike) when the fighters stand 3.5 m apart or more, swinging further out by 0.8 m for each metre closer (about 3.5 m at the closest) so the player never hides the opponent; low enough that blades read against the sky, 60° field of view, always locked on; side-on for Watch | "Like For Honor, slightly more zoomed out"; in the playable skeleton a fixed 1.35 m hid the opponent's weapon side inside about 3 m | No free camera yet; up close the view turns partly side-on. Re-check the swing with the real fighters |
| Arena | The Moonlit Shrine rebuilt as a floating walled platform, radius 15 m (was 11.5), over a landscape of mountains, pagodas, waterfalls and water | "Larger", "suspended over a void", oriental backgrounds; walls keep the weapon-drop and knockback rules unchanged | Rounds may run longer; the soak run checks it |
| Fluid combat | Attacks keep half of your running speed instead of a third; lunges ease in and out; colossal swings end with a short slide; heavies can be dodge-cancelled late in recovery; light hitstun drops from 18 to 14 frames so later string hits can be blocked or parried | These are the rule causes of the stiffness; the last one replaces a combo breaker | Balance shifts; the soak run and tests re-tune it |
| Blocking walk speed | 60% of running speed (was 45%) | "Walk a bit faster while blocking" | Blocking slightly stronger |
| Parry | Same rules; new presentation: both weapons rebound from the contact point, with sparks, ring, clang and a brief camera push-in | "Cinematic, like Sekiro" | None to the rules |
| Sound | The best of the Sonniss bundle (clangs, swings, gore, ice cracks, wind, water, UI), trimmed and converted; generated sound for what it lacks (taiko, gong, parry ring layer, footsteps, bone crunch layers) | The bundle has no oriental percussion, parry ring or footsteps on stone | Generated sounds are simpler than recordings; they are easy to replace |
| Music | Placeholder tracks generated in code at 110 BPM (menus), 140 BPM (battle) and 160 BPM (match point), switching at the round call when either fighter has two wins | The bundle has no music; the design sets the tempos | Placeholder quality until real tracks are licensed |
| Controls | The demo's defaults and remapping, per player device, saved per profile on the PC | Same habits as the demo | Browser-saved profiles don't carry over |
| Tests and tools | GUT tests run headless; `npm test`, `npm run typecheck`, `npm run soak` and `npm run build` stay the entry points and call Godot | The commit gate in CLAUDE.md keeps working | Node stays installed as a task runner |
| Large files | Git without LFS; textures are scaled down to 2K or 1K and sounds converted to 16-bit before committing; raw Sonniss files are never committed | Keeps the repo simple; the Sonniss licence forbids redistributing its files as they come | A repo of roughly 100 MB |

### Architecture

**Two layers.** The rules layer knows nothing about graphics, input devices or sound: it is a set of plain GDScript classes (world, fighter, match, input tracker, computer brains and move data) advanced exactly 60 times per second. The presentation layer (nodes, animation, camera, effects, sound, menus) reads the rules layer's state and events and never changes them. A host node runs the fixed-step loop with an accumulator, applies slow motion by scaling the accumulator (not the engine's time scale), feeds each player's input, and gives the presentation an interpolation fraction, which it holds still during hit-stop.

**Faithful port first.** The TypeScript rules are ported module by module with the same names and numbers, including the known quirks (update order, last-write-wins hit-stop, JS rounding and the Mulberry32 generator). Two details make whole runs match bit for bit:
- the rules keep positions in their own 64-bit vector classes, because Godot's built-in vectors are 32-bit;
- `game/sim/js_math.gd` computes `sin`, `cos`, `atan2` and `hypot` exactly as V8 does (a port of its fdlibm), instead of using the platform's C library.

The port is proven by:

- the 47 existing rule tests, rewritten for GUT;
- golden replays: a Node script runs the TypeScript rules on 29 scripted duels and 6 computer-vs-computer matches and records every event and each fighter's state per frame; a GUT test feeds the same inputs to the Godot rules and compares them, within 1e-6 on positions (the margin covers Godot's JSON reader, not the rules) and exactly on events;
- the Godot computer opponent producing the recorded inputs for all six matches, and the 40-match soak printing the same numbers as the TypeScript soak.

The goldens guard the faithful port only. Once the rules change on purpose, they are replaced by tests of the new behaviour.

**Events.** The rules layer keeps emitting the demo's events (swing, telegraph, hit, block, parry, counter, disarm, and so on). The presentation, sound and HUD consume them, and tests assert on them.

**Move data.** Each weapon's moves stay a table of numbers in its own data file, as in the demo, with the same defaults applied at load. New fields:

- `swing`: the weapon path (see below);
- `side_start` and `side_end`: which side the weapon starts and ends on, used to check string continuity;
- `dodge_cancel_from` on heavies;
- `charge_move`: a charge the fighter can walk during (the Iai stance);
- `release_variant`: the move a charged or held attack turns into when released with the stick left or right (the horizontal Iai);
- `lunge_along_dodge`: a dodge attack that lunges in the dodge's direction instead of facing forward.

Chains stay as they are: each move names at most one light follow-up and one heavy follow-up, and pressing nothing ends the string.

**Weapon swings.** A swing is a short list of key poses in the fighter's own space, covering the whole move: wind-up during startup, strike during the active frames, follow-through during recovery. Each key holds:
- the grip position;
- the hand frame, from which the blade direction follows, within the wrist limits;
- the edge direction;
- the torso and pelvis coil.

Between keys, the grip travels on an arc around the fighter's body, not in a straight line, and the blade turns with the hands, not on its own.

The early spike (see the plan) proved this works on the Quaternius fighters and set the rules every swing must meet:
- wrist bend within about ±60° and deviation within ±25°;
- the blade never within 5 cm of the fighter's own body;
- a 2–4 frame cocked hold before the strike;
- elbows at 150–160° at contact, never locked;
- each move's end pose is a natural start for its follow-up;
- slash, overhead, thrust and sweep are told apart from the gameplay camera in the first third of the wind-up.

Swings are stored as sampled data, so a move can later take its path from an authored clip instead of hand keys, with the rules unchanged. Swings are built from a small set of named shapes (right-to-left slash, left-to-right slash, rising and falling diagonals, overhead, thrust, low sweep, spin, stab, plus a few specials) with per-move tweaks. Each weapon supplies its grip-to-tip length and blade thickness.

- The rules layer takes the blade segment at consecutive ticks and tests the swept quad between them against the defender's hurt capsule. The capsule is part of each fighter's rules data: 0.35 m in radius from the feet to 1.75 m for the first two fighters, raised with the fighter when they jump. The hit lands on the first tick the sweep touches the capsule inside the active frames, in the same outcome order as the demo (counters, jumped, flash, evade, parry, block, hit). Hit, block and parry events carry the contact point, where the sparks and the parry rebound start.
- Reach comes from arm extension and lunge (0.7–0.8 m on lights, with the front foot landing on the contact frame), so that the last 15–20 cm of the blade enters a defender standing 2.5 m away, the demo's duelling distance.
- Unblockables use a thicker blade for their longer reach.
- The counters (stomp, leap, evade), which the demo made deliberately generous, keep their generous cone checks, now measured from each move's path.
- Each move's reach and arc, which the computer opponent and the move list use, are computed from its path at load.
- Ultimate projectiles and scripted hits (the Moonsplitter wave, Impaler, Tempest) keep their own checks.

**Rule changes after the port** (each with tests, then a soak run):

- Arena radius 15 m, with the values the demo hard-coded to the old radius (Impaler dash limit, dropped-weapon bounce, camera limit) tied to it.
- Blocking walk speed 60% of run speed (was 45%).
- Attacks keep half of the current velocity (was 30%); lunges ease out; colossal swings add a short recovery slide in the swing's direction.
- Heavies accept a dodge cancel in the second half of their recovery.
- Light hitstun default 14 frames (was 18), so that from the second hit on a defender can block or parry. Strings are no longer guaranteed after the first hit.
- The new strings (next section).

**Presentation of fighters.**

- Each fighter is a scene built from the Quaternius base body (head only, cut from the full body at import), the outfit parts, hair, headwear built in code and palette, all on the shared 65-bone skeleton. Animations are retargeted through Godot's humanoid bone map.
- The two palettes differ over a large area seen from every side (the Rogue's second palette swaps dark for ash on the hood and sleeves), not just in trim. The outfit textures are baked with wear: ambient occlusion, dust up the boots and trouser hems, scuffed knees and cuffs, worn leather edges and grime; cloth and leather are matt. Faces get soot and shadowed eyes.
- Until the guard poses exist, each fighter has a stand-in hold per weapon: the clip it idles in, how the weapon sits in the fist and which wrists are set. The Rogue idles low with her daggers reversed along her forearms; the Hunter idles in a raised guard with the greatsword trailing from his hanging hand.
- An animation tree blends idle, walk, jog and sprint by speed. Unguarded strafing and backpedalling turn the hips and legs toward the direction of travel while the chest keeps facing the opponent, and the cycle runs backwards when retreating.
- Guard walking, where duels spend most of their time, is a procedural shuffle step instead: the lead foot moves first, the trailing foot closes, the feet never cross and the stance width holds. The stance is grounded, with knees over toes, the front foot toward the opponent and the rear foot turned out.
- A lean follows acceleration, and braces back when braking.
- Attacks, blocks, parries and guard stances are procedural upper-body layers: the weapon follows its swing, both arms reach for the grip with inverse kinematics (the left hand only on two-handed weapons), and the spine and hips turn toward the swing, with the hips leading so the motion ripples from hips to hands. The pelvis dips on impact.
- Weight comes from the presentation:
  - blade lag on a spring;
  - follow-through overshoot and settle;
  - a pelvis dip and camera kick on contact;
  - hit-stop holding both fighters still.
- Reactions are their own system, because weapon paths don't animate the defender:
  - flinch clips plus a recoil away from the hit direction;
  - block impacts;
  - knockdown and death clips;
  - dodge and backstep poses with a ghost trail;
  - the parried attacker's weapon bouncing back along its path.
- Dropped weapons are separate meshes.
- Swings are keyed in a small editor plugin that scrubs a move frame by frame on a fighter, so they can be tuned by eye rather than by editing numbers.

**Look.** One toon material for everything, with a three-band light ramp and a rim light, and inverted-hull ink outlines sized in screen pixels, which thin out only far away. Outlines are always on for fighters and weapons, and on props only on High. (Godot's built-in stencil outline was tried and not used: it draws the silhouette only, its width is fixed in metres, and it needs a StandardMaterial3D.) The shaders fetch a small generated noise texture instead of computing noise, which is much cheaper on integrated graphics. A full-screen ink-wash pass adds paper grain, edge darkening, colour grading and vignette. The graphics presets turn outline width, shadow size, particle counts and the post pass up or down. The sky, clouds, mountains, pagodas, waterfalls and water are built in code and shaders from simple shapes, so they can be swapped for bought art later.

**Sound.**

- An event-to-sound table (`game/audio/sound_bank.gd`) picks randomized variations and sends them to buses (Master > Music, Ambience, SFX > Combat, Foley and an Arena reverb; UI); impacts play in 3D.
- A Node script (`npm run audio:sonniss`) extracts the chosen Sonniss clips from the zips, trims, pitches and layers them, converts them to 16-bit mono at 44.1 kHz (the arena ambience is a stereo 60 s loop), and writes them into the project with a sources list (`game/assets/audio/SOURCES.md`).
- A second script (`npm run audio:synth`) generates the missing sounds, and a third (`npm run audio:music`) the placeholder music as seamless stereo loops whose tempos are listed in `game/assets/audio/music/tracks.json`.
- A music director (`game/audio/music_director.gd`) picks the menu, battle or match-point track; the switch to match point happens at the round call when either fighter has two wins. The loops start mid-signal (the tail of the last bar wraps into the first), so the player fades a track in and out over 10–20 ms whenever it starts, stops or switches one.
- The variations the sound bank picks between for one event are matched in loudness (their loudest 100 ms, with a peak ceiling), so no variation stands out.
- Only the processed files are committed, under 40 MB in all.

**Input.** Each player reads one device: keyboard and mouse, the arrow-key layout, controller 1 or controller 2. That player's profile maps the device to the demo's eight rule buttons plus pause. Profiles are saved in the user folder (`user://controls.cfg`). Controller button names follow the detected controller. One set of devices and profiles lives for the whole game in the `GameServices` autoload, which pauses a match when the window loses focus.

**Screens.**

- Title (with a live background duel), main menu, fighter and loadout select (per side: fighter, weapon, two block abilities, computer difficulty; devices and profiles in Versus), controls, settings, how to play and move list, pause, results, and the HUD.
- The UI uses an ink-wash theme with the demo's fonts (Zen Antique, Zen Kaku Gothic New; open font licence), bundled.

**Build and tools.** The npm scripts become a task runner (`scripts/godot.mjs`). It finds Godot through a `GODOT` environment variable, then `godot` or `godot4` on PATH, then an untracked `.godot-path` file holding the executable's path. Until the web code is deleted, `test` and `typecheck` run the web and Godot checks side by side, and the Godot soak, run and editor commands are `soak:godot`, `godot:run` and `godot:dev`. At the end the scripts are:

- `test`: GUT, headless.
- `typecheck`: loads every script and fails on any error.
- `soak`: headless computer-vs-computer matches with balance numbers.
- `build`: Windows export.
- `dev`: opens the editor.
- `shots`: renders chosen scenes to PNG in a window, and fails on any shader or script error.
- `check:sizes`: fails on any tracked file over 10 MB that isn't allow-listed, and prints the asset and repo sizes.

The exported game takes a `--smoke` flag: it plays a Watch match to the results and exits 0, or 1 on any error, stall or timeout.

CI installs Godot 4.7.2 and its export templates, checks the file sizes, runs tests and a short soak, and uploads the Windows build. CI has no GPU, so its build is exported headless without baked shaders and compiles them on first use; a build from `npm run build` on a PC has them baked. The Pages workflow is removed, and the Release workflow uploads a zipped Windows build.

### The new strings

"→" is a chain; every chain is optional. Frames are startup / active / recovery at 60 per second.

**Katana**

| Move | Input | Shape | Frames | Damage / posture | Notes |
|---|---|---|---|---|---|
| Right Cut | light | right-to-left slash | 11 / 3 / 16 | 6 / 7 | → Return Cut (light), → Heaven Splitter (heavy) |
| Return Cut | light, light | left-to-right slash | 10 / 3 / 16 | 6 / 7 | → Kesa Cut (light), → Rising Heaven (heavy): the L-L-H |
| Kesa Cut | 3rd light | right-shoulder-to-left-hip diagonal | 11 / 3 / 17 | 7 / 8 | → Crown Cut (light), → Heaven Splitter (heavy) |
| Crown Cut | 4th light | overhead | 14 / 4 / 22 | 8 / 10 | end of string |
| Iai Slash (vertical) | heavy (release) | sheathe, then vertical draw from above | 14 / 4 / 24 after release | 13 / 16 | Hold to stay sheathed and strafe at block speed; auto-release at 2.5 s as a power attack; reach about 3.6 m; → Rising Heaven (heavy) |
| Iai Slash (horizontal) | heavy released with left or right held | right-to-left draw | 14 / 4 / 24 after release | 13 / 16 | → Returning Draw (heavy), → Return Cut (light) |
| Rising Heaven | heavy follow-up | low-right to high-left rising diagonal | 16 / 4 / 24 | 12 / 15 | → Heaven Splitter (heavy) |
| Returning Draw | heavy after horizontal Iai | left-to-right heavy slash | 16 / 4 / 24 | 12 / 15 | end of string |
| Heaven Splitter | heavy follow-up | overhead | 22 / 4 / 28 | 15 / 18 | end of string |

The Katana's sprint, dodge, backstep and jump attacks, block abilities and ultimate are unchanged. While sheathed the fighter can't block; a dodge cancels the stance.

**Greatsword**

| Move | Input | Shape | Frames | Damage / posture | Notes |
|---|---|---|---|---|---|
| Heavy Swing | light | right-to-left slash, stepping into it | 14 / 4 / 22 | 9 / 11 | → Backswing (light), → Overhead Strike (heavy) |
| Backswing | light, light | left-to-right slash riding the momentum | 11 / 4 / 22 | 9 / 11 | faster start from momentum; → Overhead Strike (heavy): the L-L-H |
| Overhead Strike | heavy | overhead | 26 / 5 / 32 | 18 / 22 | chargeable; → Low Sweep (heavy) |
| Low Sweep | heavy, heavy | low sweep at the feet | 26 / 5 / 34 | 16 / 22 | unblockable, can be jumped (leap counter), narrower and faster than Reaping Sweep |
| Piercing Lunge | light out of a dodge | thrust | 12 / 3 / 20 | 8 / 10 | blockable stab |
| Skewer | heavy out of a dodge | thrust | 22 / 4 / 28 | 14 / 18 | unblockable thrust (stomp counter) |

Sprint, backstep and jump attacks, block abilities and the ultimate are unchanged. All swings end with a short slide in the swing's direction.

**Twin Daggers**

| Move | Input | Shape | Frames | Damage / posture | Notes |
|---|---|---|---|---|---|
| Quick Slice | light | right hand, right-to-left | 7 / 2 / 13 | 4 / 4 | dodge-cancel from the first recovery frame; → Off-hand Slice, → Twin Fang |
| Off-hand Slice | light, light | left hand, left-to-right | 7 / 2 / 13 | 4 / 4 | → Twin Rip, → Twin Fang: the L-L-H |
| Twin Rip | 3rd light | crossing cut, both hands | 9 / 3 / 14 | 6 / 5 | → Flurry Finisher |
| Flurry Finisher | 4th light | double stab | 11 / 3 / 18 | 7 / 6 | → Spinning Backhand (heavy) |
| Twin Fang | heavy | dashing double stab, 1.4 m lunge | 16 / 3 / 20 | 10 / 9 | chargeable; → Spinning Backhand (heavy); the old light chain that looped back to Quick Slice is removed |
| Spinning Backhand | heavy, heavy | spin | 18 / 5 / 22 | 12 / 10 | end of string |
| Passing Cut | light out of a dodge | slash, lunging along the dodge direction | 6 / 2 / 12 | 5 / 4 | replaces Ghost Cut |

Sprint, backstep and jump attacks, block abilities and the ultimate are unchanged.

## Testing Decisions

- A good test drives the rules only through their public surface, as the demo's tests do: build a world with two fighters, feed per-frame button and stick inputs, then assert on emitted events, HP, posture and state. Tests never reach into presentation code or private fields.
- **Rules (GUT, headless):**
  - the 47 ported tests;
  - golden replays against the TypeScript rules until the first deliberate rule change;
  - new tests for each rule change: arena radius and wall; block walk speed; momentum carry; eased lunges; heavy dodge-cancel; light hitstun letting a defender parry the second hit;
  - swing hit detection: a blade that passes behind or above the defender misses; a low sweep misses a jumping defender; an unblockable's longer blade hits at a range a normal attack misses; hits land on the frame the blade first touches the capsule;
  - every new move and chain: Katana four-light string, Iai vertical and horizontal by stick, Iai follow-ups, strafing while sheathed, sheathed auto-release, dodge cancelling the stance; Greatsword L-L-H, Low Sweep unblockable and jumpable, dodge thrusts; Daggers alternating string, dodge-cancel timing, no light loop from Twin Fang, Passing Cut direction;
  - string continuity: every chain's `side_end` matches the next move's `side_start`.
- **Content (GUT, headless):** every fighter scene assembles on the retargeted skeleton and the shared clips drive it; the body is cut down to the head and the headwear is in place; the two palettes differ from the front, the back and the side (rendered in software); every weapon has its markers and length; no held blade runs into its fighter's body; the art stays under 60 MB with no file over 10 MB and textures scaled down.
- **Input (GUT, headless):** a fake device stands in for the keyboard, mouse and controllers. Tests cover the bindings, profiles and saving, rebinding capture, button names, per-player seats and pause, and the feed into the rules.
- **Sound:**
  - Node tests check the processing tools and measure the processed files: sharp attacks, no DC offset, clean tails, and variations matched in loudness.
  - GUT tests check:
    - every event has a sound and every file loads;
    - the bus layout;
    - the music director switches at match point;
    - the tracks have the design tempos and loop for exactly their bars.
- **Host and camera (GUT, headless):** the fixed step, hit-stop and slow motion, pause and focus loss, the camera's distances, the HUD's timing, and the flow from title to results, all driven through `step()` without a window.
- **Soak:** 40 computer-vs-computer matches must finish without errors or impossible values (NaN, a fighter outside the arena, posture out of range). They report round length, parries, counters, disarms and ultimates per round, and each weapon's win rate. Target after tuning: rounds of 35–60 s, 0.3–0.6 disarms per round, each weapon winning 45–55% of its matches.
- **Presentation:** scripted screenshot scenes, rendered in a window from the command line:
  - a pose gallery of every attack at wind-up, contact and follow-through, for each weapon, on each fighter;
  - the arena from the gameplay camera and the Watch camera;
  - every menu screen;
  - Versus split screen;
  - the parry, disarm and ultimate moments.

  They are reviewed by eye for clipping, hands off the grip, weapons through bodies and unreadable effects. A smoke test loads every scene headless and fails on errors. Shaders compile only in a window, so a shader-check scene draws every shader and its `shots` run fails on any shader error.
- **Prior art:** the demo's tests (combat, match, regressions and ultimate suites) and their helpers (world builder, button and stick input helpers, event recorder, run loop) are ported first and reused for new tests.

## Out of Scope

- The other six weapons (Odachi, Giant Hammer, Staff, Sword & Shield, Bladed Whip, Scythe) and their ultimates.
- The other six fighters (Knight, Samurai, Orc, Aristocrat, Monk, Skeleton Knight), per-fighter bare-hand moves and per-fighter computer personalities.
- The character select screen of the design doc (model on the right, loadout on the left, lock-in, gate opening), the match intro with gates and fighter intros, and victory poses. The rebuild ships a simpler fighter and loadout select.
- Arenas other than the floating Moonlit Shrine, and stage select.
- Real music (placeholders only), voices and announcers.
- Online play, accounts, progression and cosmetics.
- A lock-on toggle or free camera.
- Ring-outs and the Hammer's wall slam.
- Mac and Linux builds.

## Further Notes

**Where this differs from `docs/design.md`:**

- Fighters are cosmetic in this build. There are two of eight, and they share the bare-hand moveset.
- Music is placeholder.

**Where this differs from `docs/mvp-spec.md`, which stays the record of the web demo:**

- engine, platform, controls storage and build;
- hit detection by weapon path instead of a range-and-arc cone;
- arena radius 15 m;
- block walk speed 60%;
- light hitstun 14 frames;
- momentum and cancel changes;
- the Katana, Greatsword and Daggers strings above;
- music tempos (the demo used 84 and 138 BPM).

The demo spec's block-posture figures (60, 50 and 70%) and speed figures don't match its own code (70, 60 and 80%; 0.9 and 1.12); the Godot port follows the code, and the demo spec's tables are corrected on this branch.

**Risks, and how they're handled:**

- Procedural attack animation may not look good enough. An early animation spike on one fighter and the Katana is judged from screenshots before all moves are built. Authored clips can replace any move later, because the swing path stays the hit authority.
- Swing-based hits change balance. Handled by soak runs after the change, with ranges tuned per move.
- The body and outfit rest poses differ slightly, which risks clipping. Handled by cutting the body down to the head and checking screenshots.
- Asset licences:
  - Quaternius is CC0.
  - The Sonniss bundle allows use in the game but not redistribution of its raw files or any AI training; only processed files are committed, and their sources are listed.
  - The fonts are under the SIL Open Font License.
