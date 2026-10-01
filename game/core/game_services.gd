extends Node
## The GameServices autoload: what the whole game shares, kept for as long as
## the game runs.
##
## - one ControlProfiles (the saved controls profiles, user://controls.cfg);
## - one InputDevices, which every match samples, with its InputFeed in the
##   tree so labels follow the last device used, even in menus (the shared
##   input home that task 21 asked for; see the recipe in input_devices.gd);
## - the match being played, which it pauses when the window loses focus
##   (spec story 10).
##
## A match host registers itself with begin_match() while a match is played
## and calls end_match() when it stops. No class_name: the autoload's name is
## the global.

var profiles: ControlProfiles
var input: InputDevices
var feed: InputFeed

## The host of the match being played, or null. Anything with
## `is_playing() -> bool` and `pause()`.
var _match: Node = null


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	profiles = ControlProfiles.load_from()
	input = InputDevices.new()
	feed = InputFeed.new(input)
	feed.name = "InputFeed"


func _ready() -> void:
	add_child(feed)
	feed.focus_lost.connect(_on_focus_lost)


## A match host starts being played (Duel, Training, Watch or Versus; not the
## duel behind the menus).
func begin_match(host: Node) -> void:
	_match = host


## The host stops being played (quit to menu, or freed). Ignored for any other
## host.
func end_match(host: Node) -> void:
	if _match == host:
		_match = null


func current_match() -> Node:
	if _match != null and not is_instance_valid(_match):
		_match = null
	return _match


func _on_focus_lost() -> void:
	var host: Node = current_match()
	if host != null and host.call("is_playing"):
		host.call("pause")
