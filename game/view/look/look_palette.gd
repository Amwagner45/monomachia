class_name LookPalette
extends RefCounted
## The look's muted colours (ink blacks, bone and paper whites, stone greys,
## lacquer red) and the render layers the look relies on. Colours are sRGB,
## as picked; shader uniforms marked source_color convert them. The fighters'
## palettes (FighterPalette, and FighterStandin's for the stand-ins) are the
## only saturated colours near the fighting area, so the fighters pop from the
## arena.

const INK: Color = Color("0e0e14")
const INK_SOFT: Color = Color("1c1c26")
const BONE: Color = Color("d6ccb8")
const PAPER: Color = Color("e8e0cc")
const LACQUER: Color = Color("6a1a15")
const STONE_LIGHT: Color = Color("76736f")
const STONE: Color = Color("5c5a61")
const STONE_DARK: Color = Color("3c3b44")
const WOOD_DARK: Color = Color("2a201c")
const ROPE: Color = Color("b3a078")
const PINE: Color = Color("1e2b28")
const STEEL: Color = Color("b8bec8")

## Render layer bit for fighters and their weapons (layer 2). Lights whose
## cull mask is only this layer (the arena's moon rim light) touch fighters
## and nothing else.
const FIGHTER_LAYER: int = 2
## Render layer bit for large ground surfaces (layer 4): the courtyard floor
## and the rock ledge. Small warm lights (lanterns) leave this layer out of
## their cull mask: their pools on the ground were barely visible and cost
## about 0.4 ms per frame on the target laptop.
const GROUND_LAYER: int = 8
## Cull mask for small lights: every layer but the ground.
const SMALL_LIGHT_MASK: int = 0xFFFFF & ~GROUND_LAYER
