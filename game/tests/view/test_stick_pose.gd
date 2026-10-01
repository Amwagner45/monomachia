extends GutTest
## The stand-in fighters' stick poses, read from the rules' state: guard,
## block, an attack sweeping wind-up -> strike -> follow-through -> guard, a
## reel when hit, the fall on KO, bare hands when disarmed.


func after_each() -> void:
	SimHelpers.dispose_all()


func _world(w1: WeaponDef = Moves.KATANA, w2: WeaponDef = Moves.KATANA) -> World:
	return SimHelpers.make_world(w1, w2)


func _press(W: World, b: int) -> void:
	W.step([SimHelpers.btn(b), SimHelpers.idle()])


func test_the_stick_lengths_follow_the_weapons() -> void:
	assert_eq(StickPose.LENGTH[&"katana"], 0.95)
	assert_eq(StickPose.LENGTH[&"greatsword"], 1.6)
	assert_eq(StickPose.LENGTH[&"daggers"], 0.4)


func test_a_free_fighter_holds_the_guard() -> void:
	var W: World = _world()
	var p: StickPose.Pose = StickPose.compute(W.fighters[0], 0.0)
	assert_eq(p.phase, &"guard")
	assert_true(p.two_handed)
	assert_false(p.bare)
	assert_gt(p.right.pos.z, 0.1, "the hands are in front of the body")


func test_blocking_raises_the_block() -> void:
	var W: World = _world()
	for i: int in 3:
		W.step([SimHelpers.btn(Btn.BLOCK), SimHelpers.idle()])
	assert_true(W.fighters[0].blocking)
	var p: StickPose.Pose = StickPose.compute(W.fighters[0], 1.0)
	assert_eq(p.phase, &"block")
	assert_lt(absf(p.right.dir.y), 0.5, "the katana held across the body")


func test_an_attack_sweeps_through_its_arc() -> void:
	var W: World = _world()
	var a: Fighter = W.fighters[0]
	_press(W, Btn.LIGHT)
	assert_eq(a.state, &"attack")
	var def: AttackDef = a.atk.def
	assert_eq(def.anim, &"slashRL")
	var phases: Array[StringName] = []
	var hand_x: Array[float] = []
	var dirs: Array[Vector3] = []
	while a.state == &"attack":
		var p: StickPose.Pose = StickPose.compute(a, 1.0)
		if phases.is_empty() or phases[-1] != p.phase:
			phases.append(p.phase)
		hand_x.append(p.right.pos.x)
		dirs.append(p.right.dir)
		W.step([SimHelpers.idle(), SimHelpers.idle()])
	assert_eq(phases, [&"windup", &"strike", &"follow", &"recover"] as Array[StringName], "wind-up, strike, follow-through, back to guard")
	# a right-to-left cut: the hand starts on the right (-x) and ends on the left (+x)
	var lowest: float = hand_x.min()
	var highest: float = hand_x.max()
	assert_lt(lowest, -0.3, "wound up on the right")
	assert_gt(highest, 0.25, "followed through to the left")
	var turned: float = 0.0
	for i: int in range(1, dirs.size()):
		turned += dirs[i - 1].angle_to(dirs[i])
	assert_gt(turned, PI * 0.8, "the blade sweeps a wide arc")
	assert_eq(StickPose.compute(a, 1.0).phase, &"guard", "and returns to guard")


func test_the_strike_lands_on_the_impact_key() -> void:
	var W: World = _world()
	var a: Fighter = W.fighters[0]
	_press(W, Btn.LIGHT)
	var def: AttackDef = a.atk.def
	while a.atk.frame < def.startup + 1:
		W.step([SimHelpers.idle(), SimHelpers.idle()])
	var p: StickPose.Pose = StickPose.compute(a, 1.0)
	var impact: Dictionary = StickPose.attack_keys(def, &"katana")[1]
	assert_almost_eq(p.right.pos, (impact["right"] as StickPose.Hand).pos, Vector3.ONE * 1e-4)


func test_an_unblockable_glows_red_while_it_winds_up() -> void:
	var W: World = _world(Moves.GREATSWORD)
	var a: Fighter = W.fighters[0]
	a.start_attack(&"g_sweep")
	W.step([SimHelpers.idle(), SimHelpers.idle()])
	assert_true(a.atk.def.unblockable)
	var p: StickPose.Pose = StickPose.compute(a, 1.0)
	assert_eq(p.glow, &"danger")
	assert_eq(p.glow_amount, 1.0)


func test_a_hit_fighter_reels_and_a_ko_falls() -> void:
	var W: World = _world()
	var b: Fighter = W.fighters[1]
	b.enter_hitstun(20)
	var p: StickPose.Pose = StickPose.compute(b, 1.0)
	assert_eq(p.phase, &"reel")
	assert_lt(p.lean, -0.1, "leaning back")
	b.to_ko()
	for i: int in 30:
		W.step([SimHelpers.idle(), SimHelpers.idle()])
	p = StickPose.compute(b, 1.0)
	assert_eq(p.phase, &"down")
	assert_almost_eq(p.down, 1.0, 1e-6, "lying on the floor")


func test_a_disarmed_fighter_is_bare_handed() -> void:
	var W: World = _world()
	var b: Fighter = W.fighters[1]
	b.armed = false
	var p: StickPose.Pose = StickPose.compute(b, 1.0)
	assert_true(p.bare)
	assert_false(p.two_handed)


func test_daggers_left_hand_moves_mirror_the_right() -> void:
	var def: AttackDef = Moves.DAGGERS.moves[&"d_l2"]
	assert_eq(def.hand, &"L")
	var keys: Array[Dictionary] = StickPose.attack_keys(def, &"daggers")
	var right_keys: Array[Dictionary] = StickPose.attack_keys(Moves.DAGGERS.moves[&"d_l1"], &"daggers")
	var l: StickPose.Hand = keys[1]["left"]
	var r: StickPose.Hand = right_keys[1]["right"]
	assert_almost_eq(l.pos, StickPose.mirrored(r.pos), Vector3.ONE * 1e-6)


func test_the_standin_places_its_stick_from_the_pose() -> void:
	var W: World = _world(Moves.DAGGERS)
	var s: FighterStandin = FighterStandin.new()
	add_child_autofree(s)
	s.setup(&"hunter", 1, &"daggers", 0)
	s.update_from(W.fighters[0], Vector3(1.0, 0.0, 2.0), 0.5, 1.0, 0.016, 0.0)
	assert_eq(s.position, Vector3(1.0, 0.0, 2.0))
	var hand: Node3D = s.get_node("Body/HandR")
	assert_almost_eq(hand.position, s.last_pose.right.pos, Vector3.ONE * 1e-5)
	assert_almost_eq(hand.basis.y.normalized(), s.last_pose.right.dir, Vector3.ONE * 1e-4)
	assert_true((s.get_node("Body/HandL/Blade") as Node3D).visible, "both daggers drawn")
	W.fighters[0].armed = false
	s.update_from(W.fighters[0], Vector3.ZERO, 0.0, 1.0, 0.016, 0.0)
	assert_false((s.get_node("Body/HandR/Blade") as Node3D).visible, "no blade when disarmed")
	assert_true((s.get_node("Body/HandR/Fist") as Node3D).visible)
