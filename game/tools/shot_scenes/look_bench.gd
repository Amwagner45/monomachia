extends Node3D
## The look bench: toon fighters, blades and a stone lantern under a moon key
## light, for judging the toon bands, the rim light and the ink outlines by
## eye. Outlines are on in the left half and off in the right. Each half has a
## group at a duel's distance from the camera and another FAR metres further
## back, to show how the line width holds up far away. Render with
##   node scripts/godot.mjs shots res://tools/shot_scenes/look_bench.tscn <out.png> 20 [--width-scale=0.75]
## where --width-scale multiplies every outline width, for comparing widths.

## How far behind the near groups the far ones stand.
const FAR: float = 14.0
## Half the distance between the left and right groups.
const HALF_GAP: float = 2.4
## The game camera's field of view, and about where it sits behind a fighter
## looking at an opponent 6 m away.
const CAMERA_FOV: float = 60.0
const CAMERA_POSITION: Vector3 = Vector3(0, 1.9, 6.0)
const CAMERA_TARGET: Vector3 = Vector3(0, 1.2, -2.0)


func shot_frames() -> int:
	return 20


func _ready() -> void:
	_add_environment()
	var floor_kit := MeshKit.new()
	floor_kit.disc(Transform3D.IDENTITY, 40.0, 48, 4)
	add_child(MeshKit.instance(floor_kit.commit(), ToonMaterials.prop(LookPalette.STONE_DARK, 0.35, false), false))
	var width_scale: float = _width_scale()
	for outlined: bool in [true, false]:
		var x: float = -HALF_GAP if outlined else HALF_GAP
		var materials: Array[ShaderMaterial] = []
		materials.append_array(_add_group(Vector3(x, 0, 0), FighterStandin.PALETTES[0]))
		materials.append_array(_add_group(Vector3(x * 0.6, 0, -FAR), FighterStandin.PALETTES[1]))
		for m: ShaderMaterial in materials:
			ToonMaterials.set_outline(m, outlined, width_scale)
		var label := Label3D.new()
		label.text = "outlines on (x%.2f)" % width_scale if outlined else "outlines off"
		label.font_size = 40
		label.pixel_size = 0.005
		label.modulate = LookPalette.BONE
		label.position = Vector3(x, 2.45, 0)
		add_child(label)
	var camera := Camera3D.new()
	camera.fov = CAMERA_FOV
	camera.position = CAMERA_POSITION
	add_child(camera)
	camera.look_at(CAMERA_TARGET)
	camera.make_current()


## The --width-scale=<x> argument, or 1.
static func _width_scale() -> float:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--width-scale="):
			return arg.trim_prefix("--width-scale=").to_float()
	return 1.0


## A night like the arena's: a dark sky colour, cold ambient light and a moon
## key light from the right that casts shadows.
func _add_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.05, 0.075)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.42, 0.6)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.74, 0.82, 1.0)
	moon.light_energy = 1.35
	moon.shadow_enabled = true
	add_child(moon)
	moon.look_at_from_position(Vector3.ZERO, Vector3(-0.95, -1.05, -0.25), Vector3.UP)


## A fighter (a body capsule and a head) holding a blade across its body, so
## the outline shows inner contours, and a stone lantern beside it. Returns
## the group's materials.
func _add_group(at: Vector3, color: Color) -> Array[ShaderMaterial]:
	var group := Node3D.new()
	group.position = at
	add_child(group)
	var cloth: ShaderMaterial = ToonMaterials.fighter(color)
	var skin: ShaderMaterial = ToonMaterials.fighter(FighterStandin.TONES[&"rogue"])
	var steel: ShaderMaterial = ToonMaterials.weapon(LookPalette.STEEL)
	var wood: ShaderMaterial = ToonMaterials.weapon(LookPalette.WOOD_DARK, false)
	var stone: ShaderMaterial = ToonMaterials.prop(LookPalette.STONE)

	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = 1.5
	body.mesh = capsule
	body.material_override = cloth
	body.position = Vector3(-0.5, 0.75, 0)
	group.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.17
	sphere.height = 0.34
	head.mesh = sphere
	head.material_override = skin
	head.position = Vector3(-0.5, 1.66, 0)
	group.add_child(head)

	# The blade crosses the body from the right hip to above the left shoulder.
	var grip := Transform3D(Basis(Vector3.FORWARD, 0.7), Vector3(-0.3, 0.85, 0.36))
	var blade := MeshKit.new()
	blade.box(grip * Transform3D(Basis(), Vector3(0, 0.6, 0)), Vector3(0.05, 0.95, 0.012))
	group.add_child(MeshKit.instance(blade.commit(true), steel))
	var hilt := MeshKit.new()
	hilt.box(grip, Vector3(0.04, 0.26, 0.04))
	group.add_child(MeshKit.instance(hilt.commit(true), wood))

	var kits := MeshKitSet.new()
	var lantern: MeshKit = kits.kit(&"stone")
	var base := Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.65, 0, -0.2))
	lantern.box(base * Transform3D(Basis(), Vector3(0, 0.1, 0)), Vector3(0.7, 0.2, 0.7))
	lantern.cylinder(base * Transform3D(Basis(), Vector3(0, 0.2, 0)), 0.14, 0.11, 0.7, 10)
	lantern.box(base * Transform3D(Basis(), Vector3(0, 0.95, 0)), Vector3(0.5, 0.1, 0.5))
	lantern.box(base * Transform3D(Basis(), Vector3(0, 1.15, 0)), Vector3(0.36, 0.3, 0.36))
	lantern.roof(base * Transform3D(Basis(), Vector3(0, 1.33, 0)), 0.42, 0.42, 0.3, 0.12, 4, 0.06)
	kits.finish(group, {&"stone": stone}, [&"stone"])
	return [cloth, skin, steel, wood, stone]
