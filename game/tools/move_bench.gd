class_name MoveBench
extends RefCounted
## Plays one move on a real fighter, frame by frame on the rules' clock, and
## measures every frame with PoseCheck: the GUT helper for the pose checks,
## and the player behind the contact sheets.
##
## A bench holds a rules World with the fighter facing a defender at the
## duelling distance (PoseCheck.SPACING), and the fighter's FighterView,
## its skeleton stepped by hand. play() starts the move from the guard in a
## fresh world, steps the rules with no input until the move ends, and
## poses and measures the view once per attack frame (steps the rules spend
## in hit-stop don't advance the move, so they are skipped). Reach is
## measured against the defender standing where it stood when the move
## began.
##
## Benches made in a test are freed together by free_all().

## The most rules steps one move may take.
const MAX_STEPS: int = 600

static var _benches: Array[MoveBench] = []

## One frame of a move.
class Step:
	## The attack's frame: 1 on its first step.
	var frame: int = 0
	## &"startup", &"active" or &"recovery", from the move's frame data.
	var phase: StringName = &""
	## The first active frame.
	var contact: bool = false
	var report: PoseCheck.Report


var weapon: WeaponDef
var spacing: float = PoseCheck.SPACING
var world: World
var attacker: Fighter
var defender: Fighter
var view: FighterView
var check: PoseCheck


## A bench for fighter `fighter_id` (a FighterLook id) with `weapon`, its
## view added under `parent`, standing in its guard.
func _init(parent: Node, fighter_id: StringName, p_weapon: WeaponDef, p_spacing: float = PoseCheck.SPACING) -> void:
	weapon = p_weapon
	spacing = p_spacing
	view = FighterView.new()
	view.name = &"MoveBench"
	parent.add_child(view)
	view.setup(fighter_id, 0, weapon.id, 0)
	view.model.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	check = PoseCheck.new(view.model)
	_benches.append(self)
	stand()


## Frees every bench made since the last call: their worlds and views.
static func free_all() -> void:
	for bench: MoveBench in _benches:
		bench.world.dispose()
		if is_instance_valid(bench.view):
			bench.view.free()
	_benches.clear()


## Puts both fighters back at the duelling distance, free and facing each
## other in a fresh world, and shows the fighter in its guard.
func stand() -> void:
	if world != null:
		world.dispose()
	world = World.new(FighterConfig.make(weapon, []), FighterConfig.make(Moves.KATANA, []), 7)
	attacker = world.fighters[0]
	defender = world.fighters[1]
	attacker.pos = V3.make(0.0, 0.0, -spacing / 2.0)
	defender.pos = V3.make(0.0, 0.0, spacing / 2.0)
	attacker.yaw = 0.0
	defender.yaw = PI
	attacker.set_state(&"free")
	defender.set_state(&"free")
	_show()


## The fighter's pose now, with the defender where it stands (await it).
func frame() -> PoseCheck.Frame:
	return await _frame(_feet(defender))


## Plays move `move_id` from the guard, in a fresh world: one Step per
## attack frame, up to the frame the move ends on (await it: each frame
## waits for the skeleton to update).
func play(move_id: StringName) -> Array[Step]:
	stand()
	var feet: Vector3 = _feet(defender)
	var out: Array[Step] = []
	if not attacker.start_attack(move_id):
		push_error("MoveBench.play: %s has no move %s" % [weapon.id, move_id])
		return out
	var def: AttackDef = attacker.atk.def
	var last: int = 0
	for i: int in MAX_STEPS:
		world.step([RawInput.empty(), RawInput.empty()])
		if attacker.state != &"attack" or attacker.atk == null or attacker.atk.def != def:
			break
		if attacker.atk.frame == last:
			continue
		last = attacker.atk.frame
		_show()
		var s: Step = Step.new()
		s.frame = last
		s.phase = &"startup" if last <= def.startup else (&"active" if last <= def.startup + def.active else &"recovery")
		s.contact = last == def.startup + 1
		s.report = check.measure(await _frame(feet), s.contact)
		out.append(s)
	return out


## A move's frames on one line: the worst of each measure, and how many
## frames fail.
static func summary(move_id: StringName, steps: Array[Step]) -> String:
	var bend: float = 0.0
	var deviation: float = 0.0
	var straightest: float = 0.0
	var gap: float = INF
	var near: String = ""
	var knee: float = INF
	var reach: float = 0.0
	var contact: String = "-"
	var failing: int = 0
	var kinds: Dictionary[String, int] = {}
	for s: Step in steps:
		var r: PoseCheck.Report = s.report
		for side: String in r.wrists:
			if absf(r.wrists[side].x) > absf(bend):
				bend = r.wrists[side].x
			if absf(r.wrists[side].y) > absf(deviation):
				deviation = r.wrists[side].y
		for side: String in r.elbows:
			straightest = maxf(straightest, r.elbows[side])
		if s.contact:
			var e: PackedStringArray = []
			for side: String in r.elbows:
				e.append("%s %.0f" % [side.left(1), r.elbows[side]])
			contact = " ".join(e)
		if r.blade_gap < gap:
			gap = r.blade_gap
			near = r.blade_near
		for side: String in r.knees:
			knee = minf(knee, r.knees[side])
		if s.phase == &"active":
			reach = maxf(reach, r.reach)
		var fails: PackedStringArray = r.failures()
		if not fails.is_empty():
			failing += 1
		for f: String in fails:
			var kind: String = f.get_slice(" ", 0) + " " + f.get_slice(" ", 1) if not f.begins_with("blade") else "blade"
			kinds[kind] = kinds.get(kind, 0) + 1
	return "%-9s %3d fr  wrist %+4.0f/%+4.0f  elbow at contact %-11s most %3.0f  blade %5.1f cm (%s)  knee %+5.1f cm  reach %4.1f cm  fails %d/%d %s" % [
		move_id, steps.size(), bend, deviation, contact, straightest, gap * 100.0, near, knee * 100.0, reach * 100.0,
		failing, steps.size(), str(kinds) if not kinds.is_empty() else ""]


## Shows the fighter where the rules have it, at the end of the step.
func _show() -> void:
	view.update_from(attacker, _feet(attacker), attacker.yaw, 1.0, 1.0 / 60.0, 0.0)


func _frame(feet: Vector3) -> PoseCheck.Frame:
	var frame: PoseCheck.Frame = await PoseCheck.frame_of(view.model)
	frame.defender = view.model.skeleton.global_transform.affine_inverse() * feet
	return frame


static func _feet(f: Fighter) -> Vector3:
	return Vector3(f.pos.x, f.pos.y, f.pos.z)
