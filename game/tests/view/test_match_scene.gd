extends GutTest
## The match scene (match_host.tscn) headless: the arena loaded by id, the
## stand-in fighters following the rules, the camera following the player,
## and the HUD's announcements timed on rules steps.

var host: MatchHost
var view: MatchView
var hud: MatchHud


func before_each() -> void:
	host = (load("res://view/match/match_host.tscn") as PackedScene).instantiate()
	host.auto_run = false
	host.use_services = false
	host.input = InputDevices.new(FakeDeviceState.new())
	host.profiles = ControlProfiles.new()
	add_child_autofree(host)
	view = host.get_node("View")
	hud = host.get_node("Hud")


func _cpu(mode: StringName = MatchConfig.DUEL, seed_value: int = 7) -> MatchConfig:
	return MatchConfig.make(
		mode,
		MatchSide.computer(&"rogue", &"katana", 0, &"hard"),
		MatchSide.computer(&"hunter", &"daggers", 1, &"hard"),
		seed_value,
	)


func test_the_scene_builds_the_stage_from_the_config() -> void:
	host.start(_cpu())
	assert_not_null(view.arena, "an arena")
	assert_eq(view.arena_id, MatchConfig.DEFAULT_ARENA)
	assert_eq(view.arena.scene_file_path, ArenaScenes.SCENES[ArenaScenes.STANDIN])
	assert_not_null(view.arena.get_node_or_null("Spawn0"), "spawn and gate markers")
	assert_not_null(view.arena.get_node_or_null("Gate1"))
	assert_eq(view.fighters.size(), 2)
	assert_eq(view.fighters[0].weapon_id, &"katana")
	assert_eq(view.fighters[1].weapon_id, &"daggers")
	assert_ne(view.fighters[0].palette_color(), view.fighters[1].palette_color())
	assert_true(view.camera.current)
	assert_eq(view.camera.mode, CameraRig.Mode.FOLLOW)
	assert_true(hud.visible)


func test_an_arena_not_built_yet_falls_back_to_the_standin() -> void:
	assert_eq(ArenaScenes.scene_path(&"no_such_arena"), ArenaScenes.SCENES[ArenaScenes.STANDIN])
	if not ResourceLoader.exists(ArenaScenes.SCENES[ArenaScenes.MOONLIT_SHRINE]):
		assert_eq(ArenaScenes.scene_path(ArenaScenes.MOONLIT_SHRINE), ArenaScenes.SCENES[ArenaScenes.STANDIN])
	var cfg: MatchConfig = _cpu()
	cfg.arena_id = ArenaScenes.MOONLIT_SHRINE
	host.start(cfg)
	assert_not_null(view.arena)
	assert_eq(view.arena_id, ArenaScenes.MOONLIT_SHRINE)


func test_watch_and_menu_pick_their_cameras() -> void:
	host.start(_cpu(MatchConfig.WATCH))
	assert_eq(view.camera.mode, CameraRig.Mode.WATCH)
	host.start(MatchConfig.attract(), true)
	assert_eq(view.camera.mode, CameraRig.Mode.MENU)
	assert_false(hud.visible, "no HUD behind the menus")


func test_fighters_and_camera_follow_the_rules() -> void:
	host.start(_cpu())
	host.step(900)
	view.render(1.0 / 60.0)
	for i: int in 2:
		var f: Fighter = host.fighter(i)
		assert_almost_eq(view.fighters[i].position, host.display_position(i), Vector3.ONE * 1e-5)
		assert_almost_eq(view.fighters[i].rotation.y, wrapf(host.display_yaw(i), -PI, PI), 1e-4)
		assert_not_null(view.fighters[i].last_pose)
		assert_false(f.hp != f.hp, "no NaN")
	view.snap_camera()
	var p: Vector3 = host.display_position(0)
	var o: Vector3 = host.display_position(1)
	var d: Vector3 = Vector3(o.x - p.x, 0.0, o.z - p.z).normalized()
	var rel: Vector3 = view.camera.rig_position - p
	assert_lt(Vector3(rel.x, 0.0, rel.z).dot(d), 0.0, "the camera is behind the player")


func test_events_shake_and_kick_the_camera() -> void:
	host.start(_cpu())
	var at: Dictionary = {"x": 0.0, "y": 1.25, "z": 0.0}
	host.sim_event.emit({"t": &"hit", "attacker": 0, "target": 1, "heavy": false, "sound": &"blade", "pos": at})
	assert_eq(view.camera.shake, 0.0, "light hits don't shake")
	host.sim_event.emit({"t": &"hit", "attacker": 0, "target": 1, "heavy": true, "sound": &"blade", "pos": at})
	assert_almost_eq(view.camera.shake, view.heavy_hit_shake, 1e-6, "heavy hits do")
	view.camera.shake = 0.0
	host.sim_event.emit({"t": &"parry", "parrier": 1, "attacker": 0, "kind": &"parry", "pos": at})
	assert_almost_eq(view.camera.shake, view.parry_shake, 1e-6)
	assert_eq(view.camera.fov_kick, 3.0)
	host.sim_event.emit({"t": &"disarm", "victim": 0, "by": 1, "reason": &"parried", "pos": at})
	assert_eq(view.camera.fov_kick, 7.0)
	host.sim_event.emit({"t": &"ko", "loser": 1, "winner": 0})
	assert_gt(view.camera.ko_orbit, 0.0, "the KO swings the camera out")
	host.sim_event.emit({"t": &"roundStart", "round": 2})
	assert_eq(view.camera.ko_orbit, 0.0)


func test_the_hud_times_announcements_on_rules_steps() -> void:
	host.start(_cpu())
	assert_eq(hud.announcement_text(), "Round 1", "the intro calls the round")
	host.step(Match.FIGHT_CALL_FRAME - 1)
	assert_eq(hud.announcement_text(), "Round 1")
	host.step(1)
	assert_eq(hud.announcement_text(), "Fight")
	host.pause()
	# wall time passing changes nothing while paused
	for i: int in 30:
		host.advance(0.1)
		hud._process(0.1)
	assert_eq(hud.announcement_text(), "Fight")
	host.resume()
	host.step(MatchHud.FIGHT_FRAMES)
	assert_eq(hud.announcement_text(), "", "gone after its frames")


func test_the_hud_calls_the_ko_and_the_round_winner() -> void:
	host.start(_cpu())
	var steps: int = 0
	while host.sim_match.phase != &"roundEnd" and steps < 30000:
		host.step(1)
		steps += 1
	assert_eq(host.sim_match.phase, &"roundEnd")
	assert_true(hud.announcement_text() == "K.O." or hud.announcement_text() == "Double K.O.")
	host.step(MatchHud.ROUND_RESULT_DELAY)
	var winner: int = host.sim_match.round_winner
	if winner >= 0:
		assert_eq(hud.announcement_text(), "%s wins the round" % host.fighter(winner).name)
	else:
		assert_eq(hud.announcement_text(), "Draw")


func test_the_hud_offers_the_ultimate_to_a_human_player() -> void:
	var cfg: MatchConfig = MatchConfig.default_duel()
	host.start(cfg)
	host.step(Match.INTRO_FRAMES + 1)
	host.fighter(0).hp = 20.0
	hud._process(1.0 / 60.0)
	assert_string_contains(hud.hint_text(), "Ultimate ready")
	assert_string_contains(hud.hint_text(), "Left Click + Right Click")
	host.fighter(0).hp = 100.0
	hud._process(1.0 / 60.0)
	assert_eq(hud.hint_text(), "")


func test_a_whole_match_renders_without_errors() -> void:
	host.start(_cpu(MatchConfig.DUEL, 19))
	var steps: int = 0
	while not host.is_finished() and steps < 60 * 60 * 12:
		host.step(3)
		steps += 3
		view.render(1.0 / 20.0)
		hud._process(1.0 / 20.0)
	assert_true(host.is_finished())
