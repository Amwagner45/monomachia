extends Node
## Screenshot scenes for the menu screens of tasks 22.6-22.10, over the duel
## behind the menus. Each .tscn next to this script picks one `shot`; render
## one with
##   node scripts/godot.mjs shots res://tools/shot_scenes/<name>.tscn <out.png>
##
## "settings" is the Settings screen; "controls_kb" and "controls_pad" the
## Controls table's two tabs (the controller tab with a PlayStation pad
## plugged in a fake device state, so its names show); "results_defeat" and
## "results_watch" the results of a played Duel the player lost and of a
## Watch match; "loadout_<weapon>" the fighter select on your side of a Duel
## with that weapon, and "loadout_random" on the opponent's side left to
## Random. The screens save to throwaway paths, never the player's.

@export_enum(
	"settings", "controls_kb", "controls_pad", "results_defeat", "results_watch",
	"loadout_katana", "loadout_greatsword", "loadout_daggers", "loadout_random",
) var shot: String = "settings"
## Frames to let the renderer settle before the capture.
@export var settle_frames: int = 10

var main: Node
var host: MatchHost
var _ready_flag: bool = false


func shot_frames() -> int:
	return settle_frames


func shot_ready() -> bool:
	return _ready_flag


func _ready() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	host = main.get_node("MatchHost")
	host.auto_run = false
	var stack: ScreenStack = main.get("stack")
	var ui: CanvasLayer = main.get_node("Menus")
	match shot:
		"settings":
			_menus_behind()
			var s: SettingsScreen = SettingsScreen.new(GameSettings.new(), "user://shot_settings.cfg")
			ui.add_child(s)
			stack.push(s)
		"controls_kb", "controls_pad":
			_menus_behind()
			var state: FakeDeviceState = FakeDeviceState.new()
			var input: InputDevices = InputDevices.new(state)
			if shot == "controls_pad":
				state.plug_pad(0, "DualSense Wireless Controller", {"vendor_id": 0x054C})
				var press: InputEventJoypadButton = InputEventJoypadButton.new()
				press.button_index = JOY_BUTTON_A
				press.pressed = true
				input.note_event(press)
			var c: ControlsScreen = ControlsScreen.new(ControlProfiles.new(), "user://shot_controls.cfg", input)
			ui.add_child(c)
			stack.push(c)
		"loadout_katana", "loadout_greatsword", "loadout_daggers", "loadout_random":
			_menus_behind()
			main.call("open_select", MatchConfig.DUEL)
			var select: FighterSelect = main.get("select")
			if shot == "loadout_random":
				MatchSelection.set_random_weapon(select.draft, 1, true)
				select.show_side(1)
			else:
				MatchSelection.set_weapon(select.draft, 0, StringName(shot.trim_prefix("loadout_")))
				select.show_side(0)
		"results_defeat", "results_watch":
			var cfg: MatchConfig = MatchConfig.default_duel(7) if shot == "results_defeat" else MatchConfig.default_watch(7)
			cfg.arena_id = main.get("arena_id")
			main.call("start_match", cfg)
			while not host.is_finished():
				host.step(1)
			host.step(30)
	var view: MatchView = host.get_node("View")
	view.snap_camera()
	view.set_process(false)
	_ready_flag = true


## The main menu over the duel, as the screens open from it.
func _menus_behind() -> void:
	main.call("show_main_menu")
	host.step(420)
