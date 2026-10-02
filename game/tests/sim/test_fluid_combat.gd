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


# ------------------------------------------------------------------ block walk

## How far fighter 0 walks in one second holding inp, once up to speed (20
## frames in), against an idle opponent gap m away. It adds up each step, so
## a strafe's orbit counts in full.
static func _walk_one_second(weapon: WeaponDef, gap: float, inp: RawInput) -> float:
	var W: World = H.make_world(weapon, Moves.KATANA, gap)
	var a: Fighter = W.fighters[0]
	for _i: int in 20:
		W.step([inp, H.idle()])
	var walked: float = 0.0
	for _i: int in 60:
		var x: float = a.pos.x
		var z: float = a.pos.z
		W.step([inp, H.idle()])
		walked += JsMath.hypot(a.pos.x - x, a.pos.z - z)
	return walked


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
