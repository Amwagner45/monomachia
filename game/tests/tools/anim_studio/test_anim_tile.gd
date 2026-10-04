extends GutTest
## AnimTile (tools/anim_studio/gallery/anim_tile.gd, docs/specs/animation-studio.md,
## task 5): one live gallery tile, a small viewport with a fighter looping one
## animation, paused while scrolled out of view. The main tests run on the
## fallback path (`force_missing`, as a fresh clone plays it); the ones that
## need the Iglesias clips skip themselves without them.

const TILE_SCENE: PackedScene = preload("res://tools/anim_studio/gallery/anim_tile.tscn")

var _manifest: ClipManifest
var _catalogue: StudioCatalogue


func before_each() -> void:
	_manifest = ClipManifest.read()
	_catalogue = StudioCatalogue.build(_manifest, MoveClips.read(_manifest), StateClips.read(), StudioLibraries.keyed().get_animation_list())


func after_each() -> void:
	ClipLibraries.force_missing = false


func _tile(entry: StudioCatalogue.Entry, fighter_id: StringName = &"hunter") -> AnimTile:
	var tile: AnimTile = TILE_SCENE.instantiate() as AnimTile
	add_child_autofree(tile)
	tile.setup(entry, fighter_id)
	return tile


## A hand-made entry playing `clips`.
func _entry(kind: StringName, group: StringName, id: StringName, clips: Array[String]) -> StudioCatalogue.Entry:
	var e: StudioCatalogue.Entry = StudioCatalogue.Entry.new()
	e.kind = kind
	e.group = group
	e.id = id
	e.name = String(id)
	e.clips = clips
	return e


func _hand(tile: AnimTile) -> Vector3:
	var sk: Skeleton3D = tile.model.skeleton
	return sk.get_bone_global_pose(sk.find_bone("RightHand")).origin


## The first move of `weapon` that has a fallback.
func _move_with_fallback(weapon: StringName) -> StudioCatalogue.Entry:
	for e: StudioCatalogue.Entry in _catalogue.in_group(weapon):
		if e.kind == StudioCatalogue.KIND_MOVE and not e.fallbacks.is_empty():
			return e
	return null


# --- playing ------------------------------------------------------------------


func test_a_move_poses_differently_at_the_start_and_the_middle_on_the_fallback() -> void:
	ClipLibraries.force_missing = true
	var entry: StudioCatalogue.Entry = _move_with_fallback(&"katana")
	assert_not_null(entry, "a katana move has a fallback")
	var tile: AnimTile = _tile(entry)
	assert_true(tile.duration > 0.0, "it plays a clip")
	assert_false(tile.is_still(), "so it isn't a still")
	tile.seek(0.0)
	var start: Vector3 = _hand(tile)
	tile.seek(tile.duration * 0.5)
	var middle: Vector3 = _hand(tile)
	assert_gt(start.distance_to(middle), 0.05, "the hand has moved")


func test_a_move_poses_differently_at_the_start_and_the_middle_with_the_packs() -> void:
	if not ClipLibraries.available():
		pending("local-only: no clip libraries (node scripts/godot.mjs clips)")
		return
	var entry: StudioCatalogue.Entry = null
	for e: StudioCatalogue.Entry in _catalogue.in_group(&"katana"):
		if e.kind == StudioCatalogue.KIND_MOVE and not e.clips.is_empty():
			entry = e
			break
	assert_not_null(entry, "a katana move has clips")
	var tile: AnimTile = _tile(entry)
	assert_false(tile.is_still(), "it plays its chain")
	assert_gt(tile.duration, 0.0, "it has a length")
	tile.seek(0.0)
	var start: Vector3 = _hand(tile)
	tile.seek(tile.duration * 0.5)
	assert_gt(start.distance_to(_hand(tile)), 0.05, "the hand has moved")


func test_a_move_without_the_packs_stretches_its_fallback_over_the_move() -> void:
	ClipLibraries.force_missing = true
	var entry: StudioCatalogue.Entry = _move_with_fallback(&"katana")
	var tile: AnimTile = _tile(entry)
	var frames: int = Moves.WEAPONS[&"katana"].moves[entry.id].total_frames()
	assert_almost_eq(tile.duration / tile.playback_rate, float(frames) / float(SimConst.FPS), 0.001, "one loop takes the move's frames")


func test_pausing_stops_time_advancing() -> void:
	ClipLibraries.force_missing = true
	var tile: AnimTile = _tile(_move_with_fallback(&"katana"))
	tile._process(0.1)
	var running: float = tile.time
	assert_gt(running, 0.0, "time advances while it plays")
	tile.set_playing(false)
	tile._process(0.1)
	tile._process(0.1)
	assert_eq(tile.time, running, "and stands still when paused")
	tile.set_playing(true)
	tile._process(0.1)
	assert_ne(tile.time, running, "and runs again when resumed")


func test_pausing_switches_the_viewport_off() -> void:
	ClipLibraries.force_missing = true
	var tile: AnimTile = _tile(_move_with_fallback(&"katana"))
	assert_eq(tile.viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "playing renders")
	tile.set_playing(false)
	assert_eq(tile.viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED, "paused doesn't")
	assert_false(tile.is_playing())
	tile.set_playing(true)
	assert_eq(tile.viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "resumed renders again")


func test_time_loops_at_the_clips_length() -> void:
	ClipLibraries.force_missing = true
	var tile: AnimTile = _tile(_entry(StudioCatalogue.KIND_SOURCE, StudioCatalogue.GROUP_SOURCE, &"ual/Sword_Idle", ["ual/Sword_Idle"] as Array[String]))
	var length: float = StudioLibraries.ual().get_animation(&"Sword_Idle").length
	assert_almost_eq(tile.duration, length, 0.001, "its own length")
	tile._process(length * 0.75)
	tile._process(length * 0.5)
	assert_almost_eq(tile.time, length * 0.25, 0.001, "wrapped round")


func test_the_entrys_speed_times_the_playback() -> void:
	ClipLibraries.force_missing = true
	var entry: StudioCatalogue.Entry = _entry(StudioCatalogue.KIND_SOURCE, StudioCatalogue.GROUP_SOURCE, &"ual/Sword_Dash", ["ual/Sword_Dash"] as Array[String])
	entry.speed = 2.0
	var fast: AnimTile = _tile(entry)
	assert_eq(fast.playback_rate, 2.0)
	fast._process(0.05)
	assert_almost_eq(fast.time, 0.1, 0.0001, "twice as fast")
	for odd: float in [NAN, 0.0]:
		entry.speed = odd
		assert_eq(_tile(entry).playback_rate, 1.0, "%s plays at 1.0" % odd)


# --- what it plays ------------------------------------------------------------


func test_a_ual_source_clip_plays_without_the_packs() -> void:
	ClipLibraries.force_missing = true
	var entry: StudioCatalogue.Entry = _entry(StudioCatalogue.KIND_SOURCE, StudioCatalogue.GROUP_SOURCE, &"ual/Sword_Dash", ["ual/Sword_Dash"] as Array[String])
	var tile: AnimTile = _tile(entry)
	assert_false(tile.is_still(), "it plays")
	assert_almost_eq(tile.duration, StudioLibraries.ual().get_animation(&"Sword_Dash").length, 0.001, "the clip's own length")
	tile.seek(0.0)
	var start: Vector3 = _hand(tile)
	tile.seek(tile.duration * 0.5)
	assert_gt(start.distance_to(_hand(tile)), 0.01, "and moves")


func test_a_keyed_clip_plays_without_the_packs() -> void:
	ClipLibraries.force_missing = true
	var chain: Array[String] = ["keyed/%s" % KeyedClips.STOMP]
	var tile: AnimTile = _tile(_entry(StudioCatalogue.KIND_STATE, StudioCatalogue.GROUP_STATES, &"stomp", chain))
	assert_false(tile.is_still(), "it plays")
	assert_almost_eq(tile.duration, StudioLibraries.keyed().get_animation(KeyedClips.STOMP).length, 0.001, "the keyed clip's length")


func test_a_state_without_the_packs_plays_one_fallback_per_part() -> void:
	ClipLibraries.force_missing = true
	var entry: StudioCatalogue.Entry = _catalogue.find(StudioCatalogue.KIND_STATE, &"knockdown")
	assert_eq(entry.fallbacks.size(), entry.clips.size(), "a fallback for each phase")
	var tile: AnimTile = _tile(entry)
	var total: float = 0.0
	for f: String in entry.fallbacks:
		total += _ual_length(f)
	assert_false(tile.is_still(), "it plays")
	assert_almost_eq(tile.duration, total, 0.001, "the phases' fallbacks laid end to end")


func _ual_length(chain_entry: String) -> float:
	return StudioLibraries.ual().get_animation(StringName(chain_entry.substr(chain_entry.find("/") + 1))).length


func test_an_entry_with_no_clips_shows_a_still_pose() -> void:
	for missing: bool in [true, false]:
		ClipLibraries.force_missing = missing
		var rebound: StudioCatalogue.Entry = _catalogue.find(StudioCatalogue.KIND_STATE, &"rebound")
		assert_true(rebound.clips.is_empty(), "the rebound has no clips")
		var tile: AnimTile = _tile(rebound)
		assert_true(tile.is_still(), "a still")
		assert_eq(tile.duration, 0.0)
		tile._process(0.1)
		assert_eq(tile.time, 0.0, "nothing advances")
		assert_not_null(tile.model, "the fighter is there")


func test_an_entry_that_cant_play_falls_back_to_a_still() -> void:
	ClipLibraries.force_missing = true
	# an Iglesias clip with no fallback and no packs
	var tile: AnimTile = _tile(_entry(StudioCatalogue.KIND_SOURCE, StudioCatalogue.GROUP_SOURCE, &"Walk01_Forward", ["Walk01_Forward"] as Array[String]))
	assert_true(tile.is_still(), "nothing to play")


func test_every_catalogue_entry_sets_up_without_the_packs() -> void:
	ClipLibraries.force_missing = true
	var tile: AnimTile = _tile(_catalogue.entries[0])
	for e: StudioCatalogue.Entry in _catalogue.entries:
		tile.setup(e, &"hunter")
		tile._process(0.05)
		assert_not_null(tile.model, "%s has a fighter" % e.id)


func test_the_rogue_sets_up_too() -> void:
	ClipLibraries.force_missing = true
	var tile: AnimTile = _tile(_move_with_fallback(&"daggers"), &"rogue")
	assert_eq(tile.model.look.id, &"rogue")
	tile.seek(tile.duration * 0.5)
	assert_false(tile.is_still())


func test_setting_up_again_replaces_the_fighter() -> void:
	ClipLibraries.force_missing = true
	var tile: AnimTile = _tile(_move_with_fallback(&"katana"))
	var first: FighterModel = tile.model
	tile.setup(_move_with_fallback(&"katana"), &"rogue")
	assert_ne(tile.model, first, "a new fighter")
	assert_eq(tile.model.look.id, &"rogue")
	assert_eq(tile.viewport.get_children().filter(func(n: Node) -> bool: return n is FighterModel).size(), 1, "and only one")


func test_setup_before_the_tile_is_in_the_tree_builds_once_it_is() -> void:
	ClipLibraries.force_missing = true
	var tile: AnimTile = TILE_SCENE.instantiate() as AnimTile
	tile.setup(_move_with_fallback(&"katana"), &"hunter")
	assert_null(tile.model, "not built yet")
	add_child_autofree(tile)
	assert_not_null(tile.model, "built on entering the tree")
	assert_false(tile.is_still())


# --- the weapon -----------------------------------------------------------------


func test_the_weapon_a_tile_holds() -> void:
	var cases: Dictionary = {
		[&"move", &"katana", &"x"]: &"katana",
		[&"move", &"greatsword", &"x"]: &"greatsword",
		[&"move", &"daggers", &"x"]: &"daggers",
		[&"move", &"fists", &"x"]: &"",
		[&"state", &"states", &"idle_greatsword"]: &"greatsword",
		[&"state", &"states", &"guard_daggers"]: &"daggers",
		[&"state", &"states", &"idle_fists"]: &"",
		[&"state", &"states", &"hit_light"]: &"",
		[&"ult", &"ults", &"moonsplitter_vertical"]: &"katana",
		[&"ult", &"ults", &"impaler"]: &"greatsword",
		[&"ult", &"ults", &"tempest"]: &"daggers",
		[&"source", &"source", &"ual/Sword_Idle"]: &"",
	}
	for key: Array in cases:
		var e: StudioCatalogue.Entry = _entry(key[0], key[1], key[2], [] as Array[String])
		assert_eq(AnimTile.weapon_for(e), cases[key], "%s" % [key])


func test_a_tile_holds_its_weapon() -> void:
	ClipLibraries.force_missing = true
	var katana: AnimTile = _tile(_move_with_fallback(&"katana"))
	assert_eq(katana.model.weapons.size(), 1, "the katana")
	var daggers: AnimTile = _tile(_move_with_fallback(&"daggers"))
	assert_eq(daggers.model.weapons.size(), 2, "a dagger in each hand")
	var bare: AnimTile = _tile(_catalogue.find(StudioCatalogue.KIND_STATE, &"stun"))
	assert_true(bare.model.weapons.is_empty(), "bare hands")


# --- caption and badges -----------------------------------------------------------


func test_the_caption_names_the_animation() -> void:
	ClipLibraries.force_missing = true
	var entry: StudioCatalogue.Entry = _move_with_fallback(&"katana")
	var tile: AnimTile = _tile(entry)
	assert_eq(tile.name_label.text, entry.name)
	assert_eq(tile.id_label.text, String(entry.id))


func test_badge_chips_follow_the_entrys_badges() -> void:
	ClipLibraries.force_missing = true
	var entry: StudioCatalogue.Entry = _move_with_fallback(&"katana")
	entry.badges[&"fallback"] = true
	entry.badges[&"provisional"] = false
	var tile: AnimTile = _tile(entry)
	assert_eq(tile.badge_texts(), PackedStringArray(["fallback"]), "a chip for each set badge")
	entry.badges[&"provisional"] = true
	tile.setup(entry, &"hunter")
	assert_eq(tile.badge_texts(), PackedStringArray(["fallback", "provisional"]), "in the badges' order")


# --- clicking ----------------------------------------------------------------------


func test_a_left_click_opens_the_entry() -> void:
	ClipLibraries.force_missing = true
	var entry: StudioCatalogue.Entry = _move_with_fallback(&"katana")
	var tile: AnimTile = _tile(entry)
	watch_signals(tile)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	tile._gui_input(click)
	assert_signal_emitted_with_parameters(tile, "opened", [entry])
	var other: InputEventMouseButton = InputEventMouseButton.new()
	other.button_index = MOUSE_BUTTON_RIGHT
	other.pressed = true
	tile._gui_input(other)
	assert_signal_emit_count(tile, "opened", 1, "only the left button opens")


# --- on screen ---------------------------------------------------------------------


func test_a_tile_outside_a_scroll_container_counts_as_on_screen() -> void:
	ClipLibraries.force_missing = true
	var tile: AnimTile = _tile(_move_with_fallback(&"katana"))
	assert_true(tile.is_on_screen())


func test_a_hidden_tile_is_off_screen() -> void:
	ClipLibraries.force_missing = true
	var tile: AnimTile = _tile(_move_with_fallback(&"katana"))
	tile.hide()
	assert_false(tile.is_on_screen())
	tile._process(0.1)
	assert_false(tile.is_playing(), "and pauses")
	tile.show()
	tile._process(0.1)
	assert_true(tile.is_playing(), "and plays again when shown")


func test_tiles_scrolled_out_of_a_scroll_container_pause_and_resume() -> void:
	ClipLibraries.force_missing = true
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300.0, 320.0)
	scroll.size = Vector2(300.0, 320.0)
	var column: VBoxContainer = VBoxContainer.new()
	scroll.add_child(column)
	add_child_autofree(scroll)
	var entry: StudioCatalogue.Entry = _move_with_fallback(&"katana")
	var tiles: Array[AnimTile] = []
	for i: int in 4:
		var t: AnimTile = TILE_SCENE.instantiate() as AnimTile
		column.add_child(t)
		t.setup(entry, &"hunter")
		tiles.append(t)
	await wait_process_frames(3)
	assert_true(tiles[0].is_on_screen(), "the first is in view")
	assert_false(tiles[3].is_on_screen(), "the last is below the fold")
	assert_true(tiles[0].is_playing(), "the first plays")
	assert_false(tiles[3].is_playing(), "the last is paused")
	assert_eq(tiles[3].viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED, "and its viewport is off")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await wait_process_frames(3)
	assert_false(tiles[0].is_playing(), "scrolled past, the first pauses")
	assert_true(tiles[3].is_playing(), "the last plays once in view")
	assert_true(tiles[3].is_on_screen())
