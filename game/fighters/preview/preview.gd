extends Node3D
## A stage for looking at the fighters and weapons, and for screenshotting
## them. Run it from the editor, or through the screenshot command:
##
##   node scripts/godot.mjs shots res://fighters/preview/preview.tscn <out.png> [frames] [--option=value...]
##
## Modes (--mode=):
## - lineup (default): both fighters idle with their signature weapons, and
##   the three weapons standing beside them with their markers;
## - turntable: the lineup, slowly turning;
## - fighter: one fighter, chosen with --fighter=rogue|hunter, --palette=0|1,
##   --weapon=katana|greatsword|daggers|none (default: signature),
##   --view=front|three_quarter|side|back|head and --range=close|gameplay;
## - weapons: the weapons upright on a 10 cm grid, with their markers;
## - sheet: renders the whole review set (both fighters in both palettes from
##   the front and three-quarters, close and at gameplay distance; head
##   close-ups; rest poses; every fighter with every weapon; the weapons) into
##   contact sheets in the folder given by --sheet=<folder>.
##
## Markers: green is BladeBase, red BladeTip, blue OffHandGrip, yellow the
## weapon origin (the main hand's grip).

enum Mode { LINEUP, TURNTABLE, FIGHTER, WEAPONS, SHEET }

const VIEWS: Dictionary[StringName, float] = {
	&"front": 0.0, &"three_quarter": -38.0, &"side": -90.0, &"back": 180.0,
}
const MARKER_COLORS: Dictionary[StringName, Color] = {
	&"BladeBase": Color(0.2, 0.9, 0.3), &"BladeTip": Color(0.95, 0.2, 0.15), &"OffHandGrip": Color(0.25, 0.45, 1.0),
}
## Frames to let a new setup settle before a capture.
const SETTLE_FRAMES: int = 6
## Where the idle clips are frozen for screenshots, so every run matches.
const POSE_TIME: float = 0.5

@export var mode: Mode = Mode.LINEUP
@export var fighter_id: StringName = &"rogue"
@export_range(0, 1) var palette: int = 0
## Empty for the fighter's signature weapon; "none" for bare hands.
@export var weapon_id: StringName = &""
@export var view: StringName = &"front"
@export var gameplay_range: bool = false
## Turntable speed in radians per second.
@export var turntable_speed: float = 0.6

var _camera: Camera3D
var _label: Label
var _actors: Node3D
var _sheet_dir: String = ""
var _done: bool = false


func _ready() -> void:
	_read_args()
	_build_stage()
	_actors = Node3D.new()
	_actors.name = &"Actors"
	add_child(_actors)
	match mode:
		Mode.LINEUP, Mode.TURNTABLE:
			_setup_lineup()
		Mode.FIGHTER:
			_setup_fighter(fighter_id, palette, weapon_id, view, gameplay_range)
		Mode.WEAPONS:
			_setup_weapons()
		Mode.SHEET:
			_setup_lineup()
			_run_sheet.call_deferred()
	if mode != Mode.SHEET:
		_done = true


func _process(delta: float) -> void:
	if mode == Mode.TURNTABLE:
		for child: Node in _actors.get_children():
			if child is FighterModel:
				(child as FighterModel).rotate_y(turntable_speed * delta)


## For tools/shot.gd: frames to wait before asking shot_ready().
func shot_frames() -> int:
	return 1 if mode == Mode.SHEET else 20


## For tools/shot.gd: true once the scene has finished posing itself.
func shot_ready() -> bool:
	return _done


func _read_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		if not a.begins_with("--") or not a.contains("="):
			continue
		var key: String = a.substr(2, a.find("=") - 2)
		var value: String = a.substr(a.find("=") + 1)
		match key:
			"mode":
				mode = Mode.get(value.to_upper(), mode) as Mode
			"fighter":
				fighter_id = StringName(value)
			"palette":
				palette = int(value)
			"weapon":
				weapon_id = StringName(value)
			"view":
				view = StringName(value)
			"range":
				gameplay_range = value == "gameplay"
			"sheet":
				_sheet_dir = value


# --- stage -------------------------------------------------------------------

func _build_stage() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.3, 0.32, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.7)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40.0, -30.0, 0.0)
	key.light_energy = 1.5
	key.shadow_enabled = true
	add_child(key)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, 160.0, 0.0)
	fill.light_energy = 0.45
	fill.light_color = Color(0.75, 0.82, 1.0)
	add_child(fill)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	floor_mesh.mesh = plane
	var floor_mat: StandardMaterial3D = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.4, 0.4, 0.41)
	floor_mat.roughness = 0.95
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)
	var grid: PackedVector3Array = PackedVector3Array()
	for i: int in range(-10, 11):
		grid.append_array([Vector3(i, 0.002, -10), Vector3(i, 0.002, 10), Vector3(-10, 0.002, i), Vector3(10, 0.002, i)])
	add_child(_lines(grid, Color(0.3, 0.3, 0.31)))
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	# Bottom centre, so it survives the portrait crops of the contact sheets.
	_label = Label.new()
	_label.position = Vector2(505.0, 790.0)
	_label.size = Vector2(590.0, 100.0)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_label)


func _look_from(pos: Vector3, target: Vector3, fov: float) -> void:
	_camera.fov = fov
	_camera.position = pos
	_camera.look_at(target, Vector3.UP)


## Unshaded line segments (pairs of points).
static func _lines(points: PackedVector3Array, color: Color) -> MeshInstance3D:
	var mesh: ImmediateMesh = ImmediateMesh.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for p: Vector3 in points:
		mesh.surface_add_vertex(p)
	mesh.surface_end()
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _dot(color: Color, radius: float) -> MeshInstance3D:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	sphere.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = sphere
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# --- setups ------------------------------------------------------------------

func _clear() -> void:
	for child: Node in _actors.get_children():
		_actors.remove_child(child)
		child.free()


## Adds a fighter holding a weapon ("" = signature, "none" = bare hands),
## frozen at POSE_TIME of its idle clip.
func _add_fighter(id: StringName, pal: int, weapon: StringName, pos: Vector3, rest_pose: bool = false) -> FighterModel:
	var f: FighterModel = FighterLook.instantiate_fighter(id)
	f.autoplay_idle = false
	f.palette = pal
	f.position = pos
	_actors.add_child(f)
	var wid: StringName = f.look.signature_weapon if weapon == &"" else weapon
	if wid != &"none":
		f.attach_weapon(WeaponLook.load_id(wid))
	if rest_pose:
		f.skeleton.reset_bone_poses()
	else:
		f.play(f.look.idle_clip, 0.0)
		f.animation_player.seek(POSE_TIME, true)
		f.animation_player.pause()
	return f


## Stands a weapon upright with its origin at `pos`, with its markers shown.
func _add_weapon_display(look: WeaponLook, pos: Vector3) -> Node3D:
	var w: Node3D = look.scene.instantiate()
	w.position = pos
	_actors.add_child(w)
	_show_markers(w)
	var label: Label3D = Label3D.new()
	var tip: Vector3 = WeaponLook.marker(w, WeaponLook.BLADE_TIP).position
	label.text = "%s\n%.2f m" % [look.display_name, _length(w)]
	label.font_size = 40
	label.pixel_size = 0.0015
	label.position = Vector3(0.0, tip.y + 0.08, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	w.add_child(label)
	return w


func _show_markers(w: Node3D) -> void:
	var origin_dot: MeshInstance3D = _dot(Color(1.0, 0.85, 0.1), 0.014)
	w.add_child(origin_dot)
	w.add_child(_lines(PackedVector3Array([Vector3.ZERO, Vector3(0.08, 0, 0), Vector3.ZERO, Vector3(0, 0, 0.08)]), Color(1.0, 0.85, 0.1)))
	for marker_name: StringName in MARKER_COLORS:
		var m: Marker3D = WeaponLook.marker(w, marker_name)
		if m != null:
			m.add_child(_dot(MARKER_COLORS[marker_name], 0.014))


## Overall length along the blade axis, from the meshes' bounds.
static func _length(w: Node3D) -> float:
	var lo: float = INF
	var hi: float = -INF
	for node: Node in w.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		if mi.mesh is ImmediateMesh or mi.mesh is SphereMesh:
			continue
		var xf: Transform3D = _transform_in(mi, w)
		var box: AABB = xf * mi.get_aabb()
		lo = minf(lo, box.position.y)
		hi = maxf(hi, box.end.y)
	return hi - lo


## A bone's posed position in world space.
static func _bone_position(f: FighterModel, bone: StringName) -> Vector3:
	var sk: Skeleton3D = f.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin


static func _transform_in(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf: Transform3D = node.transform
	var p: Node = node.get_parent()
	while p != null and p != ancestor:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _setup_lineup() -> void:
	_clear()
	_add_fighter(&"rogue", 0, &"", Vector3(-0.85, 0, 0))
	_add_fighter(&"hunter", 0, &"", Vector3(0.85, 0, 0))
	var x: float = 2.0
	for id: StringName in WeaponLook.IDS:
		_add_weapon_display(WeaponLook.load_id(id), Vector3(x, 0.45, 0.2))
		x += 0.45
	_look_from(Vector3(0.6, 1.5, 5.2), Vector3(0.6, 0.9, 0.0), 42.0)
	_label.text = "Rogue and Hunter with their signature weapons (palette A); Katana, Greatsword, Dagger"


func _setup_fighter(id: StringName, pal: int, weapon: StringName, view_name: StringName, gameplay: bool, rest_pose: bool = false) -> void:
	_clear()
	var f: FighterModel = _add_fighter(id, pal, weapon, Vector3.ZERO, rest_pose)
	var yaw: float = deg_to_rad(VIEWS.get(view_name, 0.0))
	var dir: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))
	var head: Vector3 = _bone_position(f, &"Head") + Vector3(0.0, 0.08, 0.0)
	if view_name == &"head":
		_look_from(head + Vector3(-0.3, 0.06, 0.8), head, 30.0)
	elif view_name == &"head_back":
		_look_from(head + Vector3(0.55, 0.12, -0.65), head, 30.0)
	elif view_name == &"right_hand" or view_name == &"left_hand":
		var socket: Node3D = f.right_hand if view_name == &"right_hand" else f.left_hand
		var bone: StringName = &"RightHand" if view_name == &"right_hand" else &"LeftHand"
		var sk: Skeleton3D = f.skeleton
		var hand: Vector3 = sk.global_transform * (sk.get_bone_global_pose(sk.find_bone(bone)) * socket.position)
		var side: float = -1.0 if view_name == &"right_hand" else 1.0
		_look_from(hand + Vector3(side * 0.35, 0.2, 0.55), hand, 32.0)
	elif gameplay:
		_look_from(dir * 5.0 + Vector3(0, 1.9, 0), Vector3(0, 1.0, 0), 55.0)
	else:
		_look_from(dir * 2.7 + Vector3(0, 1.15, 0), Vector3(0, 0.95, 0), 40.0)
	var weapon_name: String = f.weapons[0].name if not f.weapons.is_empty() else "bare hands"
	_label.text = "%s, palette %s (%s), %s, %s%s" % [
		f.look.display_name, "AB"[pal], f.look.palettes[pal].display_name, weapon_name,
		String(view_name).replace("_", " "), ", rest pose" if rest_pose else (", 5 m" if gameplay else "")]


func _setup_weapons() -> void:
	_clear()
	var x: float = -0.5
	for id: StringName in WeaponLook.IDS:
		_add_weapon_display(WeaponLook.load_id(id), Vector3(x, 0.45, 0.0))
		x += 0.5
	# A 10 cm grid behind the weapons to read their sizes.
	var grid: PackedVector3Array = PackedVector3Array()
	for i: int in 19:
		grid.append_array([Vector3(-1.0, i * 0.1, -0.15), Vector3(1.0, i * 0.1, -0.15)])
	for i: int in 21:
		grid.append_array([Vector3(-1.0 + i * 0.1, 0.0, -0.15), Vector3(-1.0 + i * 0.1, 1.8, -0.15)])
	_actors.add_child(_lines(grid, Color(0.42, 0.44, 0.47)))
	_look_from(Vector3(0.0, 0.95, 2.4), Vector3(0.0, 0.9, 0.0), 42.0)
	_label.text = "Weapons: green BladeBase, red BladeTip, blue OffHandGrip, yellow origin (main grip)"


# --- sheet -------------------------------------------------------------------

func _capture() -> Image:
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _run_sheet() -> void:
	var dir: String = _sheet_dir if _sheet_dir != "" else ProjectSettings.globalize_path("user://preview_sheet")
	DirAccess.make_dir_recursive_absolute(dir)
	var portrait: Rect2i = Rect2i(500, 0, 600, 900)
	var wide: Rect2i = Rect2i(0, 0, 1600, 900)
	# Each fighter: palettes A and B, front and three-quarter, close and at 5 m.
	for id: StringName in FighterLook.IDS:
		for gameplay: bool in [false, true]:
			var cells: Array[Image] = []
			for pal: int in 2:
				for v: StringName in [&"front", &"three_quarter"]:
					_setup_fighter(id, pal, &"", v, gameplay)
					cells.append(await _capture())
			_save_sheet(cells, portrait, 4, 0.7, dir.path_join("%s_%s.png" % [id, "gameplay_5m" if gameplay else "close"]))
	# Heads close up, for clipping at the hood, hair and neck.
	var heads: Array[Image] = []
	for id: StringName in FighterLook.IDS:
		for v: StringName in [&"head", &"head_back"]:
			_setup_fighter(id, 0, &"none", v, false)
			heads.append(await _capture())
	_save_sheet(heads, Rect2i(350, 0, 900, 900), 4, 0.5, dir.path_join("heads_close.png"))
	# Hands on the grips.
	var hands: Array[Image] = []
	for id: StringName in FighterLook.IDS:
		for w: StringName in WeaponLook.IDS:
			_setup_fighter(id, 0, w, &"right_hand", false)
			hands.append(await _capture())
		_setup_fighter(id, 0, &"daggers", &"left_hand", false)
		hands.append(await _capture())
	_save_sheet(hands, Rect2i(350, 0, 900, 900), 4, 0.5, dir.path_join("hands_close.png"))
	# Rest pose, front and side.
	var rest: Array[Image] = []
	for id: StringName in FighterLook.IDS:
		for v: StringName in [&"front", &"side"]:
			_setup_fighter(id, 0, &"", v, false, true)
			rest.append(await _capture())
	_save_sheet(rest, Rect2i(300, 0, 1000, 900), 4, 0.5, dir.path_join("rest_pose.png"))
	# Every fighter with every weapon.
	for id: StringName in FighterLook.IDS:
		var held: Array[Image] = []
		for v: StringName in [&"front", &"three_quarter"]:
			for w: StringName in WeaponLook.IDS:
				_setup_fighter(id, 0, w, v, false)
				held.append(await _capture())
		_save_sheet(held, portrait, 3, 0.7, dir.path_join("%s_weapons.png" % id))
	# Mirror match at gameplay distance: palette A against palette B.
	for id: StringName in FighterLook.IDS:
		_clear()
		var left: FighterModel = _add_fighter(id, 0, &"", Vector3(-1.2, 0, 0))
		left.rotation.y = deg_to_rad(60.0)
		var right: FighterModel = _add_fighter(id, 1, &"", Vector3(1.2, 0, 0))
		right.rotation.y = deg_to_rad(-60.0)
		_look_from(Vector3(0, 2.0, 5.5), Vector3(0, 1.0, 0), 55.0)
		_label.text = "%s mirror match: palette A (left) against palette B (right), 5 m" % String(id).capitalize()
		_save_sheet([await _capture()], wide, 1, 1.0, dir.path_join("%s_mirror.png" % id))
	_setup_weapons()
	_save_sheet([await _capture()], wide, 1, 1.0, dir.path_join("weapons_lineup.png"))
	_setup_lineup()
	_save_sheet([await _capture()], wide, 1, 1.0, dir.path_join("lineup.png"))
	print("preview: sheets saved in %s" % dir)
	_done = true


## Crops each image, scales it and lays the cells out in rows of `cols`.
static func _save_sheet(images: Array[Image], crop: Rect2i, cols: int, scale: float, path: String) -> void:
	var cw: int = int(crop.size.x * scale)
	var ch: int = int(crop.size.y * scale)
	var rows: int = ceili(images.size() / float(cols))
	var out: Image = Image.create(cw * mini(cols, images.size()), ch * rows, false, Image.FORMAT_RGBA8)
	for i: int in images.size():
		var cell: Image = images[i].get_region(crop)
		cell.convert(Image.FORMAT_RGBA8)
		cell.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), Vector2i((i % cols) * cw, (i / cols) * ch))
	var err: Error = out.save_png(path)
	if err != OK:
		printerr("preview: cannot save %s (%s)" % [path, error_string(err)])
