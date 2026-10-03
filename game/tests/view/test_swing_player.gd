extends GutTest
## Swing playback (plan task 14.10): a move with a swing places the weapon
## exactly where the rules' swing has it at the frame shown, the arms reach
## for it, and the root stays the rules'. The swings are synthetic
## (tests/sim/swing_fixtures.gd) on fresh copies of the weapons.

const SF := preload("res://tests/sim/swing_fixtures.gd")
## How close the shown weapon must be to the sample: 1 mm and 0.5°.
const NEAR_POS: float = 0.001
const NEAR_DEG: float = 0.5


func after_each() -> void:
	SimHelpers.dispose_all()


func _view(fighter_id: StringName, weapon: WeaponDef) -> FighterView:
	var v: FighterView = FighterView.new()
	add_child_autofree(v)
	v.setup(fighter_id, 0, weapon.id, 0)
	v.model.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	return v


## A copy of weapon `id` whose light start has a level slash.
static func _slashing(id: StringName) -> WeaponDef:
	var start: StringName = (Moves.WEAPONS[id] as WeaponDef).light_start
	var move: AttackDef = (Moves.WEAPONS[id] as WeaponDef).moves[start]
	return SF.weapon(id, {start: SF.level_slash(move)} as Dictionary[StringName, Swing])


## How far the shown weapon `index` is from `s` (a hand track's sample):
## the grip's miss (m) and the worst of the blade's and the edge's turn
## (degrees), worked from the sample by hand, not through SwingPlayer.
func _miss(v: FighterView, index: int, s: Swing.Sample) -> Vector2:
	var xf: Transform3D = v.model.weapons[index].transform
	var grip: Vector3 = Vector3(-s.grip.x, s.grip.y, s.grip.z)
	var blade: Vector3 = Vector3(-s.blade.x, s.blade.y, s.blade.z)
	var edge: Vector3 = Vector3(-s.edge.x, s.edge.y, s.edge.z)
	var turn: float = maxf(xf.basis.y.angle_to(blade), xf.basis.x.angle_to(edge))
	return Vector2(xf.origin.distance_to(grip), rad_to_deg(turn))


## Plays the light start of `weapon` on fighter `fighter_id`, showing every
## step at alpha 1 and halfway between steps, and returns the worst miss of
## the right hand's weapon from the swing's sample at the frame shown.
func _play_and_miss(fighter_id: StringName, weapon: WeaponDef) -> Vector2:
	var W: World = SimHelpers.make_world(weapon, Moves.KATANA, 3.0)
	var f: Fighter = W.fighters[0]
	var v: FighterView = _view(fighter_id, weapon)
	var swing: Swing = (weapon.moves[weapon.light_start] as AttackDef).swing
	W.step([SimHelpers.btn(Btn.LIGHT), SimHelpers.idle()])
	var worst: Vector2 = Vector2.ZERO
	var frames: int = 0
	while f.state == &"attack" and frames < 120:
		for alpha: float in [0.5, 1.0]:
			v.update_from(f, Vector3.ZERO, 0.0, alpha, 1.0 / 60.0, 0.0)
			var t: float = maxf(0.0, float(f.atk.frame) - 1.0 + alpha)
			var miss: Vector2 = _miss(v, 0, swing.sample(SF.RIGHT, t))
			worst = Vector2(maxf(worst.x, miss.x), maxf(worst.y, miss.y))
		W.step([SimHelpers.idle(), SimHelpers.idle()])
		frames += 1
	assert_gt(frames, 20, "%s %s: the whole move played" % [fighter_id, weapon.id])
	return worst


func test_the_shown_weapon_is_the_swing_at_every_frame() -> void:
	for pair: Array in [[&"hunter", &"greatsword"], [&"rogue", &"katana"], [&"rogue", &"daggers"], [&"hunter", &"katana"]]:
		var miss: Vector2 = _play_and_miss(pair[0], _slashing(pair[1]))
		assert_lt(miss.x, NEAR_POS, "%s %s: the grip is the swing's (%.2f mm off)" % [pair[0], pair[1], miss.x * 1000.0])
		assert_lt(miss.y, NEAR_DEG, "%s %s: the blade and edge are the swing's (%.2f° off)" % [pair[0], pair[1], miss.y])


## A follow-up enters from the hand-off of the move before, as the rules'
## swing does.
func test_a_follow_up_plays_its_chained_entry() -> void:
	var cut: AttackDef = Moves.GREATSWORD.moves[&"g_l1"]
	var back: AttackDef = Moves.GREATSWORD.moves[&"g_l2"]
	var first: Swing = SF.level_slash(cut)
	var second: Swing = SF.level_slash(back, 1.2, -60.0, 60.0)
	var weapon: WeaponDef = SF.weapon(&"greatsword", {&"g_l1": first, &"g_l2": second} as Dictionary[StringName, Swing])
	var W: World = SimHelpers.make_world(weapon, Moves.KATANA, 3.0)
	var f: Fighter = W.fighters[0]
	var v: FighterView = _view(&"hunter", weapon)
	W.step([SimHelpers.btn(Btn.LIGHT), SimHelpers.idle()])
	var steps: int = 0
	while not (f.state == &"attack" and f.atk.def.id == &"g_l2") and steps < 80:
		W.step([SimHelpers.btn(Btn.LIGHT) if steps % 2 == 0 else SimHelpers.idle(), SimHelpers.idle()])
		steps += 1
	assert_eq(f.atk.def.id, &"g_l2", "the follow-up started")
	assert_eq(f.atk.chained_from, weapon.moves[&"g_l1"], "following Heavy Swing")
	var compared: int = 0
	while f.state == &"attack" and f.atk.frame <= back.startup:
		v.update_from(f, Vector3.ZERO, 0.0, 1.0, 1.0 / 60.0, 0.0)
		var miss: Vector2 = _miss(v, 0, second.sample(SF.RIGHT, float(f.atk.frame), first))
		assert_lt(miss.x, NEAR_POS, "frame %d: the chained entry's grip" % f.atk.frame)
		assert_lt(miss.y, NEAR_DEG, "frame %d: the chained entry's blade" % f.atk.frame)
		W.step([SimHelpers.idle(), SimHelpers.idle()])
		compared += 1
	assert_gt(compared, 5, "the entry was shown")
	assert_ne(second.sample(SF.RIGHT, 1.0, first).grip.x, second.sample(SF.RIGHT, 1.0).grip.x,
			"the chained entry differs from the guard's, so the test can tell them apart")


## The frame shown: between steps by alpha, from 0, and the frame itself
## while charging, as the rules hold the blade.
func test_the_frame_shown_follows_alpha_and_holds_in_a_charge() -> void:
	var W: World = SimHelpers.make_world(_slashing(&"katana"), Moves.KATANA, 3.0)
	var f: Fighter = W.fighters[0]
	W.step([SimHelpers.btn(Btn.LIGHT), SimHelpers.idle()])
	W.step([SimHelpers.idle(), SimHelpers.idle()])
	var at: int = f.atk.frame
	assert_almost_eq(SwingPlayer.swing_frame(f, 0.25), float(at) - 0.75, 1e-9)
	assert_almost_eq(SwingPlayer.swing_frame(f, 1.0), float(at), 1e-9)
	f.atk.frame = 0
	assert_eq(SwingPlayer.swing_frame(f, 0.5), 0.0, "never before the first frame")
	f.atk.frame = 9
	f.atk.charging = true
	assert_eq(SwingPlayer.swing_frame(f, 0.25), 9.0, "held at the charge's frame")


## The root stays where the rules put the fighter, and the stand-in's lean,
## crouch and spin are left out of a swing.
func test_the_root_and_body_stay_the_rules() -> void:
	var weapon: WeaponDef = _slashing(&"greatsword")
	var W: World = SimHelpers.make_world(weapon, Moves.KATANA, 3.0)
	var f: Fighter = W.fighters[0]
	var v: FighterView = _view(&"hunter", weapon)
	W.step([SimHelpers.btn(Btn.LIGHT), SimHelpers.idle()])
	for i: int in 16:
		W.step([SimHelpers.idle(), SimHelpers.idle()])
		v.update_from(f, Vector3(f.pos.x, f.pos.y, f.pos.z), f.yaw, 1.0, 1.0 / 60.0, 0.0)
		assert_eq(v.position, Vector3(f.pos.x, f.pos.y, f.pos.z), "frame %d: at the rules' position" % f.atk.frame)
		assert_eq(v.model.rotation, Vector3.ZERO, "frame %d: no spin" % f.atk.frame)
		assert_almost_eq(v.model.rig.body.spine_pitch, 0.0, 1e-9, "frame %d: no stand-in lean" % f.atk.frame)
	assert_ne(v.last_pose.lean, 0.0, "the stand-in would have leaned")


## A weapon held in both hands puts the off hand on its off-hand grip, and
## both hands land on the posed weapon wherever their arms reach it (the
## level slash, made for the Katana, takes the Hunter's right hand past its
## reach across the body).
func test_both_hands_grip_a_swung_greatsword() -> void:
	var weapon: WeaponDef = _slashing(&"greatsword")
	var W: World = SimHelpers.make_world(weapon, Moves.KATANA, 3.0)
	var f: Fighter = W.fighters[0]
	var v: FighterView = _view(&"hunter", weapon)
	W.step([SimHelpers.btn(Btn.LIGHT), SimHelpers.idle()])
	var worst: float = 0.0
	var reached: int = 0
	while f.state == &"attack":
		v.update_from(f, Vector3.ZERO, 0.0, 1.0, 1.0 / 60.0, 0.0)
		assert_true(v.model.rig.drives("Right") and v.model.rig.drives("Left"), "frame %d: both hands on it" % f.atk.frame)
		var poses: Array[Transform3D] = await _posed(v)
		for side: String in FighterRig.SIDES:
			var shoulder: Vector3 = poses[v.model.skeleton.find_bone(side + "UpperArm")].origin
			if shoulder.distance_to(v.model.rig.hand_frame(side).origin) > 0.98 * v.model.rig.arm_length(side):
				continue
			reached += 1
			var fist: Vector3 = poses[v.model.skeleton.find_bone(side + "Hand")] * v.model.rig.fist(side).origin
			worst = maxf(worst, fist.distance_to(v.model.rig.grip_point(side)))
		W.step([SimHelpers.idle(), SimHelpers.idle()])
	assert_gt(reached, 40, "most frames are within reach")
	assert_lt(worst, 0.01, "the fists land on the grips they reach (%.1f mm off at worst)" % (worst * 1000.0))


## Moves without a swing, and a dagger with no track of its own, stay on
## the stand-in pose.
func test_moves_without_a_swing_keep_the_stand_in() -> void:
	var weapon: WeaponDef = _slashing(&"daggers")
	var W: World = SimHelpers.make_world(weapon, Moves.KATANA, 3.0)
	var f: Fighter = W.fighters[0]
	var v: FighterView = _view(&"rogue", weapon)
	W.step([SimHelpers.btn(Btn.LIGHT), SimHelpers.idle()])
	W.step([SimHelpers.idle(), SimHelpers.idle()])
	v.update_from(f, Vector3.ZERO, 0.0, 1.0, 1.0 / 60.0, 0.0)
	assert_true(SwingPlayer.plays(f))
	assert_almost_eq(v.model.weapons[1].transform.basis.y, v.last_pose.left.dir, Vector3.ONE * 1e-4,
			"the left dagger, with no track, follows the stand-in")
	var plain: World = SimHelpers.make_world(Moves.DAGGERS, Moves.KATANA, 3.0)
	plain.step([SimHelpers.btn(Btn.LIGHT), SimHelpers.idle()])
	plain.step([SimHelpers.idle(), SimHelpers.idle()])
	assert_false(SwingPlayer.plays(plain.fighters[0]), "the shared Daggers have no swings yet")


## The key's elbow-pole tweak goes on the rig for the hand it moves.
func test_the_elbow_pole_tweak_reaches_the_rig() -> void:
	var start: AttackDef = Moves.KATANA.moves[&"k_l1"]
	var swing: Swing = SF.level_slash(start)
	for k: Swing.KeyPose in swing.track(SF.RIGHT):
		k.pole = V3.make(0.3, 0.1, -0.2)
	swing = _rebuilt(swing, start)
	var weapon: WeaponDef = SF.weapon(&"katana", {&"k_l1": swing} as Dictionary[StringName, Swing])
	var W: World = SimHelpers.make_world(weapon, Moves.KATANA, 3.0)
	var f: Fighter = W.fighters[0]
	var v: FighterView = _view(&"rogue", weapon)
	W.step([SimHelpers.btn(Btn.LIGHT), SimHelpers.idle()])
	for i: int in start.startup:
		W.step([SimHelpers.idle(), SimHelpers.idle()])
	v.update_from(f, Vector3.ZERO, 0.0, 1.0, 1.0 / 60.0, 0.0)
	assert_almost_eq(v.model.rig.pole_tweak["Right"], Vector3(-0.3, 0.1, -0.2), Vector3.ONE * 1e-6,
			"turned into skeleton space")
	assert_eq(v.model.rig.pole_tweak["Left"], Vector3.ZERO, "none for the other hand")
	f.set_state(&"free")
	v.update_from(f, Vector3.ZERO, 0.0, 1.0, 1.0 / 60.0, 0.0)
	assert_eq(v.model.rig.pole_tweak["Right"], Vector3.ZERO, "cleared out of the swing")


## The same keys in a fresh swing, so its tables hold the changed keys.
static func _rebuilt(swing: Swing, move: AttackDef) -> Swing:
	var out: Swing = Swing.new(move.total_frames(), swing.guard)
	for part: StringName in swing.parts():
		out.add_track(part, swing.track(part))
	return out


## Steps the model's skeleton once and returns every bone's pose in skeleton
## space at the end of the modifier stack.
func _posed(v: FighterView) -> Array[Transform3D]:
	var sk: Skeleton3D = v.model.skeleton
	var poses: Array[Transform3D] = []
	var grab: Callable = func() -> void:
		poses.clear()
		for i: int in sk.get_bone_count():
			poses.append(sk.get_bone_global_pose(i))
	(sk.get_node(^"RigCarry") as SkeletonModifier3D).modification_processed.connect(grab, CONNECT_ONE_SHOT)
	sk.advance(1.0 / 60.0)
	if poses.is_empty():
		await wait_process_frames(1)
	return poses


# ------------------------------------------------------------ chains (14.11)

## A copy of weapon `id` whose lights `moves` have level slashes, each the
## other way from the one before, the third lower.
static func _string_weapon(id: StringName, moves: Array[StringName]) -> WeaponDef:
	var w: WeaponDef = Moves.WEAPONS[id]
	var swings: Dictionary[StringName, Swing] = {}
	for i: int in moves.size():
		var move: AttackDef = w.moves[moves[i]]
		var height: float = 1.0 if i == 2 else 1.2
		swings[moves[i]] = SF.level_slash(move, height) if i % 2 == 0 else SF.level_slash(move, height, -60.0, 60.0)
	return SF.weapon(id, swings)


## Plays `lights` lights of fighter 0's string from the guard (pressing the
## light until that many moves have started), showing the fighter at alpha 1
## after every step, `before` steps of standing in the guard first, and
## `after` steps once the string is over. One record per step: "move" (the
## move id, or &"" out of an attack), "frame" and "grip" (the shown grip).
func _play_string(v: FighterView, W: World, lights: int, before: int = 6, after: int = 12) -> Array[Dictionary]:
	var f: Fighter = W.fighters[0]
	var out: Array[Dictionary] = []
	var started: Array[AttackState] = []
	var idle_after: int = 0
	var steps: int = 0
	while steps < 400:
		var press: bool = steps >= before and started.size() < lights and steps % 2 == 0
		W.step([SimHelpers.btn(Btn.LIGHT) if press else SimHelpers.idle(), SimHelpers.idle()])
		steps += 1
		v.update_from(f, Vector3.ZERO, 0.0, 1.0, 1.0 / 60.0, 0.0)
		var attacking: bool = f.state == &"attack"
		if attacking and not started.has(f.atk):
			started.append(f.atk)
		out.append({"move": f.atk.def.id if attacking else &"", "frame": f.atk.frame if attacking else 0,
				"grip": v.model.weapons[0].transform.origin})
		if not attacking and not started.is_empty():
			idle_after += 1
			if idle_after > after:
				break
	assert_eq(started.size(), lights, "%d lights played" % lights)
	return out


## The most a swing's own right-hand grip moves in a frame between frames
## `from` and `to`, entered from `chained_from`.
static func _own_speed(swing: Swing, from: int, to: int, chained_from: Swing = null) -> float:
	var most: float = 0.0
	for t: int in range(maxi(from, 0), mini(to, swing.last_frame)):
		var a: V3 = swing.sample(SF.RIGHT, float(t), chained_from).grip
		var b: V3 = swing.sample(SF.RIGHT, float(t + 1), chained_from).grip
		most = maxf(most, V3.length(V3.sub(b, a)))
	return most


static func _skeleton(v: V3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


## A weapon with swings stands in their guard. Without a stance under it
## (the Greatsword) that is the guard exactly, so an opener plays exactly
## from its first frame: there is no gap to blend.
func test_an_opener_starts_from_the_guard_it_stands_in() -> void:
	var weapon: WeaponDef = _slashing(&"greatsword")
	var W: World = SimHelpers.make_world(weapon, Moves.KATANA, 3.0)
	var f: Fighter = W.fighters[0]
	var v: FighterView = _view(&"hunter", weapon)
	var guard: Swing.KeyPose = SF.slash_guard()
	for i: int in 4:
		W.step([SimHelpers.idle(), SimHelpers.idle()])
		v.update_from(f, Vector3.ZERO, 0.0, 1.0, 1.0 / 60.0, 0.0)
	var held: Swing.Sample = Swing.Sample.new()
	held.grip = guard.grip
	held.blade = guard.blade
	held.edge = guard.edge
	var miss: Vector2 = _miss(v, 0, held)
	assert_lt(miss.x, NEAR_POS, "in the swings' guard")
	assert_lt(miss.y, NEAR_DEG, "turned as the guard is")
	var swing: Swing = (weapon.moves[weapon.light_start] as AttackDef).swing
	W.step([SimHelpers.btn(Btn.LIGHT), SimHelpers.idle()])
	while f.state == &"attack":
		for alpha: float in [0.5, 1.0]:
			v.update_from(f, Vector3.ZERO, 0.0, alpha, 1.0 / 60.0, 0.0)
			var at: Vector2 = _miss(v, 0, swing.sample(SF.RIGHT, SwingPlayer.swing_frame(f, alpha)))
			assert_lt(at.x, NEAR_POS, "frame %d alpha %.1f: the swing exactly" % [f.atk.frame, alpha])
		W.step([SimHelpers.idle(), SimHelpers.idle()])


## Under the Katana's stance the guard rides the lowered pelvis (the
## stand-in's guard is gone); the opener blends from it into the swing over
## at most BLEND_FRAMES frames, then plays it exactly.
func test_the_guard_rides_the_stance_and_the_opener_blends_from_it() -> void:
	var weapon: WeaponDef = _slashing(&"katana")
	var W: World = SimHelpers.make_world(weapon, Moves.KATANA, 3.0)
	var f: Fighter = W.fighters[0]
	var v: FighterView = _view(&"rogue", weapon)
	for i: int in 4:
		W.step([SimHelpers.idle(), SimHelpers.idle()])
		v.update_from(f, Vector3.ZERO, 0.0, 1.0, 1.0 / 60.0, 0.0)
	var guard: Transform3D = SwingPlayer.guard_poses(weapon, 1)[0]
	var shown: Transform3D = v.model.weapons[0].transform
	assert_lt(rad_to_deg(shown.basis.y.angle_to(guard.basis.y)), NEAR_DEG, "the guard's blade")
	assert_gt(shown.origin.distance_to(guard.origin), 0.05, "riding the stance's lowered pelvis")
	assert_almost_eq(shown.origin.y, guard.origin.y - GuardStance.CROUCH, 0.04, "about as low as the stance")
	var swing: Swing = (weapon.moves[weapon.light_start] as AttackDef).swing
	W.step([SimHelpers.btn(Btn.LIGHT), SimHelpers.idle()])
	var before: Vector3 = shown.origin
	var exact_from: int = -1
	while f.state == &"attack":
		v.update_from(f, Vector3.ZERO, 0.0, 1.0, 1.0 / 60.0, 0.0)
		var now: Vector3 = v.model.weapons[0].transform.origin
		var own: float = _own_speed(swing, f.atk.frame - 2, f.atk.frame)
		assert_lt(now.distance_to(before), own + GuardStance.CROUCH * 0.5,
				"frame %d: no jump (moved %.1f cm)" % [f.atk.frame, now.distance_to(before) * 100.0])
		before = now
		var miss: Vector2 = _miss(v, 0, swing.sample(SF.RIGHT, float(f.atk.frame)))
		if exact_from < 0 and miss.x < NEAR_POS and miss.y < NEAR_DEG:
			exact_from = f.atk.frame
		elif exact_from >= 0:
			assert_lt(miss.x, NEAR_POS, "frame %d: the swing exactly once blended" % f.atk.frame)
		W.step([SimHelpers.idle(), SimHelpers.idle()])
	assert_between(exact_from, 2, int(SwingPlayer.BLEND_FRAMES) + 1, "blended over the first frames only")


## Through the Katana's L-L-L-L and the strings stopped after one, two and
## three lights, the shown grip moves no more in a frame at a chain point
## than the swings around it move on their own, though a follow-up's entry
## starts from the hand-off key, which the move before had not reached (the
## opener also closes the gap from the guard riding the stance); a stopped
## string runs its exit to the guard, then blends to the guard as it rides
## the stance, without a jump. The exit reaches the guard on the move's last
## frame, which the rules never show: the attack ends on the step that
## reaches it, so the last frame shown is a frame short of the guard.
func test_strings_never_jump_and_a_stopped_string_ends_on_the_guard() -> void:
	var lights: Array[StringName] = [&"k_l1", &"k_l2", &"k_l3", &"k_l4"]
	var largest_gap: float = 0.0
	var played_lights: int = 0
	for n: int in [1, 2, 3, 4]:
		var weapon: WeaponDef = _string_weapon(&"katana", lights)
		var chain: Array[StringName] = []
		var id: StringName = weapon.light_start
		while id != &"" and weapon.moves.has(id) and chain.size() < n:
			chain.append(id)
			id = (weapon.moves[id] as AttackDef).chain_light
		if chain.size() < n:
			continue
		played_lights = n
		var W: World = SimHelpers.make_world(weapon, Moves.KATANA, 3.0)
		var v: FighterView = _view(&"rogue", weapon)
		var played: Array[Dictionary] = _play_string(v, W, n)
		for i: int in range(1, played.size()):
			var was: Dictionary = played[i - 1]
			var now: Dictionary = played[i]
			if now["move"] == &"" or now["move"] == was["move"]:
				continue
			var swing: Swing = (weapon.moves[now["move"]] as AttackDef).swing
			var from: Swing = (weapon.moves[was["move"]] as AttackDef).swing if was["move"] != &"" else null
			var at: int = now["frame"]
			var own: float = _own_speed(swing, at - 1, at, from)
			var allow: float = 0.005 if from != null else 0.005 + GuardStance.CROUCH * 0.5
			if from != null:
				var last: int = was["frame"]
				own = maxf(own, _own_speed(from, last - 1, last))
				var raw: float = (was["grip"] as Vector3).distance_to(_skeleton(swing.sample(SF.RIGHT, float(now["frame"]), from).grip))
				largest_gap = maxf(largest_gap, raw - own)
			var moved: float = (now["grip"] as Vector3).distance_to(was["grip"])
			assert_lt(moved, own + allow, "L x%d, into %s: moved %.1f cm, its swings %.1f cm a frame" % [n, now["move"], moved * 100.0, own * 100.0])
		var guard: Transform3D = SwingPlayer.guard_poses(weapon, 1)[0]
		var last_attack: int = -1
		for i: int in played.size():
			if played[i]["move"] != &"":
				last_attack = i
		var ender: Swing = (weapon.moves[played[last_attack]["move"]] as AttackDef).swing
		var short: float = _own_speed(ender, ender.last_frame - 1, ender.last_frame)
		assert_eq(played[last_attack]["frame"], ender.last_frame - 1, "L x%d: the last frame shown" % n)
		assert_lt((played[last_attack]["grip"] as Vector3).distance_to(guard.origin), short + NEAR_POS,
				"L x%d: a frame of its exit short of the guard" % n)
		for i: int in range(last_attack + 1, played.size()):
			var moved: float = (played[i]["grip"] as Vector3).distance_to(played[i - 1]["grip"])
			assert_lt(moved, GuardStance.CROUCH * 0.5, "L x%d: then on to the guard riding the stance, no jump" % n)
		assert_almost_eq((played[-1]["grip"] as Vector3).y, guard.origin.y - GuardStance.CROUCH, 0.04, "L x%d: riding it" % n)
	assert_gt(played_lights, 1, "the string has follow-ups")
	assert_gt(largest_gap, 0.008, "some follow-up's entry started away from the shown grip, so the test can fail")


## A swing cut off by a dodge (the stand-in's pose takes over) blends out
## rather than jumping to the stand-in.
func test_a_cut_off_swing_blends_out() -> void:
	var weapon: WeaponDef = _slashing(&"katana")
	var W: World = SimHelpers.make_world(weapon, Moves.KATANA, 3.0)
	var f: Fighter = W.fighters[0]
	var v: FighterView = _view(&"rogue", weapon)
	var cut: AttackDef = weapon.moves[weapon.light_start]
	W.step([SimHelpers.btn(Btn.LIGHT), SimHelpers.idle()])
	while f.state == &"attack" and f.atk.frame < cut.dodge_cancel_from + 1:
		v.update_from(f, Vector3.ZERO, 0.0, 1.0, 1.0 / 60.0, 0.0)
		W.step([SimHelpers.idle(), SimHelpers.idle()])
	v.update_from(f, Vector3.ZERO, 0.0, 1.0, 1.0 / 60.0, 0.0)
	var before: Vector3 = v.model.weapons[0].transform.origin
	W.step([SimHelpers.move(1.0, 0.0, Btn.DODGE), SimHelpers.idle()])
	assert_ne(f.state, &"attack", "the dodge cut the swing off")
	v.update_from(f, Vector3.ZERO, 0.0, 1.0, 1.0 / 60.0, 0.0)
	var after: Vector3 = v.model.weapons[0].transform.origin
	var gap: float = before.distance_to(v.last_pose.right.pos)
	assert_gt(gap, 0.1, "the stand-in's pose is far from the swing's")
	assert_lt(after.distance_to(before), 0.2 * gap, "the first frame closes a fifth of the gap at most (%.1f of %.1f cm)" % [
			after.distance_to(before) * 100.0, gap * 100.0])
	for i: int in int(SwingPlayer.BLEND_FRAMES) + 1:
		W.step([SimHelpers.idle(), SimHelpers.idle()])
		v.update_from(f, Vector3.ZERO, 0.0, 1.0, 1.0 / 60.0, 0.0)
	assert_true(v.swing_player.settled(), "blended out within BLEND_FRAMES")
