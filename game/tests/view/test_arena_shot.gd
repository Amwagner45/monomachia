extends GutTest
## The arena screenshot rig (tools/shot_scenes/arena_shot.gd), headless: the
## arena put in by id with the real fighters at its spawns, each view's
## camera, the top-down debug overlay and the chosen preset.

const ArenaShot := preload("res://tools/shot_scenes/arena_shot.gd")

var _services: Node


func before_all() -> void:
	_services = get_tree().root.get_node("GameServices")


## The rig applies its preset to the renderer and the viewport: put back the
## one the run started with.
func after_all() -> void:
	GraphicsApplier.apply(_services.call("graphics_preset"), null, get_viewport())


func _rig(view: ArenaShot.View, preset: StringName = &"") -> ArenaShot:
	var rig: ArenaShot = ArenaShot.new()
	rig.arena_id = ArenaScenes.STANDIN
	rig.view = view
	rig.preset_id = preset
	add_child_autofree(rig)
	return rig


func _match_view(rig: ArenaShot) -> MatchView:
	return rig.host.get_node("View") as MatchView


func test_the_real_fighters_stand_on_the_arenas_spawns() -> void:
	var rig: ArenaShot = _rig(ArenaShot.View.GAMEPLAY)
	var view: MatchView = _match_view(rig)
	assert_eq(view.arena.scene_file_path, ArenaScenes.STANDIN_SCENE)
	assert_eq(view.fighters.size(), 2)
	for side: int in 2:
		var spawn: Node3D = view.arena.get_node("Spawn%d" % side)
		assert_almost_eq(view.fighters[side].position, spawn.position, Vector3.ONE * 1e-4, "fighter %d on its spawn" % side)
		assert_not_null(view.fighters[side].model, "fighter %d is a real fighter" % side)
	assert_false(rig.host.get_node("Hud").visible, "no HUD over the arena")


func test_the_gameplay_watch_and_menu_views_are_the_camera_rigs() -> void:
	var modes: Dictionary = {
		ArenaShot.View.GAMEPLAY: CameraRig.Mode.FOLLOW,
		ArenaShot.View.WATCH: CameraRig.Mode.WATCH,
		ArenaShot.View.MENU: CameraRig.Mode.MENU,
	}
	for shot_view: ArenaShot.View in modes:
		var rig: ArenaShot = _rig(shot_view)
		var camera: CameraRig = _match_view(rig).camera
		assert_eq(camera.mode, modes[shot_view])
		assert_true(camera.current, "the match's own camera")
		assert_null(rig.shot_camera, "no camera of the rig's own")
		assert_almost_eq(camera.global_position, camera.rig_position, Vector3.ONE * 1e-4, "snapped to its target")


func test_the_menu_view_stands_menu_time_into_the_orbit() -> void:
	var rig: ArenaShot = _rig(ArenaShot.View.MENU)
	var camera: CameraRig = _match_view(rig).camera
	var target: Dictionary = camera.menu_target(rig.menu_time)
	assert_almost_eq(camera.global_position, target["pos"] as Vector3, Vector3.ONE * 1e-4)


func test_the_establishing_view_looks_at_the_arena_from_beyond_its_edge_and_below_its_floor() -> void:
	var rig: ArenaShot = _rig(ArenaShot.View.ESTABLISHING)
	var camera: Camera3D = rig.shot_camera
	assert_not_null(camera)
	assert_true(camera.current)
	var at: Vector3 = camera.global_position
	assert_almost_eq(Vector2(at.x, at.z).length(), rig.establishing_distance, 1e-3)
	assert_lt(at.y, 0.0, "below the floor")
	assert_gte(camera.far, _match_view(rig).camera.far, "sees as far as the match camera")


func test_the_top_down_view_rings_the_rules_wall_and_marks_spawns_and_gates() -> void:
	var rig: ArenaShot = _rig(ArenaShot.View.TOP_DOWN)
	assert_eq(rig.shot_camera.projection, Camera3D.PROJECTION_ORTHOGONAL)
	assert_true(rig.shot_camera.current)
	var overlay: Node3D = rig.get_node("DebugOverlay")
	var wall: AABB = (overlay.get_node("RulesWall") as MeshInstance3D).get_aabb()
	assert_almost_eq(wall.size.x, 2.0 * SimConst.ARENA_RADIUS, 0.01, "the rules' wall")
	var limit: AABB = (overlay.get_node("CentreLimit") as MeshInstance3D).get_aabb()
	assert_almost_eq(limit.size.x, 2.0 * (SimConst.ARENA_RADIUS - SimConst.FIGHTER_RADIUS), 0.01, "where fighters' centres stop")
	assert_null(overlay.get_node_or_null("WallFace"), "the stand-in has no arena data to draw")
	var marks: AABB = (overlay.get_node("Markers") as MeshInstance3D).get_aabb()
	var gate_z: float = absf((_match_view(rig).arena.get_node("Gate1") as Node3D).position.z)
	assert_almost_eq(marks.end.z, gate_z + ArenaShot.GATE_MARK_RADIUS, 0.01, "a ring on each gate")
	assert_almost_eq(marks.position.z, -gate_z - ArenaShot.GATE_MARK_RADIUS, 0.01)


func test_the_chosen_preset_reaches_the_arena() -> void:
	var low: GraphicsPreset = GraphicsPreset.load_id(&"low")
	var rig: ArenaShot = _rig(ArenaShot.View.GAMEPLAY, &"low")
	var ink: InkWashPass = _match_view(rig).arena.find_children("*", "InkWashPass", true, false)[0]
	assert_eq(ink.quality, low.post_quality)
	assert_eq(rig.preset.id, &"low")


func test_without_a_preset_it_shoots_the_saved_one() -> void:
	var rig: ArenaShot = _rig(ArenaShot.View.GAMEPLAY)
	assert_eq(rig.preset.id, (_services.call("graphics_preset") as GraphicsPreset).id)
