extends GutTest
## Locomotion, the legs under a fighter in the match: idle (the weapon's hold
## clip), walk, jog and sprint blended by the rules' speed, every clip played
## from one shared step phase that moves a stride per cycle, each fighter's
## strides measured from its own clips by FootPhase, all on the rules' clock,
## so it holds still in hit-stop and pause.

## The bones compared when a pose should be a clip's.
const BONES: Array[String] = ["Hips", "Spine", "LeftUpperLeg", "LeftLowerLeg", "RightUpperLeg", "RightLowerLeg", "LeftFoot"]
const W_IDLE: int = 0
const W_WALK: int = 1
const W_JOG: int = 2
const W_SPRINT: int = 3


func after_each() -> void:
	SimHelpers.dispose_all()


## Two fighters `gap` apart, fighter 0 facing +Z toward fighter 1.
func _world(gap: float = 24.0, weapon: WeaponDef = Moves.KATANA) -> World:
	return SimHelpers.make_world(weapon, Moves.KATANA, gap)


func _view(fighter_id: StringName = &"rogue", weapon: WeaponDef = Moves.KATANA) -> FighterView:
	var v: FighterView = FighterView.new()
	add_child_autofree(v)
	v.setup(fighter_id, 0, weapon.id, 0)
	v.model.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	return v


func _show(v: FighterView, f: Fighter, alpha: float = 1.0) -> void:
	v.update_from(f, Vector3(f.pos.x, f.pos.y, f.pos.z), f.yaw, alpha, 1.0 / 60.0, 0.0)


## Steps the world once with fighter 0's input and shows fighter 0.
func _step(W: World, v: FighterView, input: RawInput) -> void:
	W.step([input, SimHelpers.idle()])
	_show(v, W.fighters[0])


static func _speed(f: Fighter) -> float:
	return Vector2(f.vel.x, f.vel.z).length()


## The animated (pre-modifier) local poses of BONES.
func _pose(v: FighterView) -> Array[Transform3D]:
	var sk: Skeleton3D = v.model.skeleton
	var out: Array[Transform3D] = []
	for bone: String in BONES:
		out.append(sk.get_bone_pose(sk.find_bone(bone)))
	return out


## The local poses of BONES in clip `clip` at `seconds`, played alone on the
## model's own player (the tree is shown again afterwards by the caller).
func _clip_pose(v: FighterView, clip: StringName, seconds: float) -> Array[Transform3D]:
	var ap: AnimationPlayer = v.model.animation_player
	ap.play(String(FighterModel.LIBRARY) + "/" + String(clip), 0.0)
	ap.seek(seconds, true)
	return _pose(v)


func _assert_pose(a: Array[Transform3D], b: Array[Transform3D], what: String) -> void:
	for i: int in BONES.size():
		assert_almost_eq(a[i].origin, b[i].origin, Vector3.ONE * 2e-3, "%s: %s's position" % [what, BONES[i]])
		var angle: float = rad_to_deg(a[i].basis.get_rotation_quaternion().angle_to(b[i].basis.get_rotation_quaternion()))
		assert_lt(angle, 0.5, "%s: %s's rotation" % [what, BONES[i]])


func _weights(s: float, run: float = 3.9, sprint: float = 7.2) -> PackedFloat32Array:
	return Locomotion.weights(s, run, sprint)


func _assert_weights(got: PackedFloat32Array, want: Array, what: String) -> void:
	assert_eq(got.size(), 4, what)
	for i: int in 4:
		assert_almost_eq(got[i], float(want[i]), 1e-5, "%s: %s" % [what, ["idle", "walk", "jog", "sprint"][i]])


# ------------------------------------------------------------------ the blend

func test_the_blend_is_idle_at_rest_walk_at_0_98_jog_at_the_run_and_sprint_at_the_sprint() -> void:
	_assert_weights(_weights(0.0), [1, 0, 0, 0], "at rest")
	_assert_weights(_weights(0.98), [0, 1, 0, 0], "at 0.98 m/s")
	_assert_weights(_weights(3.9), [0, 0, 1, 0], "at the run, 3.9 m/s")
	_assert_weights(_weights(7.2), [0, 0, 0, 1], "at the sprint, 7.2 m/s")
	_assert_weights(_weights(0.49), [0.5, 0.5, 0, 0], "half way to the walk")
	_assert_weights(_weights((0.98 + 3.9) / 2.0), [0, 0.5, 0.5, 0], "half way to the run")
	_assert_weights(_weights((3.9 + 7.2) / 2.0), [0, 0, 0.5, 0.5], "half way to the sprint")
	_assert_weights(_weights(9.0), [0, 0, 0, 1], "past the sprint")
	# a Greatsword's run and sprint (its 0.9 speed)
	_assert_weights(_weights(3.51, 3.51, 6.48), [0, 0, 1, 0], "the Greatsword's run")
	_assert_weights(_weights(6.48, 3.51, 6.48), [0, 0, 0, 1], "the Greatsword's sprint")
	var s: float = 0.0
	while s < 8.0:
		var w: PackedFloat32Array = _weights(s)
		assert_almost_eq(w[0] + w[1] + w[2] + w[3], 1.0, 1e-5, "the weights sum to 1 at %.2f m/s" % s)
		s += 0.05


func test_each_fighters_strides_are_measured_from_its_own_clips() -> void:
	var walk: Vector2 = Vector2(0.85, 1.1)
	var bands: Array[Vector2] = [walk, Vector2(4.5, 5.8), Vector2(7.5, 9.5)]
	var strides: Array[float] = []
	for id: StringName in FighterLook.IDS:
		var v: FighterView = _view(id)
		var gaits: Array[FootPhase.Gait] = v.locomotion.gaits
		assert_eq(gaits.size(), 3)
		for i: int in 3:
			var g: FootPhase.Gait = gaits[i]
			assert_eq(g.clip, Locomotion.CLIPS[i])
			assert_between(g.speed, bands[i].x, bands[i].y, "%s %s's ground speed" % [id, g.clip])
			assert_almost_eq(g.stride, g.speed * g.length, 1e-4, "%s %s: a stride per cycle" % [id, g.clip])
			assert_almost_eq(fposmod(g.right_stance - g.left_stance, 1.0), 0.5, 0.07, "%s %s: the feet half a cycle apart" % [id, g.clip])
		strides.append(gaits[1].stride)
		var again: FootPhase.Gait = FootPhase.measure(v.model, Locomotion.CLIPS[1])
		assert_almost_eq(again.stride, gaits[1].stride, 1e-4, "%s: the same measure again" % id)
	assert_ne(strides[0], strides[1], "each fighter its own")


func test_a_foot_sweeping_back_gives_the_ground_speed_at_mid_stance() -> void:
	# 2 m/s back for the first half of a 1 s cycle (z from +0.5 to -0.5),
	# then swinging forward again
	var z: PackedFloat32Array = PackedFloat32Array()
	var n: int = 200
	for i: int in n:
		var t: float = float(i) / n
		z.append(0.5 - 2.0 * t if t < 0.5 else -0.5 + 2.0 * (t - 0.5))
	var mid: Vector2 = FootPhase.mid_stance(z, 1.0 / n)
	assert_almost_eq(mid.x, 0.25, 1e-3, "mid-stance a quarter of the way round")
	assert_almost_eq(mid.y, 2.0, 1e-3, "the ground passes at 2 m/s")


# ------------------------------------------------------------------ the phase

func test_the_phase_moves_a_stride_per_cycle_on_each_rules_frame() -> void:
	var W: World = _world()
	var f: Fighter = W.fighters[0]
	var v: FighterView = _view()
	var loco: Locomotion = v.locomotion
	_show(v, f)
	var most: float = SimConst.MOVE_SPRINT / loco.gaits[2].stride / 60.0
	var inputs: Array[RawInput] = []
	for i: int in 20:
		inputs.append(SimHelpers.idle())
	for i: int in 30:
		inputs.append(SimHelpers.move(0.0, 1.0))
	for i: int in 40:
		inputs.append(SimHelpers.move(0.0, 1.0, Btn.SPRINT))
	var top: float = 0.0
	for input: RawInput in inputs:
		var before: float = loco.phase
		_step(W, v, input)
		var s: float = _speed(f)
		top = maxf(top, s)
		var moved: float = fposmod(loco.phase - before, 1.0)
		assert_almost_eq(moved, s / loco.stride(s) / 60.0, 1e-5, "at %.2f m/s, frame %d" % [s, W.frame])
		assert_lt(moved, most + 1e-6, "never more than a sprint's step")
	assert_almost_eq(top, SimConst.MOVE_SPRINT, 1e-3, "it reached the sprint")
	assert_almost_eq(loco.stride(SimConst.MOVE_SPRINT), loco.gaits[2].stride, 1e-5, "a sprint's stride at the sprint")
	assert_almost_eq(loco.stride(0.3), loco.gaits[0].stride, 1e-5, "a walk's stride below the walk")


func test_the_shown_phase_blends_between_rules_frames_by_alpha() -> void:
	var W: World = _world()
	var f: Fighter = W.fighters[0]
	var v: FighterView = _view()
	var loco: Locomotion = v.locomotion
	for i: int in 30:
		_step(W, v, SimHelpers.move(0.0, 1.0))
	var step: float = fposmod(loco.phase - loco.prev_phase, 1.0)
	assert_gt(step, 0.0)
	for alpha: float in [0.0, 0.25, 1.0]:
		_show(v, f, alpha)
		assert_almost_eq(loco.shown_phase, fposmod(loco.prev_phase + step * alpha, 1.0), 1e-6, "alpha %.2f" % alpha)
	# across the wrap from just under 1 to just over 0
	loco.prev_phase = 0.99
	loco.phase = 0.01
	_show(v, f, 0.5)
	assert_almost_eq(loco.shown_phase, 0.0, 1e-6, "half way round the wrap")


func test_the_phase_holds_in_hit_stop() -> void:
	var W: World = _world()
	var f: Fighter = W.fighters[0]
	var v: FighterView = _view()
	var loco: Locomotion = v.locomotion
	for i: int in 30:
		_step(W, v, SimHelpers.move(0.0, 1.0))
	assert_gt(_speed(f), 3.0)
	var held: float = loco.phase
	var pose: Array[Transform3D] = _pose(v)
	W.hitstop = 8
	for i: int in 8:
		_step(W, v, SimHelpers.move(0.0, 1.0))
		assert_eq(loco.phase, held, "hit-stop step %d" % i)
	_assert_pose(_pose(v), pose, "the legs hold still")
	_step(W, v, SimHelpers.move(0.0, 1.0))
	assert_ne(loco.phase, held, "and walk on after it")


func test_the_phase_holds_while_the_match_is_paused() -> void:
	var host: MatchHost = (load("res://view/match/match_host.tscn") as PackedScene).instantiate()
	host.auto_run = false
	host.use_services = false
	add_child_autofree(host)
	host.start(MatchConfig.make(
		MatchConfig.DUEL,
		MatchSide.computer(&"rogue", &"katana", 0, &"normal"),
		MatchSide.computer(&"hunter", &"greatsword", 1, &"normal"),
		7,
	))
	var view: MatchView = host.get_node("View")
	var loco: Locomotion = view.fighters[0].locomotion
	var steps: int = 0
	while _speed(host.fighter(0)) < 1.0 and steps < 600:
		host.step(1)
		view.update_fighters(1.0 / 60.0)
		steps += 1
	assert_gt(_speed(host.fighter(0)), 1.0, "the computer walks")
	host.pause()
	assert_true(host.is_paused())
	var held: float = loco.shown_phase
	var pose: Array[Transform3D] = _pose(view.fighters[0])
	for i: int in 5:
		assert_eq(host.advance(0.25), 0)
		view.update_fighters(0.25)
		assert_eq(loco.shown_phase, held, "paused, update %d" % i)
	_assert_pose(_pose(view.fighters[0]), pose, "the legs hold still")
	host.resume()
	host.step(1)
	view.update_fighters(1.0 / 60.0)
	assert_ne(loco.shown_phase, held, "and walk on after it")


# ------------------------------------------------------------------ the pose

func test_at_rest_the_hold_clip_plays_on_the_rules_clock() -> void:
	var W: World = _world()
	var f: Fighter = W.fighters[0]
	var v: FighterView = _view(&"hunter")
	for i: int in 70:
		_step(W, v, SimHelpers.idle())
	v.update_from(f, Vector3.ZERO, 0.0, 0.5, 1.0 / 60.0, 0.0)
	var shown: Array[Transform3D] = _pose(v)
	_assert_weights(v.locomotion.shown, [1, 0, 0, 0], "at rest")
	_assert_pose(shown, _clip_pose(v, v.model.idle_clip(), (W.frame + 0.5) / 60.0), "the hold clip at the rules' frame")
	v.update_from(f, Vector3.ZERO, 0.0, 0.5, 3.0, 7.0)
	_assert_pose(_pose(v), shown, "the same frame shows the same however much wall time passes")


func test_a_running_fighter_jogs_and_a_sprinting_one_sprints_from_the_shared_phase() -> void:
	var W: World = _world()
	var f: Fighter = W.fighters[0]
	var v: FighterView = _view()
	var loco: Locomotion = v.locomotion
	for spec: Array in [[SimHelpers.move(0.0, 1.0), W_JOG], [SimHelpers.move(0.0, 1.0, Btn.SPRINT), W_SPRINT]]:
		for i: int in 25:
			_step(W, v, spec[0])
		var which: int = spec[1]
		var want: Array = [0, 0, 0, 0]
		want[which] = 1
		_assert_weights(loco.shown, want, "at %.2f m/s" % _speed(f))
		var g: FootPhase.Gait = loco.gaits[which - 1]
		var at: float = fposmod(loco.shown_phase + g.left_stance, 1.0) * g.length
		assert_almost_eq(loco.clip_time(which - 1, loco.shown_phase), at, 1e-6)
		var shown: Array[Transform3D] = _pose(v)
		_assert_pose(shown, _clip_pose(v, g.clip, at), "%s at the shared phase" % g.clip)
		_show(v, f)


func test_a_greatsword_runs_and_sprints_at_its_own_speeds() -> void:
	var W: World = _world(24.0, Moves.GREATSWORD)
	var f: Fighter = W.fighters[0]
	var v: FighterView = _view(&"hunter", Moves.GREATSWORD)
	var loco: Locomotion = v.locomotion
	for i: int in 25:
		_step(W, v, SimHelpers.move(0.0, 1.0))
	assert_almost_eq(_speed(f), SimConst.MOVE_RUN_FORWARD * Moves.GREATSWORD.speed_mult, 1e-4, "its run")
	_assert_weights(loco.shown, [0, 0, 1, 0], "a full jog at its run")
	for i: int in 25:
		_step(W, v, SimHelpers.move(0.0, 1.0, Btn.SPRINT))
	assert_almost_eq(_speed(f), SimConst.MOVE_SPRINT * Moves.GREATSWORD.speed_mult, 1e-4, "its sprint")
	_assert_weights(loco.shown, [0, 0, 0, 1], "a full sprint at its sprint")


func test_the_left_foot_is_at_mid_stance_at_phase_zero_in_every_clip() -> void:
	var v: FighterView = _view()
	var loco: Locomotion = v.locomotion
	var sk: Skeleton3D = v.model.skeleton
	for i: int in 3:
		var g: FootPhase.Gait = loco.gaits[i]
		_clip_pose(v, g.clip, loco.clip_time(i, 0.0))
		var left: float = sk.get_bone_global_pose(sk.find_bone("LeftFoot")).origin.z
		var zs: PackedFloat32Array = PackedFloat32Array()
		for k: int in 40:
			_clip_pose(v, g.clip, g.length * k / 40.0)
			zs.append(sk.get_bone_global_pose(sk.find_bone("LeftFoot")).origin.z)
		var lo: float = zs[0]
		var hi: float = zs[0]
		for z: float in zs:
			lo = minf(lo, z)
			hi = maxf(hi, z)
		assert_almost_eq(left, (lo + hi) / 2.0, 0.03 * (hi - lo), "%s: the left foot passes the middle of its sweep" % g.clip)


func test_only_walking_and_running_on_the_ground_move_the_legs() -> void:
	var W: World = _world()
	var f: Fighter = W.fighters[0]
	f.vel = V3.make(0.0, 0.0, 3.9)
	assert_almost_eq(Locomotion.ground_speed(f), 3.9, 1e-6, "free")
	f.set_state(&"step")
	assert_almost_eq(Locomotion.ground_speed(f), 3.9, 1e-6, "a step")
	for state: StringName in [&"dodge", &"backstep", &"attack", &"hitstun", &"jump", &"ko"]:
		f.set_state(state)
		assert_eq(Locomotion.ground_speed(f), 0.0, state)
	f.set_state(&"free")
	f.pos = V3.make(0.0, 0.5, 0.0)
	assert_eq(Locomotion.ground_speed(f), 0.0, "in the air")
