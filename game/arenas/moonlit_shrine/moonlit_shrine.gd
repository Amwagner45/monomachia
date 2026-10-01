class_name MoonlitShrine
extends Node3D
## The Moonlit Shrine arena: a walled stone courtyard floating above a sea of
## clouds under a blood-red moon. Everything is built from code and shaders
## when the scene enters the tree, from two data files: the ArenaDef (def:
## walls, spawns, gates, camera limits, ambience) and the ShrineLayout
## (layout: where every piece goes).
##
## Like every arena it brings its own environment, lights and the ink-wash
## pass, and applies the chosen graphics preset to itself when it loads; the
## match brings the camera and the fighters. It flickers its lantern lights.
##
## Seams for the match (see ArenaScenes): `def`, from which the camera takes
## its limits; Marker3D children Spawn0, Spawn1 (where the rules start each
## side) and Gate0, Gate1 (the gate anchors); and Platform/GateRope0 and
## GateRope1 (each gate's rope barrier, for the match intro to drop).
##
## Built so far: the courtyard (17.3) and its props (17.4). The underside,
## the sky, the backdrop and the embers and ash come with tasks 17.5 to 17.8.

## The environment until the arena's own sky (task 17.6) sets def.environment.
const NIGHT_ENVIRONMENT: Environment = preload("res://view/look/ink_night_environment.tres")

@export var def: ArenaDef
@export var layout: ShrineLayout

var _lantern_lights: Array[OmniLight3D] = []
var _time: float = 0.0


func _ready() -> void:
	_build()
	GraphicsApplier.apply_to_tree(GameServices.graphics_preset(), self)


func _process(delta: float) -> void:
	_time += delta
	for i: int in _lantern_lights.size():
		_lantern_lights[i].light_energy = ShrinePlatform.LANTERN_ENERGY * _flicker(_time, i)


## Lantern i's brightness at time t, around 1: three waves at odd rates,
## offset per lantern so they don't flicker together.
static func _flicker(t: float, i: int) -> float:
	return 1.0 + 0.08 * sin(t * 9.0 + i * 1.7) + 0.06 * sin(t * 23.0 + i * 4.1) + 0.035 * sin(t * 3.1 + i)


func _build() -> void:
	assert(def != null and layout != null, "MoonlitShrine needs def and layout")
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	# Each arena gets its own copy, so a preset can change its fog.
	var source: Environment = def.environment if def.environment != null else NIGHT_ENVIRONMENT
	env.environment = source.duplicate(true) as Environment
	add_child(env)
	add_child(_build_lights())
	add_child(ShrinePlatform.build(layout, def))
	for light: Node in get_node(^"Platform/LanternLights").get_children():
		_lantern_lights.append(light as OmniLight3D)
	_add_markers()
	var ink := InkWashPass.new()
	ink.name = "InkWash"
	add_child(ink)


## Marker3D seams: Spawn0, Spawn1 and Gate0, Gate1 from the ArenaDef.
func _add_markers() -> void:
	for side: int in def.spawn_points.size():
		_add_marker("Spawn%d" % side, def.spawn_point(side))
	for side: int in def.gate_anchors.size():
		_add_marker("Gate%d" % side, def.gate_anchor(side))


func _add_marker(marker_name: String, xform: Transform3D) -> void:
	var m := Marker3D.new()
	m.name = marker_name
	m.transform = xform
	add_child(m)


## The moon's key light (cold, casting the shadows the preset sets), and a red
## rim light from the moon's side that touches fighters only.
func _build_lights() -> Node3D:
	var root := Node3D.new()
	root.name = "Lights"
	var key := DirectionalLight3D.new()
	key.name = "MoonKey"
	key.light_color = Color(0.74, 0.82, 1.0)
	key.light_energy = 1.35
	key.shadow_enabled = true
	key.shadow_bias = 0.04
	key.shadow_normal_bias = 1.2
	key.shadow_blur = 1.0
	key.directional_shadow_split_1 = 0.22
	key.directional_shadow_blend_splits = true
	key.directional_shadow_fade_start = 0.85
	key.light_angular_distance = 0.0
	key.add_to_group(GraphicsApplier.GROUP_SHADOW_LIGHT)
	key.basis = _shining_from(layout.key_light_direction)
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.name = "MoonRim"
	rim.light_color = Color(1.0, 0.36, 0.28)
	rim.light_energy = 1.1
	rim.shadow_enabled = false
	rim.light_cull_mask = LookPalette.FIGHTER_LAYER
	# Light only: the sky (task 17.6) draws one moon, from the layout.
	rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	rim.basis = _shining_from(layout.moon_direction)
	root.add_child(rim)
	return root


## A light's basis shining from from_dir: its -Z points away from it.
static func _shining_from(from_dir: Vector3) -> Basis:
	var d: Vector3 = -from_dir.normalized()
	var up: Vector3 = Vector3.UP if absf(d.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	return Basis.looking_at(d, up)
