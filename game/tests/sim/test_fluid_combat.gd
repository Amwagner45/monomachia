extends GutTest
## The fluid combat rules that changed the demo's on purpose (plan task 8),
## one section per rule. Expected numbers come from the spec, not the code.

const H := preload("res://tests/sim/sim_helpers.gd")
## toBeCloseTo's default precision (2 digits), as the neighbouring tests use
const CLOSE: float = 0.005

## The spec's arena: a 15 m wall.
const WALL: float = 15.0
## Fighters' centres stop a fighter's radius (0.42 m) inside the wall.
const CENTRE_LIMIT: float = WALL - 0.42
## The Impaler's dash ends 0.7 m inside the wall.
const IMPALER_STOP: float = WALL - 0.7
## Dropped weapons bounce off a ring 0.8 m inside the wall.
const BOUNCE_RING: float = WALL - 0.8
## The Impaler dashes 24 m/s: 0.4 m a frame.
const DASH_STEP: float = 0.4

## The spec's blocking walk: 60% of running speed.
const BLOCK_WALK: float = 0.6
## Running speeds (m/s), kept from the demo (story 12), before the weapon's
## speed: the Greatsword moves 10% slower and the Daggers 12% faster.
const RUN_FORWARD: float = 3.9
const RUN_STRAFE: float = 3.5
const RUN_BACK: float = 3.0
const SPRINT: float = 7.2

## The spec's momentum carry: an attack keeps half the speed it starts at.
const MOMENTUM_KEEP: float = 0.5
## Kept from the demo: a running jump flies at strafing speed, and an attack
## on the ground brakes by a fifth of its speed each step after the first.
const JUMP_FLIGHT: float = 3.5
const ATTACK_BRAKE: float = 0.8


func after_each() -> void:
	H.dispose_all()


## How far p is from the arena's centre, on the ground (in doubles: Godot's
## Vector2 is 32-bit).
static func _r(p: V3) -> float:
	return JsMath.hypot(p.x, p.z)


# ------------------------------------------------------------------ arena

func test_backing_away_stops_a_fighters_centre_at_the_15_m_wall() -> void:
	var W: World = H.make_world(Moves.KATANA, Moves.KATANA, 2.0)
	var a: Fighter = W.fighters[0]
	var furthest: float = 0.0
	for _i: int in 600:
		W.step([H.move(0.0, -1.0), H.idle()])
		furthest = maxf(furthest, _r(a.pos))
	assert_gt(furthest, 12.0, "past the demo's 11.08 m")
	assert_almost_eq(furthest, CENTRE_LIMIT, 1e-9, "no further than the wall less a fighter's radius")
	assert_almost_eq(_r(a.pos), CENTRE_LIMIT, 1e-9, "held against the wall")


func test_a_weapon_dropped_near_the_wall_bounces_off_it_and_rests_inside() -> void:
	var W: World = H.make_world()
	var victim: Fighter = W.fighters[1]
	victim.pos = V3.make(0.0, 0.0, 14.0)
	W.fighters[0].pos = V3.make()
	W.spawn_dropped_weapon(victim, W.fighters[0])
	var furthest: float = 0.0
	for _i: int in 300:
		W.step([H.idle(), H.idle()])
		furthest = maxf(furthest, _r(W.weapons[0].pos))
	var w: DroppedWeapon = W.weapons[0]
	assert_true(w.grounded, "it comes to rest")
	assert_almost_eq(furthest, BOUNCE_RING, 1e-9, "it flies out to its bounce ring and no further")
	assert_lt(_r(w.pos), BOUNCE_RING - 1.0, "it bounces back off the ring and rests well inside")


func test_the_impaler_dash_stops_0_7_m_inside_the_wall() -> void:
	# The target hangs 2 m up, beyond where the dash should stop: the blade
	# never reaches it, and the dash never passes it.
	var W: World = H.make_world(Moves.GREATSWORD, Moves.KATANA)
	var a: Fighter = W.fighters[0]
	var b: Fighter = W.fighters[1]
	a.pos = V3.make()
	a.hp = 20.0
	b.pos = V3.make(0.0, 2.0, 14.5)
	var dash_frames: int = 0
	var stop_r: float = -1.0
	for i: int in 120:
		b.pos.y = 2.0
		b.vel.y = 0.0
		W.step([H.btn(Btn.ULTIMATE) if i == 0 else H.idle(), H.idle()])
		if a.state == &"ult" and a.ult.phase == &"dash":
			dash_frames = a.ult.pf
		elif dash_frames > 0 and stop_r < 0.0:
			stop_r = _r(a.pos)
	assert_gt(dash_frames, 0, "the Impaler dashed")
	# the last dash frame seen is 39 when its 40 frames run out
	assert_lt(dash_frames, 39, "the stop ends the dash before its frames run out")
	assert_between(stop_r, IMPALER_STOP, IMPALER_STOP + DASH_STEP, "within one dash step past the stop, 0.7 m inside the wall")
	assert_lt(stop_r, CENTRE_LIMIT, "short of the wall itself, so the stop ended it, not the wall")


func test_a_vertical_moonsplitter_hits_across_the_widest_gap() -> void:
	# two fighters with their backs to opposite walls: 29.16 m apart
	var W: World = H.make_world(Moves.KATANA, Moves.KATANA, 2.0 * CENTRE_LIMIT)
	var a: Fighter = W.fighters[0]
	var b: Fighter = W.fighters[1]
	a.hp = 20.0
	var r: H.Rec = H.Rec.new()
	var gap_at_release: float = -1.0
	for i: int in 150:
		W.step([H.btn(Btn.ULTIMATE) if i == 0 else H.idle(), H.idle()])
		r.collect(W)
		if gap_at_release < 0.0 and r.has(&"ultWave"):
			gap_at_release = SimMath.dist2(a.pos, b.pos)
	assert_eq(r.find(&"ultWave").get("kind"), &"vertical")
	assert_almost_eq(gap_at_release, 2.0 * CENTRE_LIMIT, 1e-9, "the fighters stand 29.16 m apart")
	assert_almost_eq(b.hp, 70.0, CLOSE, "the wave reaches and hits")


# ------------------------------------------------------------------ helpers

## Fighter 0 on each step of a run: how far it moved along the ground, and the
## attack it was in afterwards (&"" outside one).
class FighterSteps:
	var moved: PackedFloat64Array = []
	var attack: Array[StringName] = []

	## The step that started attack id, or -1.
	func start_of(id: StringName) -> int:
		for i: int in attack.size():
			if attack[i] == id and (i == 0 or attack[i - 1] != id):
				return i
		return -1

	## How far it moved from step from on, adding up each step (so an orbit
	## counts in full).
	func walked(from: int = 0) -> float:
		var total: float = 0.0
		for d: float in moved.slice(from):
			total += d
		return total


## Runs n steps with fighter 0's input from p0 (step index -> RawInput) and an
## idle Katana opponent gap m away.
static func _record(weapon: WeaponDef, gap: float, n: int, p0: Callable) -> FighterSteps:
	var W: World = H.make_world(weapon, Moves.KATANA, gap)
	var a: Fighter = W.fighters[0]
	var s := FighterSteps.new()
	for i: int in n:
		var x: float = a.pos.x
		var z: float = a.pos.z
		W.step([p0.call(i), H.idle()])
		s.moved.append(JsMath.hypot(a.pos.x - x, a.pos.z - z))
		s.attack.append(a.atk.def.id if a.state == &"attack" and a.atk != null else &"")
	return s


# ------------------------------------------------------------------ block walk

## How far fighter 0 walks in one second holding inp, once up to speed (20
## steps in), against an idle opponent gap m away.
static func _walk_one_second(weapon: WeaponDef, gap: float, inp: RawInput) -> float:
	return _record(weapon, gap, 80, func(_i: int) -> RawInput: return inp).walked(20)


func test_walking_forward_while_blocking_is_60_percent_of_running() -> void:
	# 8 m apart, so the walker ends more than 4 m short of the opponent
	var weapon_speed: Dictionary[StringName, float] = {&"katana": 1.0, &"greatsword": 0.9, &"daggers": 1.12}
	for id: StringName in weapon_speed:
		var expected: float = RUN_FORWARD * weapon_speed[id] * BLOCK_WALK
		var walked: float = _walk_one_second(Moves.WEAPONS[id], 8.0, H.move(0.0, 1.0, Btn.BLOCK))
		assert_almost_eq(walked, expected, 1e-6, "%s walks forward %.4f m/s blocking" % [id, expected])


func test_strafing_and_backing_away_while_blocking_are_60_percent_of_running() -> void:
	# The strafe orbits the opponent 6 m away (strafes keep their distance
	# inside 9 m). Each step is pulled back onto the circle, which shortens the
	# second's walk by about 3e-5 m, hence the looser tolerance.
	var strafed: float = _walk_one_second(Moves.KATANA, 6.0, H.move(1.0, 0.0, Btn.BLOCK))
	assert_almost_eq(strafed, RUN_STRAFE * BLOCK_WALK, 1e-4, "strafing")
	var backed: float = _walk_one_second(Moves.KATANA, 6.0, H.move(0.0, -1.0, Btn.BLOCK))
	assert_almost_eq(backed, RUN_BACK * BLOCK_WALK, 1e-6, "backing away")


func test_holding_block_stops_a_sprint() -> void:
	# 20 m apart, so the sprint (about 9 m in all) never reaches the opponent
	var sprint: float = _walk_one_second(Moves.KATANA, 20.0, H.move(0.0, 1.0, Btn.SPRINT))
	var blocking: float = _walk_one_second(Moves.KATANA, 20.0, H.move(0.0, 1.0, Btn.SPRINT, Btn.BLOCK))
	assert_almost_eq(sprint, SPRINT, 1e-6, "the sprint button sprints")
	assert_almost_eq(blocking, RUN_FORWARD * BLOCK_WALK, 1e-6, "blocking walks at the blocking walk instead")


# ------------------------------------------------------------------ momentum
# Each run starts 10 m from the opponent, so nobody meets.

func test_a_light_thrown_at_a_run_keeps_half_the_running_speed() -> void:
	var s: FighterSteps = _record(Moves.KATANA, 10.0, 40, func(i: int) -> RawInput:
		return H.move(0.0, 1.0, Btn.LIGHT) if i == 30 else H.move(0.0, 1.0))
	var i: int = s.start_of(&"k_l1")
	assert_eq(i, 30, "Right Cut starts on the press")
	assert_almost_eq(s.moved[i - 1], RUN_FORWARD / 60.0, 1e-9, "running at full speed the step before")
	assert_almost_eq(s.moved[i], MOMENTUM_KEEP * s.moved[i - 1], 1e-12, "the step it starts on keeps exactly half")


func test_a_light_thrown_at_a_run_carries_the_attacker_further_than_one_thrown_standing() -> void:
	var standing: FighterSteps = _record(Moves.KATANA, 10.0, 60, func(i: int) -> RawInput:
		return H.btn(Btn.LIGHT) if i == 0 else H.idle())
	var running: FighterSteps = _record(Moves.KATANA, 10.0, 90, func(i: int) -> RawInput:
		if i < 30:
			return H.move(0.0, 1.0)
		return H.btn(Btn.LIGHT) if i == 30 else H.idle())
	assert_eq(standing.start_of(&"k_l1"), 0, "the standing Right Cut starts on the press")
	assert_eq(running.start_of(&"k_l1"), 30, "the running one too")
	# The kept speed for one step, then braked each step after:
	# 1.95 m/s x 1/60 s x (1 + 0.8 + 0.8^2 + ...) = 1.95 / 12 m. The cut ends
	# after 31 steps, which leaves 0.1% of the series out.
	var expected: float = MOMENTUM_KEEP * RUN_FORWARD / 60.0 / (1.0 - ATTACK_BRAKE)
	assert_almost_eq(running.walked(30) - standing.walked(), expected, 0.0005, "the same cut, 16 cm further")


func test_a_jump_attack_keeps_all_its_speed() -> void:
	# the stick is let go in the air, so the flight is straight
	var s: FighterSteps = _record(Moves.KATANA, 10.0, 40, func(i: int) -> RawInput:
		if i < 30:
			return H.move(0.0, 1.0, Btn.JUMP) if i == 29 else H.move(0.0, 1.0)
		return H.btn(Btn.LIGHT) if i == 34 else H.idle())
	var i: int = s.start_of(&"k_jl")
	assert_eq(i, 34, "Aerial Cut starts on the press")
	assert_almost_eq(s.moved[i - 1], JUMP_FLIGHT / 60.0, 1e-9, "flying at the jump's speed the step before")
	assert_almost_eq(s.moved[i], s.moved[i - 1], 1e-12, "the step it starts on keeps it all")


func test_a_hop_attack_keeps_all_its_speed() -> void:
	# Leaping Cleave, the Katana's sprint heavy, hops forward
	var s: FighterSteps = _record(Moves.KATANA, 10.0, 40, func(i: int) -> RawInput:
		return H.move(0.0, 1.0, Btn.SPRINT, Btn.HEAVY) if i == 30 else H.move(0.0, 1.0, Btn.SPRINT))
	var i: int = s.start_of(&"k_sh")
	assert_eq(i, 30, "Leaping Cleave starts on the press")
	assert_almost_eq(s.moved[i - 1], SPRINT / 60.0, 1e-9, "sprinting the step before")
	assert_almost_eq(s.moved[i], s.moved[i - 1], 1e-12, "the step it starts on keeps it all")
