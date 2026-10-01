extends Node3D
## Screenshot rig for an arena: the arena as a match shows it, from each of
## the match's cameras and from two of its own. A MatchHost, stepped without
## the clock, plays a computer duel (the Rogue with the katana against the
## Hunter with the greatsword) held in the round's intro, so the real fighters
## stand on their spawns; MatchView.set_arena puts the arena in; the chosen
## graphics preset is applied to the renderer, the window and the whole rig.
## Each .tscn next to this script picks a view; render one with
##   node scripts/godot.mjs shots res://tools/shot_scenes/arena_<view>.tscn <out.png> 30 [--preset=<id>] [--arena=<id>]
##
## The arena is its ArenaDef's own scene whenever that scene exists, even
## while ArenaScenes' radius guard keeps it out of matches, so an arena can be
## shot before the rules reach its radius. Otherwise it is whatever
## ArenaScenes draws for the id (the stand-in).
##
## Views:
## - gameplay: the match camera over side 0's shoulder (CameraRig FOLLOW);
## - watch: the match camera side-on (CameraRig WATCH);
## - menu: the match camera's orbit behind the menus, menu_time seconds in;
## - establishing: the whole arena from beyond its edge and below its floor,
##   which shows a floating arena's underside. Its numbers frame the
##   Moonlit Shrine's; the stand-in, with nothing under its floor, sits small
##   at the top of the frame;
## - top_down: an orthographic debug view with a legend: the rules' wall
##   (magenta), where fighters' centres stop (grey), the arena's walkable circle
##   when it differs from the rules' wall (orange) and its wall's inner face
##   (yellow) from the arena's ArenaDef, and the arena's Spawn and Gate
##   markers with their facing (cyan), plus a close-up of the wall at +X.

enum View { GAMEPLAY, WATCH, MENU, ESTABLISHING, TOP_DOWN }

## The match camera's mode for each of its views.
const CAMERA_MODES: Dictionary[View, CameraRig.Mode] = {
	View.GAMEPLAY: CameraRig.Mode.FOLLOW,
	View.WATCH: CameraRig.Mode.WATCH,
	View.MENU: CameraRig.Mode.MENU,
}
const SEED: int = 7

const RULES_WALL_COLOR := Color(1.0, 0.2, 0.85)
const CENTRE_LIMIT_COLOR := Color(0.65, 0.65, 0.68)
const ARENA_WALKABLE_COLOR := Color(1.0, 0.55, 0.1)
const WALL_FACE_COLOR := Color(1.0, 0.85, 0.2)
const MARKER_COLOR := Color(0.3, 0.9, 1.0)
const TITLE_COLOR := Color(0.92, 0.92, 0.95)
## The overlay's marks: a ring on each spawn (fighter-sized) and on each gate,
## lifted clear of the floor and the gate's props, and an arrow for facing.
const SPAWN_MARK_RADIUS: float = 0.42
const SPAWN_MARK_LIFT: float = 2.0
const GATE_MARK_RADIUS: float = 0.6
const GATE_MARK_LIFT: float = 8.0

@export var arena_id: StringName = ArenaScenes.MOONLIT_SHRINE
@export var view: View = View.GAMEPLAY
## A preset id (low, medium or high); empty shoots the saved preset.
@export var preset_id: StringName = &""
## Frames to let the renderer settle before the capture.
@export var settle_frames: int = 20

@export_group("Menu")
## Seconds into the menu orbit. It starts straight behind side 1, where one
## fighter hides the other; 10 s in it shows them three-quarter on.
@export var menu_time: float = 10.0

@export_group("Establishing")
## Angle around the arena (degrees, from +Z toward +X), distance from the
## centre and height of the camera, and the height it looks at (m).
@export var establishing_angle_deg: float = 228.0
@export var establishing_distance: float = 58.0
@export var establishing_height: float = -5.0
@export var establishing_look_height: float = -13.0
@export var establishing_fov: float = 60.0

@export_group("Top-down")
## How many metres the top-down view spans, top to bottom (an orthographic
## camera's size is its height).
@export var top_down_size: float = 46.0
## How far right of the screen's centre the arena sits (m), clear of the
## legend and the close-up on the left.
@export var top_down_shift: float = 12.0
## The overlay rings' width (m): two pixels or so at 46 m tall.
@export var ring_width: float = 0.1

var host: MatchHost
## The preset the shot is taken at.
var preset: GraphicsPreset
## The rig's own camera, for the establishing and top-down views; null for
## the match camera's views.
var shot_camera: Camera3D
var _ready_flag: bool = false


func shot_frames() -> int:
	return settle_frames


func shot_ready() -> bool:
	return _ready_flag


func _ready() -> void:
	_read_args()
	preset = _chosen_preset()
	host = (load("res://view/match/match_host.tscn") as PackedScene).instantiate()
	host.auto_run = false
	host.use_services = false
	add_child(host)
	var match_view: MatchView = host.get_node("View")
	match_view.set_arena(_make_arena(), arena_id)
	host.start(MatchConfig.make(
		MatchConfig.WATCH,
		MatchSide.computer(&"rogue", &"katana", 0, &"hard"),
		MatchSide.computer(&"hunter", &"greatsword", 1, &"hard"),
		SEED,
		arena_id,
	))
	# Twice: the view shows the position before the last step.
	host.step(2)
	var hud: CanvasLayer = host.get_node("Hud")
	hud.visible = false
	hud.set_process(false)
	_aim_match_camera(match_view)
	match_view.set_process(false)
	if not CAMERA_MODES.has(view):
		_add_shot_camera(match_view.camera.far)
	GraphicsApplier.apply(preset, self, get_viewport())
	if view == View.TOP_DOWN:
		_setup_top_down(match_view.arena)
	_ready_flag = true


## --preset= and --arena= on the command line override the exports. An
## unknown arena is an error, so the shot run fails.
func _read_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--preset="):
			preset_id = StringName(a.trim_prefix("--preset="))
		elif a.begins_with("--arena="):
			arena_id = StringName(a.trim_prefix("--arena="))
	if not ArenaScenes.has(arena_id):
		push_error("arena_shot.gd: no arena '%s'" % arena_id)


## The preset named by preset_id, or the saved one when it is empty. An
## unknown id is an error, so the shot run fails.
func _chosen_preset() -> GraphicsPreset:
	if preset_id == &"":
		return GameServices.graphics_preset()
	var chosen: GraphicsPreset = GraphicsPreset.load_id(preset_id)
	if chosen == null:
		push_error("arena_shot.gd: no preset '%s' (%s)" % [preset_id, ", ".join(PackedStringArray(GraphicsPreset.IDS))])
		return GameServices.graphics_preset()
	return chosen


## The arena's own scene when its data names one that exists (past the radius
## guard), else what ArenaScenes draws for the id.
func _make_arena() -> Node3D:
	var def: ArenaDef = ArenaScenes.def(arena_id)
	if def != null and ResourceLoader.exists(def.scene_path):
		return (load(def.scene_path) as PackedScene).instantiate() as Node3D
	return ArenaScenes.instantiate(arena_id)


## Puts the match camera in the view's mode (when the view is one of its
## own) and snaps it there.
func _aim_match_camera(match_view: MatchView) -> void:
	var camera: CameraRig = match_view.camera
	camera.mode = CAMERA_MODES.get(view, CameraRig.Mode.FOLLOW)
	if view == View.MENU:
		# Nothing has rendered the view yet, so the orbit's clock is at 0:
		# run it to menu_time, and the snap lands there.
		camera.update_rig(menu_time, Vector3.ZERO, Vector3.ZERO)
	match_view.snap_camera()


## The rig's own camera, for the establishing and top-down views.
func _add_shot_camera(far_plane: float) -> void:
	shot_camera = Camera3D.new()
	shot_camera.name = "ShotCamera"
	shot_camera.near = 0.1
	shot_camera.far = far_plane
	add_child(shot_camera)
	if view == View.ESTABLISHING:
		var a: float = deg_to_rad(establishing_angle_deg)
		shot_camera.fov = establishing_fov
		shot_camera.position = Vector3(sin(a) * establishing_distance, establishing_height, cos(a) * establishing_distance)
		shot_camera.look_at(Vector3(0.0, establishing_look_height, 0.0))
	else:
		shot_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		shot_camera.size = top_down_size
		# Looking straight down with -Z up the screen, so +X is right.
		shot_camera.position = Vector3(-top_down_shift, 90.0, 0.0)
		shot_camera.look_at(Vector3(-top_down_shift, 0.0, 0.0), Vector3.FORWARD)
	shot_camera.make_current()


# ------------------------------------------------------------------ top-down

## No fog, distance mist or vignette, the overlay, the legend and the
## close-up.
func _setup_top_down(arena: Node3D) -> void:
	for node: Node in arena.find_children("*", "WorldEnvironment", true, false):
		(node as WorldEnvironment).environment.fog_enabled = false
	for node: Node in arena.find_children("*", "InkWashPass", true, false):
		var ink: InkWashPass = node
		ink.set_param(&"vignette_strength", 0.0)
		ink.set_param(&"fade_max", 0.0)
	var def: ArenaDef = arena.get("def") as ArenaDef
	add_child(_overlay(arena, def))
	var layer := CanvasLayer.new()
	layer.name = "Legend"
	add_child(layer)
	layer.add_child(_legend(arena, def))
	_add_close_up(layer, def.wall_inner_radius() if def != null else SimConst.ARENA_RADIUS)


func _overlay(arena: Node3D, def: ArenaDef) -> Node3D:
	var root := Node3D.new()
	root.name = "DebugOverlay"
	var r: float = SimConst.ARENA_RADIUS
	root.add_child(_ring("RulesWall", r, 1.5, RULES_WALL_COLOR))
	root.add_child(_ring("CentreLimit", r - SimConst.FIGHTER_RADIUS, 1.5, CENTRE_LIMIT_COLOR))
	if _walkable_differs(def):
		root.add_child(_ring("ArenaWalkable", def.walkable_radius, 1.52, ARENA_WALKABLE_COLOR))
	if def != null:
		root.add_child(_ring("WallFace", def.wall_inner_radius() + ring_width, 1.55, WALL_FACE_COLOR))
	var marks := MeshKit.new()
	for key: String in ["Spawn0", "Spawn1", "Gate0", "Gate1"]:
		var marker: Node3D = arena.get_node_or_null(key)
		if marker == null:
			continue
		var at: Transform3D = marker.global_transform
		var gate: bool = key.begins_with("Gate")
		var lift := Vector3(0.0, GATE_MARK_LIFT if gate else SPAWN_MARK_LIFT, 0.0)
		var size: float = GATE_MARK_RADIUS if gate else SPAWN_MARK_RADIUS
		marks.disc(Transform3D(Basis(), at.origin + lift), size, 24, 1, size - 0.15)
		var facing: Vector3 = -at.basis.z
		marks.box(Transform3D(at.basis, at.origin + lift + facing * (size + 0.4)), Vector3(0.12, 0.05, 0.8))
	var mi: MeshInstance3D = MeshKit.instance(marks.commit(), _flat(MARKER_COLOR), false)
	mi.name = "Markers"
	root.add_child(mi)
	return root


## A flat ring ring_width wide, its outer edge at radius.
func _ring(ring_name: String, radius: float, height: float, color: Color) -> MeshInstance3D:
	var kit := MeshKit.new()
	kit.disc(Transform3D(Basis(), Vector3(0.0, height, 0.0)), radius, 256, 1, radius - ring_width)
	var mi: MeshInstance3D = MeshKit.instance(kit.commit(), _flat(color), false)
	mi.name = ring_name
	return mi


func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	return m


func _legend(arena: Node3D, def: ArenaDef) -> Control:
	var r: float = SimConst.ARENA_RADIUS
	var rows: Array[Array] = [
		[TITLE_COLOR, "%s, top-down (%.0f m tall), preset %s" % [_arena_title(def), top_down_size, preset.id]],
		[RULES_WALL_COLOR, "the rules' wall: ARENA_RADIUS %.2f m" % r],
		[CENTRE_LIMIT_COLOR, "fighters' centres stop at %.2f m (minus the %.2f m body)" % [r - SimConst.FIGHTER_RADIUS, SimConst.FIGHTER_RADIUS]],
	]
	if _walkable_differs(def):
		rows.append([ARENA_WALKABLE_COLOR, "the arena's walkable radius %.2f m (matches use the stand-in until the rules match it)" % def.walkable_radius])
	if def == null:
		rows.append([WALL_FACE_COLOR, "no arena data: the stand-in's wall stands on the rules' wall"])
	else:
		rows.append([WALL_FACE_COLOR, "wall inner face %.3f m (wall %.2f m, %.2f m thick)" % [def.wall_inner_radius(), def.wall_radius, def.wall_thickness]])
	var spawn: Node3D = arena.get_node_or_null("Spawn1")
	var gate: Node3D = arena.get_node_or_null("Gate1")
	if spawn != null and gate != null:
		rows.append([MARKER_COLOR, "markers: spawns at z = ±%.2f m, gates at ±%.2f m (arrows: facing)" % [absf(spawn.position.z), absf(gate.position.z)]])
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	var list := VBoxContainer.new()
	panel.add_child(list)
	for row: Array in rows:
		var label := Label.new()
		label.text = row[1]
		label.add_theme_color_override(&"font_color", row[0])
		label.add_theme_font_size_override(&"font_size", 20)
		list.add_child(label)
	return panel


## Whether the arena's data puts its walkable circle somewhere other than the
## rules' wall (which keeps it out of matches).
static func _walkable_differs(def: ArenaDef) -> bool:
	return def != null and not is_equal_approx(def.walkable_radius, SimConst.ARENA_RADIUS)


## The arena's name, or the stand-in's (and the arena it stands in for).
func _arena_title(def: ArenaDef) -> String:
	if def != null:
		return def.display_name
	if arena_id == ArenaScenes.STANDIN:
		return "The stand-in arena"
	return "The stand-in arena (in place of %s)" % arena_id


## A close-up of the wall at +X (its inner face at wall_x), 2.4 m tall, in
## the bottom-left corner.
func _add_close_up(layer: CanvasLayer, wall_x: float) -> void:
	var at_x: float = wall_x + 0.2
	var frame := SubViewportContainer.new()
	frame.stretch = true
	frame.size = Vector2(480, 360)
	frame.position = Vector2(24, get_viewport().get_visible_rect().size.y - 360 - 24)
	layer.add_child(frame)
	var sub := SubViewport.new()
	sub.size = Vector2i(480, 360)
	frame.add_child(sub)
	var close := Camera3D.new()
	close.projection = Camera3D.PROJECTION_ORTHOGONAL
	close.size = 2.4
	close.far = 200.0
	sub.add_child(close)
	close.look_at_from_position(Vector3(at_x, 60.0, 0.0), Vector3(at_x, 0.0, 0.0), Vector3.FORWARD)
	close.make_current()
	var caption := Label.new()
	caption.text = "close-up of the wall at +X (2.4 m tall)"
	caption.add_theme_font_size_override(&"font_size", 18)
	caption.position = frame.position + Vector2(8, 4)
	layer.add_child(caption)
