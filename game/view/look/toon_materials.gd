class_name ToonMaterials
extends RefCounted
## Makes the shared toon material and its ink outline, for fighters, weapons
## and props alike. Every material remembers its outline pass and its outline
## kind (metadata), so the graphics presets can switch outlines per kind.
##
## Outline choice (see docs/specs/godot-rebuild.md, "Look"):
## - Fighters and weapons: inverted hull (outline.gdshader). It draws inner
##   contours (an arm across the torso, a blade over the body), keeps a
##   constant on-screen width at any camera distance, takes the material's own
##   ink colour, and works with the custom toon shader. Always on.
## - Props: the same hull, with smoothed normals baked by MeshKit, on High
##   only. It gives architecture a heavier silhouette stroke over the ink-wash
##   pass's thin crease lines. On Medium and Low the ink-wash pass (or nothing)
##   draws prop lines, which costs no extra geometry pass.
## - The built-in STENCIL_MODE_OUTLINE was evaluated and not used for
##   outlines: it draws the silhouette only (no inner lines), its thickness is
##   fixed in metres (thin far away, fat up close), it needs a
##   StandardMaterial3D rather than this shader, and a stencil read forces the
##   pass into the transparent queue. Its sibling STENCIL_MODE_XRAY is the
##   right tool later for showing a fighter hidden behind a pillar.

## What an outline is drawn for: each kind has its own width, and the
## graphics presets switch kinds on and off.
enum OutlineKind { NONE, FIGHTER, WEAPON, PROP }

const TOON_SHADER: Shader = preload("res://shaders/toon.gdshader")
const OUTLINE_SHADER: Shader = preload("res://shaders/outline.gdshader")

const META_OUTLINE: StringName = &"look_outline"
const META_KIND: StringName = &"look_outline_kind"

## Outline width in pixels at 1080p, per kind.
const OUTLINE_WIDTH: Dictionary[OutlineKind, float] = {
	OutlineKind.FIGHTER: 4.0,
	OutlineKind.WEAPON: 3.2,
	OutlineKind.PROP: 3.0,
}


## A toon material with base colour color. params are shader parameters to
## set (for example {&"rim_strength": 0.8}). ink is the outline and wash colour.
static func make(color: Color, kind: OutlineKind = OutlineKind.PROP, params: Dictionary = {},
		ink: Color = LookPalette.INK) -> ShaderMaterial:
	return make_with_shader(TOON_SHADER, kind, params.merged({&"base_color": color}), ink)


## Like make(), for another shader that includes toon_light.gdshaderinc (the
## stone floor, rock).
static func make_with_shader(shader: Shader, kind: OutlineKind, params: Dictionary = {},
		ink: Color = LookPalette.INK) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter(&"ink_color", ink)
	LookNoise.apply_to(m)
	for key: Variant in params:
		m.set_shader_parameter(key, params[key])
	m.set_meta(META_KIND, kind)
	if kind != OutlineKind.NONE:
		var outline: ShaderMaterial = make_outline(ink, OUTLINE_WIDTH[kind])
		m.set_meta(META_OUTLINE, outline)
		m.next_pass = outline
	return m


## A fighter's cloth or skin: strong rim, a little fresnel glow, less brush
## noise (clean reads beat painterly ones on the fighters).
static func fighter(color: Color, ink: Color = LookPalette.INK) -> ShaderMaterial:
	return make(color, OutlineKind.FIGHTER, {
		&"rim_strength": 0.9,
		&"rim_width": 0.32,
		&"rim_emission": 0.22,
		&"brush_noise": 0.05,
		&"shadow_fill": 0.16,
	}, ink)


## A weapon: hard toon highlight for steel, thinner outline.
static func weapon(color: Color, metal: bool = true) -> ShaderMaterial:
	var params: Dictionary = {&"rim_strength": 0.8, &"rim_width": 0.3, &"brush_noise": 0.0}
	if metal:
		params[&"specular_strength"] = 1.6
		params[&"specular_size"] = 0.06
	return make(color, OutlineKind.WEAPON, params)


## A prop: painterly wash stains and no rim (a floor seen at a grazing angle
## would glow), outlined as a PROP, or not at all for distant scenery.
static func prop(color: Color, wash: float = 0.35, outlined: bool = true, ink: Color = LookPalette.INK) -> ShaderMaterial:
	return make(color, OutlineKind.PROP if outlined else OutlineKind.NONE, {
		&"wash_amount": wash,
		&"rim_strength": 0.0,
		&"use_vertex_color": true,
	}, ink)


## An ink outline pass on its own.
static func make_outline(ink: Color, width_px: float) -> ShaderMaterial:
	var o := ShaderMaterial.new()
	o.shader = OUTLINE_SHADER
	o.set_shader_parameter(&"ink_color", ink)
	o.set_shader_parameter(&"width_px", width_px)
	return o


## The outline kind a material was made with (NONE for any other material).
static func outline_kind_of(material: Material) -> OutlineKind:
	if material == null or not material.has_meta(META_KIND):
		return OutlineKind.NONE
	return material.get_meta(META_KIND) as OutlineKind


## Turns a material's outline pass on or off, at width_scale times its kind's
## width. A material made without an outline is left alone.
static func set_outline(material: Material, enabled: bool, width_scale: float = 1.0) -> void:
	if material == null or not material.has_meta(META_OUTLINE):
		return
	var outline: ShaderMaterial = material.get_meta(META_OUTLINE)
	outline.set_shader_parameter(&"width_px", OUTLINE_WIDTH[outline_kind_of(material)] * width_scale)
	material.next_pass = outline if enabled else null


## True while a material's outline pass is switched on.
static func is_outlined(material: Material) -> bool:
	return material != null and material.has_meta(META_OUTLINE) and material.next_pass == material.get_meta(META_OUTLINE)
