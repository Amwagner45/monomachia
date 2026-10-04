---
tags: [project]
---

# Godot rebuild

The original Monomachia was a browser demo in three.js and TypeScript (see [[MVP spec]]). The design update of Sep 30, 2026 moved the game to Godot for PC: eight fighters, per-weapon movesets, floating arenas, character select, match intros and music ([[Design doc]]). The rebuild's first destination is parity with the demo on the new foundation; the rest of the design update comes later.

## The plan

The [[Rebuild plan]] lives on `feature/godot-rebuild`, and every lane's work merges into that branch through pull requests. Its phases:

- **A. Foundation and a [[Faithful port]]:** the Godot project, the rules ported bit for bit, and golden replays.
- **B. A playable skeleton:** a match you can play in Godot.
- **C. The rule changes:** [[Weapon swings]] decide hits, the fluid rules, and the new strings.
- **D. Fighters and animation:** the Rogue and the Hunter, retargeted clips, inverse kinematics and procedural steps ([[Fighter animation]]).
- **E. Look, arena and effects:** the toon and ink-wash look, the [[Moonlit Shrine]], combat effects ([[Art direction]]).
- **F. Sound and music:** see [[Sound and music]].
- **G. Screens and modes:** menus, the fighter select, Training, Watch, Versus and the HUD ([[HUD and menus]], [[Game modes]]).
- **H. Ship:** the Windows build and release.

The build order runs these as 14 stages; each stage note shows how many of its tasks are done, live from the plan. Start at [[Stage 1 - Resume and safety nets]], or see the list in [[Rebuild plan]].

The choices behind all this: [[Key decisions]]. How the work is organised: [[Workflow]] and [[Lanes and the board]].

**Sources:** [[Rebuild spec]] · [[Rebuild spec - Problem Statement]] · [[Rebuild plan - Destination]] · [[Rebuild plan - Progress]]
