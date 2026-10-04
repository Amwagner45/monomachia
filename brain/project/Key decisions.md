---
tags: [project, decisions]
---

# Key decisions

The choices that shape the rebuild, in short. The full tables, with the reasons and costs, are in [[Rebuild spec - Implementation Decisions]] and [[Rebuild plan - Decisions so far]]; the demo's are in [[MVP spec - Decisions in plain English]] and [[MVP spec - Gaps in the design doc]].

| Question | Choice |
|---|---|
| Engine | Godot 4.7.2 with typed GDScript; Node stays as the task runner |
| Where the code lives | `game/` beside the web demo until parity, then the web code goes (tag `v0.1-web-mvp` keeps it) |
| How to port | Line for line first, proven identical, and only then changed ([[Faithful port]]) |
| What decides a hit | The weapon's real path ([[Weapon swings]]) |
| How attacks animate | The same path moves the weapon; the arms follow by inverse kinematics ([[Fighter animation]]) |
| First fighters | The Rogue and the Hunter, the two the free packs can dress ([[Roster]]) |
| Arena | The [[Moonlit Shrine]], floating and walled, radius 15 m |
| Fluid combat | Half the run speed kept into attacks, eased lunges, colossal slides, late dodge cancels, 14-frame light hitstun instead of a combo breaker ([[Attacking]]) |
| Blocking walk | 60% of run speed (was 45%) |
| Parry | Same rules, cinematic presentation ([[Defending]]) |
| Look | Toon, ink outlines, ink-wash finish ([[Art direction]]) |
| Sound | The Sonniss bundle plus generated sound; placeholder music at 110/140/160 BPM ([[Sound and music]]) |
| Not in the game | Directional guard and combo breakers |
| Large files | Plain git, no LFS; textures scaled down, raw Sonniss files never committed |

When a change contradicts the design doc or a spec, the doc is updated in the same branch ([[Workflow]]).
