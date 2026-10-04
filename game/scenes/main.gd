extends Node
## The game's flow for the playable skeleton (task 22 replaces the menus):
## title -> main menu (Duel, Watch, Controls, Settings, Quit) -> a match -> results (Rematch, Main
## menu), with a pause menu (Resume, Main menu) during play, which Back, Start
## or the pause binding also closes. The pages sit on a ScreenStack: Back on
## a page goes to the page that opened it (the main menu's to the title).
## A computer duel plays behind the title
## and the menus, seen from the orbiting menu camera; its restarts and the
## matches draw their seeds from one sequence (_next_seed).
##
## The music (GameServices): the title, the menus and the results play the
## menu track, a played match the battle track, and the played match's rules
## events reach the music director, so a round call with a fighter on two wins
## switches to match point. The duel behind the menus never changes the track.
## The music stops when these screens go.
##
## Duel is the Rogue with the katana (you) against the Hunter with the
## greatsword (Normal); Watch is katana against daggers, both Normal.
##
## With --smoke on the command line the game plays a Watch match to the
## results at once and quits with its outcome (see SmokeRun).

enum Screen { TITLE, MENU, PLAYING, PAUSED, RESULTS }

## The arena the duel behind the menus and every match are fought in, until
## the arena select (task 22). Tests set the stand-in before the scene enters
## the tree.
@export var arena_id: StringName = MatchConfig.DEFAULT_ARENA

@onready var host: MatchHost = $MatchHost
@onready var ui: CanvasLayer = $Menus

var screen: Screen = Screen.TITLE
var title: TitleScreen
var main_menu: MenuScreen
var pause_menu: MenuScreen
var results_screen: ResultsScreen
var controls_screen: ControlsScreen
var settings_screen: SettingsScreen
## The menus' pages, the open one on top.
var stack: ScreenStack = ScreenStack.new()
## The last match played, for Rematch.
var last_config: MatchConfig
## The demo's per-match seed sequence (see MatchConfig.next_seed).
var _seed: int = 1
## The --smoke run, when the flag is given.
var _smoke: SmokeRun


func _ready() -> void:
	title = TitleScreen.new()
	title.name = "Title"
	ui.add_child(title)
	title.proceed.connect(show_main_menu)

	main_menu = MainMenu.new()
	main_menu.name = "MainMenu"
	main_menu.add_button("Duel", "vs computer", start_duel)
	main_menu.add_button("Watch", "computer vs computer", start_watch)
	main_menu.add_button("Controls", "keys and buttons", show_controls)
	main_menu.add_button("Settings", "picture and sound", show_settings)
	main_menu.add_button("Quit", "to the desktop", quit_game)
	ui.add_child(main_menu)

	pause_menu = MenuScreen.new()
	pause_menu.name = "Pause"
	pause_menu.add_heading("Paused")
	pause_menu.add_button("Resume", "", resume)
	pause_menu.add_button("Main menu", "", quit_to_menu)
	pause_menu.back_pops = false
	pause_menu.back_requested.connect(resume)
	ui.add_child(pause_menu)

	results_screen = ResultsScreen.new()
	results_screen.name = "Results"
	results_screen.rematch.connect(rematch)
	results_screen.main_menu.connect(quit_to_menu)
	ui.add_child(results_screen)

	controls_screen = ControlsScreen.new()
	controls_screen.name = "Controls"
	ui.add_child(controls_screen)
	settings_screen = SettingsScreen.new()
	settings_screen.name = "Settings"
	ui.add_child(settings_screen)
	stack.changed.connect(_on_stack_changed)

	host.match_finished.connect(_on_match_finished)
	host.pause_changed.connect(_on_pause_changed)
	host.sim_event.connect(_on_sim_event)
	# the attract restarts draw from the same seed sequence as the matches
	host.seed_source = _next_seed
	start_attract()
	show_title()
	# _process only ticks a smoke run.
	set_process(false)
	if SmokeRun.requested(OS.get_cmdline_args() + OS.get_cmdline_user_args()):
		_smoke = SmokeRun.new(self)
		_smoke.start()
		set_process(true)


func _exit_tree() -> void:
	GameServices.stop_music()


func _process(_delta: float) -> void:
	if _smoke == null or _smoke.tick() == SmokeRun.Status.RUNNING:
		return
	print(_smoke.report())
	get_tree().quit(_smoke.exit_code())
	_smoke = null
	set_process(false)


func _next_seed() -> int:
	_seed = MatchConfig.next_seed(_seed)
	return _seed


## Follows the stack's top page into `screen` (Back can change it).
func _on_stack_changed(top: MenuPage) -> void:
	if top == title:
		screen = Screen.TITLE
	elif top == main_menu:
		screen = Screen.MENU
	elif top == pause_menu:
		screen = Screen.PAUSED
	elif top == results_screen:
		screen = Screen.RESULTS


# ------------------------------------------------------------------ screens

func start_attract() -> void:
	host.start(_in_arena(MatchConfig.attract(_next_seed())), true)


func show_title() -> void:
	stack.reset([title] as Array[MenuPage])
	GameServices.play_menu_music()


## The main menu, over the title (where its Back goes).
func show_main_menu() -> void:
	stack.reset([title, main_menu] as Array[MenuPage])
	GameServices.play_menu_music()


## Controls and Settings open over the page that chose them; Back returns
## there.
func show_controls() -> void:
	stack.push(controls_screen)


func show_settings() -> void:
	stack.push(settings_screen)


func start_duel() -> void:
	start_match(_in_arena(MatchConfig.default_duel(_next_seed())))


func start_watch() -> void:
	start_match(_in_arena(MatchConfig.default_watch(_next_seed())))


func _in_arena(cfg: MatchConfig) -> MatchConfig:
	cfg.arena_id = arena_id
	return cfg


## Plays a match from a config. A config the host refuses (it reports why)
## goes back to the main menu instead. Returns whether the match started.
func start_match(cfg: MatchConfig) -> bool:
	if not host.start(cfg):
		quit_to_menu()
		return false
	stack.clear()
	last_config = cfg
	screen = Screen.PLAYING
	GameServices.play_match_music()
	return true


func rematch() -> void:
	if last_config == null:
		return
	start_match(last_config.with_seed(_next_seed()))


## Back to the match from the pause menu (Resume, Back). The host's
## pause_changed closes the menu, as it does when Start resumes.
func resume() -> void:
	host.resume()


func quit_to_menu() -> void:
	host.stop()
	start_attract()
	show_main_menu()


func quit_game() -> void:
	get_tree().quit()


func _on_pause_changed(paused: bool) -> void:
	if paused:
		stack.reset([pause_menu] as Array[MenuPage])
	elif screen == Screen.PAUSED:
		stack.clear()
		screen = Screen.PLAYING


func _on_match_finished(results: MatchResults) -> void:
	results_screen.show_results(results)
	stack.reset([results_screen] as Array[MenuPage])
	GameServices.play_menu_music()


func _on_sim_event(e: Dictionary) -> void:
	if not host.attract:
		GameServices.music_event(e)
