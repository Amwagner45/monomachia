class_name MatchAudio
extends Node3D
## The match's sound: plays every rules event's cues (see [SoundBank]) through
## its [SoundPlayer] in played matches (Duel, Training, Watch, Versus) and on
## the results screen. The duel behind the menus stays silent, as in the demo.
## A pause holds the sound and its delayed cues (the round gong waits for the
## resume); a new match, the duel behind the menus and quitting each stop
## everything. It listens to a MatchHost and never changes the rules.
##
## Cues play flat for now; task 19.3 places them in 3D.

## The host to follow. The default is the parent (match_host.tscn).
@export var host_path: NodePath = ^".."

var host: MatchHost
var player: SoundPlayer


func _ready() -> void:
	player = SoundPlayer.new()
	player.name = "Sounds"
	add_child(player)
	# Load the one-shot cues now, so the first hit doesn't wait on a file.
	var cues: Array[StringName] = []
	for cue_name: StringName in SoundBank.CUES:
		if not SoundBank.CUES[cue_name].get("loop", false):
			cues.append(cue_name)
	player.preload_cues(cues)
	if host == null and has_node(host_path):
		var h: Node = get_node(host_path)
		if h is MatchHost:
			bind(h as MatchHost)


func bind(p_host: MatchHost) -> void:
	if host != null:
		host.match_started.disconnect(_on_match_started)
		host.sim_event.disconnect(_on_sim_event)
		host.pause_changed.disconnect(_on_pause_changed)
		host.stopped.disconnect(_on_stopped)
	host = p_host
	host.match_started.connect(_on_match_started)
	host.sim_event.connect(_on_sim_event)
	host.pause_changed.connect(_on_pause_changed)
	host.stopped.connect(_on_stopped)


func _on_match_started(_config: MatchConfig) -> void:
	player.stop_all()


func _on_sim_event(e: Dictionary) -> void:
	if host.attract:
		return
	player.play_event(e)


func _on_pause_changed(paused: bool) -> void:
	player.set_held(paused)


func _on_stopped() -> void:
	player.stop_all()
