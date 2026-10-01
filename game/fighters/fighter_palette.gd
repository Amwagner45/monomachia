class_name FighterPalette
extends Resource
## One colour scheme of a fighter. Every fighter has two, so that a mirror
## match can dress the second fighter differently.
##
## The outfit is recoloured from the Ranger outfit's T_Ranger_3 texture by
## tools/bake_palettes.gd, which splits it into four regions by colour:
## - cloth: the cream shirt, sleeves and trousers;
## - trim: the ochre quilting and padding;
## - leather: the brown hood, vest, belts and boots;
## - metal: the buckles, studs and pauldron plates.
## Cloth and trim take a new colour, keeping the painted shading; leather and
## metal are tinted. The baked result is `outfit_albedo`.

@export var display_name: String = ""
## Colour the cloth takes, as it should look where the source is a mid tone.
@export var cloth_color: Color = Color(0.5, 0.5, 0.5)
## Colour the trim takes.
@export var trim_color: Color = Color(0.5, 0.5, 0.5)
## Multiplies the leather; below 1 darkens it.
@export var leather_tint: Color = Color.WHITE
## 0 turns the leather grey, 1 keeps its saturation.
@export_range(0.0, 1.5) var leather_saturation: float = 1.0
## Multiplies the metal.
@export var metal_tint: Color = Color.WHITE
## Multiplies the hair and eyebrows (the hair textures are near white).
@export var hair_color: Color = Color.WHITE
## The baked outfit base colour (written by tools/bake_palettes.gd).
@export var outfit_albedo: Texture2D
