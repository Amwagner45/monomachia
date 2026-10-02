extends GutTest
## The match's sound (match_host.tscn's Audio): every rules event's cues in a
## played match and on the results screen, silence from the duel behind the
## menus, sound held through a pause, and nothing left playing after a quit.
## Headless runs use the dummy audio driver, so these tests follow what the
## sound player is asked to play.

var host: MatchHost
var audio: MatchAudio


func before_each() -> void:
	host = (load("res://view/match/match_host.tscn") as PackedScene).instantiate()
	host.auto_run = false
	host.use_services = false
	host.input = InputDevices.new(FakeDeviceState.new())
	host.profiles = ControlProfiles.new()
	add_child_autofree(host)
	audio = host.get_node("Audio")
	audio.player.auto_run = false


## Computer against computer on the stand-in arena.
func _cpu(mode: StringName = MatchConfig.DUEL, seed_value: int = 7) -> MatchConfig:
	return MatchConfig.make(
		mode,
		MatchSide.computer(&"rogue", &"katana", 0, &"hard"),
		MatchSide.computer(&"hunter", &"greatsword", 1, &"hard"),
		seed_value,
		ArenaScenes.STANDIN,
	)


## Every cue the match's sound player starts, with its bus.
func _record() -> Array[Dictionary]:
	var log: Array[Dictionary] = []
	audio.player.played.connect(func(cue: StringName, voice: Node) -> void:
		log.append({"cue": cue, "bus": voice.get("bus")}))
	return log


func _cues(log: Array[Dictionary]) -> Array[StringName]:
	var names: Array[StringName] = []
	for entry: Dictionary in log:
		names.append(entry["cue"])
	return names


func _count(log: Array[Dictionary], cue_name: StringName) -> int:
	return _cues(log).count(cue_name)


func _descendants(node: Node) -> int:
	var n := node.get_child_count()
	for child: Node in node.get_children():
		n += _descendants(child)
	return n


func test_a_played_duel_plays_its_events_cues_in_order_on_their_buses() -> void:
	var events: Array[Dictionary] = []
	host.sim_event.connect(func(e: Dictionary) -> void: events.append(e))
	var log := _record()
	host.start(_cpu())
	host.step(Match.INTRO_FRAMES + 60 * 20)
	var expected: Array[StringName] = []
	var types := {}
	for e: Dictionary in events:
		types[StringName(e["t"])] = true
		for cue: Dictionary in SoundBank.cues_for(e):
			if float(cue["delay"]) == 0.0:
				expected.append(cue["cue"])
	assert_true(types.has(&"roundStart") and types.has(&"swing"), "the round was called and swung in")
	assert_true(types.has(&"hit") or types.has(&"block"), "and something landed")
	assert_eq(_cues(log), expected, "every event's cues, in the world's order")
	for entry: Dictionary in log:
		assert_eq(entry["bus"], SoundBank.CUES[entry["cue"]]["bus"], "%s on its bus" % entry["cue"])


func test_watch_plays_too() -> void:
	var log := _record()
	host.start(_cpu(MatchConfig.WATCH))
	assert_eq(_cues(log), [&"round_roll"] as Array[StringName])


func test_the_duel_behind_the_menus_is_silent() -> void:
	var log := _record()
	var cfg := MatchConfig.attract(5)
	cfg.arena_id = ArenaScenes.STANDIN
	host.start(cfg, true)
	var restarts: Array[int] = []
	host.match_started.connect(func(_c: MatchConfig) -> void: restarts.append(host.step_count))
	while restarts.is_empty() and host.step_count < 60 * 60 * 12:
		host.step(10)
	assert_eq(restarts.size(), 1, "a whole attract duel and its restart")
	host.step(Match.INTRO_FRAMES + 60)
	audio.player.advance(5.0)
	assert_eq(log.size(), 0)
	assert_true(audio.player.is_quiet())


func test_a_pause_holds_the_round_gong() -> void:
	var log := _record()
	host.start(_cpu())
	assert_eq(_cues(log), [&"round_roll"] as Array[StringName])
	host.pause()
	assert_true(audio.player.is_held())
	audio.player.advance(3.0)
	assert_eq(_count(log, &"gong"), 0, "no gong over the pause menu")
	host.resume()
	assert_false(audio.player.is_held())
	audio.player.advance(1.4)
	assert_eq(_count(log, &"gong"), 1, "it rings once the match resumes")


func test_quitting_leaves_nothing_playing() -> void:
	var log := _record()
	host.start(_cpu())
	host.step(Match.INTRO_FRAMES + 60 * 5)
	assert_false(audio.player.is_quiet())
	var played := log.size()
	host.stop()
	assert_true(audio.player.is_quiet(), "no voice playing, nothing waiting")
	audio.player.advance(3.0)
	assert_eq(log.size(), played)


func test_a_new_match_drops_the_last_one_s_sound() -> void:
	var log := _record()
	host.start(_cpu())
	host.step(30)
	host.start(_cpu(MatchConfig.DUEL, 8))
	audio.player.advance(1.4)
	assert_eq(_count(log, &"round_roll"), 2)
	assert_eq(_count(log, &"gong"), 1, "only the new round's gong rings")


func test_the_results_screen_still_plays() -> void:
	var log := _record()
	host.start(_cpu(MatchConfig.DUEL, 19))
	while not host.is_finished() and host.step_count < 60 * 60 * 12:
		host.step(10)
	assert_true(host.is_finished())
	var played := log.size()
	host.sim_event.emit({"t": &"weaponBounce", "owner": 0, "speed": 9.0, "pos": {"x": 1.0, "y": 0.0, "z": 0.0}})
	assert_eq(_cues(log).slice(played), [&"weapon_bounce", &"weapon_clatter"] as Array[StringName])


func test_rematches_and_restarts_leave_no_stray_nodes() -> void:
	host.start(_cpu())
	var baseline := _descendants(audio)
	assert_gt(baseline, 1, "the sound player and its voices")
	for k: int in 3:
		host.step(Match.INTRO_FRAMES + 120)
		if k == 1:
			var cfg := MatchConfig.attract(k + 5)
			cfg.arena_id = ArenaScenes.STANDIN
			host.start(cfg, true)
		else:
			host.start(_cpu(MatchConfig.DUEL, 7 + k))
		await get_tree().process_frame
		assert_eq(_descendants(audio), baseline, "match %d: nothing left behind" % k)
