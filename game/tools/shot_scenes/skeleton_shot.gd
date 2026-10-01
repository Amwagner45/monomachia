extends Node
## Screenshot scenes for the playable skeleton (task 6). Each .tscn next to
## this script picks one `shot`; render one with
##   node scripts/godot.mjs shots res://tools/shot_scenes/<name>.tscn <out.png>
##
## Gameplay shots run a deterministic computer-against-computer duel (Rogue
## with katana against Hunter with greatsword, both Hard, seed SEED), step it
## without the clock to a chosen moment, snap the camera and hold still: the
## view and the HUD stop processing once snapped, so the wall clock (idle bob,
## shake decay, the menu orbit) can't change the picture between runs.

const SEED: int = 7

@export_enum("round_start", "exchange", "parry", "watch", "dropped", "results", "main_menu") var shot: String = "round_start"
## Frames to let the renderer settle before the capture.
@export var settle_frames: int = 10

var host: MatchHost
var main: Node
var _ready_flag: bool = false
var _parried: bool = false
var _katana_hit: bool = false


func shot_frames() -> int:
	return settle_frames


func shot_ready() -> bool:
	return _ready_flag


func _ready() -> void:
	match shot:
		"round_start":
			_gameplay(MatchConfig.DUEL)
			host.step(40)
		"exchange":
			_gameplay(MatchConfig.DUEL)
			_step_until(_exchanging, 20000, 300)
		"parry":
			_gameplay(MatchConfig.DUEL)
			host.sim_event.connect(_on_event)
			_step_until(func() -> bool: return _parried, 40000, 0)
		"watch":
			# the katana (side 0) landing a cut, two steps on: the hit flash,
			# the defender reeling, held by the hit-stop
			_gameplay(MatchConfig.WATCH)
			host.step(600)
			host.sim_event.connect(_on_event)
			_step_until(func() -> bool: return _katana_hit, 40000, 0)
			host.step(2)
		"dropped":
			# the first weapon knocked out of a hand, lying on the floor
			# under its marker
			_gameplay(MatchConfig.WATCH)
			_step_until(_weapon_down, 200000, 0)
		"results":
			_main()
			main.call("start_match", _config(MatchConfig.DUEL))
			_step_until(func() -> bool: return host.is_finished(), 200000, 0)
			host.step(30)
		"main_menu":
			_main()
			main.call("show_main_menu")
			host.step(420)
	var view: MatchView = host.get_node("View")
	view.snap_camera()
	if shot == "dropped":
		_frame_dropped(view.camera)
	var hud: MatchHud = host.get_node("Hud")
	hud.snap_bars()
	view.set_process(false)
	hud.set_process(false)
	_ready_flag = true


func _config(mode: StringName) -> MatchConfig:
	return MatchConfig.make(
		mode,
		MatchSide.computer(&"rogue", &"katana", 0, &"hard"),
		MatchSide.computer(&"hunter", &"greatsword", 1, &"hard"),
		SEED,
	)


func _gameplay(mode: StringName) -> void:
	host = (load("res://view/match/match_host.tscn") as PackedScene).instantiate()
	host.auto_run = false
	add_child(host)
	host.start(_config(mode))


func _main() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	host = main.get_node("MatchHost")
	host.auto_run = false


## Steps until cond() holds (checked after at least min_steps), at most limit steps.
func _step_until(cond: Callable, limit: int, min_steps: int) -> void:
	var n: int = 0
	while n < limit:
		host.step(1)
		n += 1
		if n >= min_steps and cond.call():
			return
	push_warning("skeleton_shot: %s not reached in %d steps" % [shot, limit])


## Fighters close, the opponent (side 1, facing the camera) one frame before
## a slash or an overhead lands.
func _exchanging() -> bool:
	var a: Fighter = host.fighter(0)
	var b: Fighter = host.fighter(1)
	if Vector2(a.pos.x - b.pos.x, a.pos.z - b.pos.z).length() > 3.0:
		return false
	if b.state != &"attack" or b.atk == null or b.atk.charging:
		return false
	var d: AttackDef = b.atk.def
	return (d.type == &"slash" or d.type == &"overhead") and b.atk.frame == d.startup


## Puts the camera 3.5 m beyond the grounded weapon, looking past it at the
## fighters, so the blade, its marker and the fight share the frame.
func _frame_dropped(camera: Camera3D) -> void:
	for w: DroppedWeapon in host.world.weapons:
		if not w.grounded:
			continue
		var at := Vector3(w.pos.x, 0.0, w.pos.z)
		var mid: Vector3 = (host.display_position(0) + host.display_position(1)) * 0.5
		mid.y = 0.0
		var away: Vector3 = (at - mid).normalized() if at.distance_to(mid) > 0.1 else Vector3.BACK
		camera.global_position = at + away * 3.5 + Vector3(0.0, 1.7, 0.0)
		camera.look_at(at.lerp(mid, 0.35) + Vector3(0.0, 0.5, 0.0))
		return


func _weapon_down() -> bool:
	for w: DroppedWeapon in host.world.weapons:
		if w.grounded:
			return true
	return false


func _on_event(e: Dictionary) -> void:
	if e["t"] == &"parry":
		_parried = true
	elif e["t"] == &"hit" and int(e["attacker"]) == 0 and not _katana_hit:
		_katana_hit = true
