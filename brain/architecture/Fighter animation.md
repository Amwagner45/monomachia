---
tags: [architecture, presentation]
---

# Fighter animation

- **Bodies:** each fighter is a scene built from the Quaternius base body, outfit parts, hair, headwear built in code and a palette, all on a shared 65-bone skeleton. Animations are retargeted through Godot's humanoid bone map.
- **Movement:** walk, jog, sprint, idle, jump, flinch, knockdown and death clips from the packs, blended by speed on one shared step phase so the feet stay planted. Strafing and backpedalling turn the hips toward the direction of travel while the chest keeps facing the opponent.
- **Guard walking**, where duels spend most of their time, is a procedural shuffle: the lead foot moves first, the trailing foot closes, and the feet never cross.
- **Lean:** follows acceleration, up to 11°: forward when setting off, into turns, and back when braking.
- **Weapons:** a weapon is never fixed to a hand. It's posed in the fighter's space by its [[Weapon swings|swing]], and the arms reach for it with inverse kinematics; each fist curls round its own handle.
- **Attacks:** the swing that decides hits also moves the weapon on screen, with the torso and hips coiling and the feet stepping with the lunge. The free packs have no weapon attacks, and one path for hits and visuals keeps them in sync.

Procedural animation is less expressive than hand-keyed clips, so the authored-animation plan ([[Plan - Authored animation and the dodge roll]]) is replacing moves, reactions, knockdowns and KOs with authored clips while keeping the rules unchanged. It retired the rebuild plan's task 15 (full fighter animation) and 14b (the swing editor). Clips play on the rules' clock and hold still in hit-stop.

Plan: [[Task 13]], [[Task 14]] · [[Stage 8 - Fighter animation core]] · [[Stage 13 - Full animation]]

**Sources:** [[Rebuild spec - Implementation Decisions]] · [[Rebuild plan notes 13-15-fighters-and-animation]] · [[Animation spike (Sep 30, 2026)]] · code in [[game.view.fighter]] · see [[Roster]]
