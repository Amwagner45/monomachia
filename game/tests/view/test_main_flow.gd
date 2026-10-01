extends GutTest
## The game's flow in main.tscn, headless and without the clock: title over
## the duel behind the menus -> main menu -> Duel against the computer -> the
## results -> Rematch or Main menu, and pause during play.

const MainScript := preload("res://scenes/main.gd")

var main: Node
var host: MatchHost


func before_each() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	host = main.get_node("MatchHost")
	host.auto_run = false


func _screen() -> int:
	return int(main.get("screen"))


func test_it_opens_on_the_title_over_a_computer_duel() -> void:
	assert_eq(_screen(), MainScript.Screen.TITLE)
	assert_true((main.get("title") as Control).visible)
	assert_true(host.is_started())
	assert_true(host.attract, "the duel behind the menus")
	assert_false(host.is_playing())


func test_the_title_leads_to_the_main_menu() -> void:
	main.call("show_main_menu")
	assert_eq(_screen(), MainScript.Screen.MENU)
	var menu: MenuScreen = main.get("main_menu")
	assert_true(menu.visible)
	var labels: Array[String] = []
	for b: Button in menu.buttons:
		labels.append(b.text.get_slice("\n", 0))
	assert_eq(labels, ["Duel", "Watch", "Quit"] as Array[String])


func test_a_duel_runs_from_the_menu_to_the_results_and_back() -> void:
	main.call("show_main_menu")
	main.call("start_duel")
	assert_eq(_screen(), MainScript.Screen.PLAYING)
	assert_false(host.attract)
	assert_true(host.is_playing())
	assert_eq(host.config.mode, MatchConfig.DUEL)
	assert_eq(host.config.sides[0].fighter_id, &"rogue")
	assert_eq(host.config.sides[0].weapon_id, &"katana")
	assert_true(host.config.sides[0].is_human())
	assert_eq(host.config.sides[1].fighter_id, &"hunter")
	assert_eq(host.config.sides[1].weapon_id, &"greatsword")
	assert_eq(host.config.sides[1].difficulty, &"normal")
	# nobody touches the controls: the computer wins
	var steps: int = 0
	while _screen() != MainScript.Screen.RESULTS and steps < 60 * 60 * 12:
		host.step(1)
		steps += 1
	assert_eq(_screen(), MainScript.Screen.RESULTS)
	var results: ResultsScreen = main.get("results_screen")
	assert_true(results.visible)
	assert_eq(results.results.winner, 1)
	assert_eq(results.results.wins[1], 3)
	assert_eq(results.results.title(), "Defeat")
	var seed_before: int = host.config.world_seed
	main.call("rematch")
	assert_eq(_screen(), MainScript.Screen.PLAYING)
	assert_true(host.is_playing())
	assert_ne(host.config.world_seed, seed_before, "a rematch takes a new seed")
	assert_eq(host.config.sides[1].weapon_id, &"greatsword", "the same loadouts")
	main.call("quit_to_menu")
	assert_eq(_screen(), MainScript.Screen.MENU)
	assert_true(host.attract)


func test_watch_starts_computer_against_computer() -> void:
	main.call("start_watch")
	assert_eq(host.config.mode, MatchConfig.WATCH)
	assert_eq(host.config.human_count(), 0)
	assert_eq((host.get_node("View") as MatchView).camera.mode, CameraRig.Mode.WATCH)


func test_pause_opens_the_pause_menu_and_resume_closes_it() -> void:
	main.call("start_duel")
	host.step(30)
	host.pause()
	assert_eq(_screen(), MainScript.Screen.PAUSED)
	assert_true((main.get("pause_menu") as MenuScreen).visible)
	assert_eq(host.step(5), 0, "nothing moves while paused")
	main.call("resume")
	assert_eq(_screen(), MainScript.Screen.PLAYING)
	assert_false((main.get("pause_menu") as MenuScreen).visible)
	assert_eq(host.step(5), 5)


func test_resume_from_the_host_closes_the_pause_menu() -> void:
	# Start or the pause binding resumes in the host (see test_match_host)
	main.call("start_duel")
	host.pause()
	host.resume()
	assert_eq(_screen(), MainScript.Screen.PLAYING)
	assert_false((main.get("pause_menu") as MenuScreen).visible)


# ------------------------------------------------------------------ seeds

func test_attract_restarts_and_matches_share_one_seed_sequence() -> void:
	var attract_seed: int = host.config.world_seed
	assert_true(host.seed_source.is_valid(), "main hands the host its sequence")
	var restart_seed: int = int(host.seed_source.call())
	assert_ne(restart_seed, attract_seed, "an attract restart takes the next seed")
	main.call("start_duel")
	assert_ne(host.config.world_seed, attract_seed, "the Duel doesn't replay the attract duel's seed")
	assert_ne(host.config.world_seed, restart_seed, "nor the restart's")


# ------------------------------------------------------------------ a bad config

func test_a_config_the_host_refuses_goes_back_to_the_main_menu() -> void:
	main.call("start_duel")
	var bad: MatchConfig = MatchConfig.default_duel()
	bad.mode = &"ranked"
	assert_false(main.call("start_match", bad))
	assert_push_error("bad match config")
	assert_eq(_screen(), MainScript.Screen.MENU)
	assert_true((main.get("main_menu") as MenuScreen).visible)
	assert_true(host.attract, "the duel behind the menus runs")


# ------------------------------------------------------------------ controllers

func _press_pad(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var e: InputEventJoypadButton = InputEventJoypadButton.new()
		e.button_index = button
		e.pressed = pressed
		get_viewport().push_input(e)


func _focus_first(menu_name: String) -> MenuScreen:
	var menu: MenuScreen = main.get(menu_name)
	menu.buttons[0].grab_focus()
	return menu


func test_a_controller_drives_the_menus() -> void:
	main.call("show_main_menu")
	_focus_first("main_menu")
	_press_pad(JOY_BUTTON_B)
	assert_eq(_screen(), MainScript.Screen.TITLE, "B on the main menu goes back to the title")
	_press_pad(JOY_BUTTON_A)
	assert_eq(_screen(), MainScript.Screen.MENU, "any button on the title goes on")
	_focus_first("main_menu")
	_press_pad(JOY_BUTTON_A)
	assert_eq(_screen(), MainScript.Screen.PLAYING, "A chooses Duel")
	assert_eq(host.config.mode, MatchConfig.DUEL)
	host.pause()
	_focus_first("pause_menu")
	_press_pad(JOY_BUTTON_A)
	assert_eq(_screen(), MainScript.Screen.PLAYING, "A on Resume")
	host.pause()
	_press_pad(JOY_BUTTON_B)
	assert_eq(_screen(), MainScript.Screen.PLAYING, "B on the pause menu resumes")
	assert_false(host.is_paused())


func test_back_on_the_results_goes_to_the_main_menu() -> void:
	main.call("start_duel")
	host.step(Match.INTRO_FRAMES + 10)
	host.match_finished.emit(host.results())
	assert_eq(_screen(), MainScript.Screen.RESULTS)
	_focus_first("results_screen")
	_press_pad(JOY_BUTTON_B)
	assert_eq(_screen(), MainScript.Screen.MENU)
	assert_true(host.attract)


func test_the_input_feed_sees_the_presses_the_menus_take() -> void:
	var input: InputDevices = get_tree().root.get_node("GameServices").get("input")
	var before: InputDevices.LastUsed = input.last_used
	input.last_used = InputDevices.LastUsed.KEYBOARD
	main.call("show_main_menu")
	_press_pad(JOY_BUTTON_B)
	var seen: InputDevices.LastUsed = input.last_used
	input.last_used = before
	assert_eq(_screen(), MainScript.Screen.TITLE, "the menu took B")
	assert_eq(seen, InputDevices.LastUsed.PAD, "and the feed saw it: labels follow the controller")
