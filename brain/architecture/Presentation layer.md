---
tags: [architecture]
---

# Presentation layer

Everything the player sees and hears. It reads the [[Rules layer]]'s state and events each frame and never changes them, so the rules stay testable without graphics.

- **Fighters** ([[game.view.fighter]]): models, palettes, [[Fighter animation]] and the weapon held by inverse kinematics.
- **The look** ([[game.view.look]]): the toon and ink-wash shaders. See [[Art direction]].
- **The match** ([[game.view.match]]): the match scene, the [[Camera]] rig, effects (sparks, flashes, trails, the 危 mark) and the swing debug view (F3 in a debug build).
- **The arena** ([[game.arenas.moonlit_shrine]]): the [[Moonlit Shrine]].
- **UI** ([[game.ui.hud]], [[game.ui.menus]], [[game.ui.theme]]): see [[HUD and menus]].
- **Audio** ([[game.audio]]): see [[Sound and music]].

Animations and effects run on the rules' clock, so they hold still in hit-stop and pause. Between rules ticks the host's interpolation fraction smooths movement.

**Sources:** [[Rebuild spec - Implementation Decisions]] · see [[Architecture]]
