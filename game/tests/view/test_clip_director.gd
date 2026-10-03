extends GutTest
## The clip director (ClipDirector, authored-animation task 8): a fighter's
## rules state in, the clips, their times and weights out, with no nodes.
## The Katana's first two lights are given baked swings here (made-up clips
## whose lengths the context names), so these run without the packs.

const LENGTH: float = 1.5

var _saved: Dictionary[StringName, Swing] = {}


func before_each() -> void:
	var k: WeaponDef = Moves.KATANA
	for id: StringName in [&"k_l1", &"k_l2"]:
		_saved[id] = k.moves[id].swing
		k.moves[id].swing = _baked(k.moves[id], [StringName("Clip_" + String(id))])


func after_each() -> void:
	for id: StringName in _saved:
		Moves.KATANA.moves[id].swing = _saved[id]
	_saved.clear()
	SimHelpers.dispose_all()


## A baked swing for `move` that holds still, baked at ×1.0 from `clips`:
## its markers put the contact start on the move's last startup frame and
## the settle on its last.
static func _baked(move: AttackDef, clips: Array[StringName]) -> Swing:
	var s: Swing = Swing.new(move.total_frames())
	var keys: Array[Swing.KeyPose] = []
	for f: int in move.total_frames() + 1:
		var k: Swing.KeyPose = Swing.KeyPose.new()
		k.frame = f
		k.grip = V3.make(-0.1, 1.1, 0.4)
		k.blade = V3.make(0.0, 0.6, 0.8)
		k.edge = V3.make(1.0, 0.0, 0.0)
		keys.append(k)
	s.add_track(&"right_hand", keys, true)
	s.clips = clips
	s.speed = 1.0
	s.marks = PackedFloat64Array([0.0, move.startup / 2.0, (move.startup + move.active) / 2.0, move.total_frames() / 2.0])
	s.fallback = &"Sword_Attack"
	return s


static func _ctx(fighter_id: StringName = &"hunter", libraries: bool = true) -> ClipDirector.Context:
	var lengths: Dictionary[String, float] = {"ual/Sword_Attack": 1.2}
	for set_name: StringName in ClipLibraries.SETS:
		for id: String in ["Clip_k_l1", "Clip_k_l2", "Chain_A", "Chain_B"]:
			lengths["%s/%s" % [set_name, id]] = LENGTH
	return ClipDirector.Context.make(fighter_id, libraries, lengths)


## Steps the world one frame (no inputs) and the director after it.
static func _next(W: World, prev: ClipDirector.Shot, ctx: ClipDirector.Context, inputs: Array[RawInput] = []) -> ClipDirector.Shot:
	var given: Array[RawInput] = inputs
	if given.is_empty():
		given = [SimHelpers.idle(), SimHelpers.idle()]
	W.step(given)
	return ClipDirector.step(prev, W.fighters[0], ctx)


func test_the_free_idle_is_the_weapon_classs() -> void:
	var cases: Dictionary = {
		Moves.KATANA: ["HumanM/CombatIdle1H01", "ual/Sword_Idle"],
		Moves.GREATSWORD: ["HumanM/CombatIdle2H01", "ual/Sword_Idle"],
		Moves.DAGGERS: ["HumanM/CombatIdle1H01", "ual/Sword_Idle"],
		Moves.FISTS: ["HumanM/CombatIdle01", "ual/Idle"],
	}
	for w: WeaponDef in cases:
		var W: World = SimHelpers.make_world(w, Moves.KATANA)
		var f: Fighter = W.fighters[0]
		assert_eq(ClipDirector.step(null, f, _ctx()).idle, cases[w][0], "%s: its combat idle" % w.id)
		assert_eq(ClipDirector.step(null, f, _ctx(&"rogue")).idle, "HumanF" + String(cases[w][0]).substr(6), "%s: the Rogue's own set" % w.id)
		assert_eq(ClipDirector.step(null, f, _ctx(&"hunter", false)).idle, cases[w][1], "%s: the CC0 fallback without the packs" % w.id)
		assert_eq(ClipDirector.step(null, f, _ctx()).drive, ClipDirector.LEGS, "the legs drive the free state")
	var W2: World = SimHelpers.make_world(Moves.GREATSWORD, Moves.KATANA)
	W2.fighters[0].armed = false
	assert_eq(ClipDirector.step(null, W2.fighters[0], _ctx()).idle, "HumanM/CombatIdle01", "disarmed: bare hands' idle")


func test_an_attacks_clip_time_follows_its_attack_frame() -> void:
	var W: World = SimHelpers.make_world()
	var f: Fighter = W.fighters[0]
	var ctx: ClipDirector.Context = _ctx()
	var shot: ClipDirector.Shot = ClipDirector.step(null, f, ctx)
	shot = _next(W, shot, ctx, [SimHelpers.btn(Btn.LIGHT), SimHelpers.idle()] as Array[RawInput])
	assert_eq(f.state, &"attack")
	var cut: AttackDef = f.atk.def
	var t: ClipTiming = ClipDirector.timing_of(cut.swing)
	assert_eq([t.startup, t.active, t.total()], [cut.startup, cut.active, cut.total_frames()], "the timing the bake used")
	while f.state == &"attack":
		assert_eq(shot.drive, ClipDirector.ATTACK)
		assert_eq(shot.clip.name, "HumanM/Clip_k_l1")
		assert_almost_eq(shot.clip.time, t.clip_time(float(f.atk.frame)), 1e-9, "frame %d" % f.atk.frame)
		if f.atk.frame == cut.startup:
			assert_almost_eq(shot.clip.time, t.marks[1] / 30.0, 1e-9, "the contact start on the last startup frame")
		shot = _next(W, shot, ctx)
	assert_eq(shot.drive, ClipDirector.LEGS, "back to the legs after")


func test_hit_stop_and_pause_hold_the_shot() -> void:
	var W: World = SimHelpers.make_world()
	var f: Fighter = W.fighters[0]
	var ctx: ClipDirector.Context = _ctx()
	var shot: ClipDirector.Shot = _next(W, ClipDirector.step(null, f, ctx), ctx, [SimHelpers.btn(Btn.LIGHT), SimHelpers.idle()] as Array[RawInput])
	shot = _next(W, shot, ctx)
	var held: float = shot.clip.time
	# paused: the world isn't stepped, the frame stands
	assert_same(ClipDirector.step(shot, f, ctx), shot, "a frame seen again gives the same shot")
	# hit-stop: the world steps, its frame stands
	W.hitstop = 3
	for i: int in 3:
		var again: ClipDirector.Shot = _next(W, shot, ctx)
		assert_same(again, shot, "hit-stop holds it")
	assert_eq(shot.clip.time, held)
	shot = _next(W, shot, ctx)
	assert_gt(shot.clip.time, held, "and it goes on after")


func test_a_charge_holds_the_clip() -> void:
	var W: World = SimHelpers.make_world()
	var f: Fighter = W.fighters[0]
	var ctx: ClipDirector.Context = _ctx()
	var shot: ClipDirector.Shot = _next(W, ClipDirector.step(null, f, ctx), ctx, [SimHelpers.btn(Btn.LIGHT), SimHelpers.idle()] as Array[RawInput])
	for i: int in 3:
		shot = _next(W, shot, ctx)
	# a charge holds the attack's frame, as the rules do
	f.atk.charging = true
	var frame: int = f.atk.frame
	var t: float = ClipDirector.step(shot, f, ctx).clip.time
	for i: int in 4:
		W.frame += 1
		f.atk.frame = frame
		shot = ClipDirector.step(shot, f, ctx)
		assert_eq(shot.clip.time, t, "held at the charge's frame")


## Pokes fighter `f` into a state for the director's next step.
static func _poke(W: World, f: Fighter, state: StringName, move: StringName = &"", frame: int = 0, from: StringName = &"") -> void:
	W.frame += 1
	f.state = state
	if move == &"":
		f.atk = null
		return
	if f.atk == null or f.atk.def.id != move:
		f.atk = AttackState.new()
		f.atk.def = Moves.KATANA.moves[move]
		f.atk.chained_from = Moves.KATANA.moves[from] if from != &"" else null
	f.atk.frame = frame


func test_each_crossfade_has_its_length() -> void:
	var W: World = SimHelpers.make_world()
	var f: Fighter = W.fighters[0]
	var ctx: ClipDirector.Context = _ctx()
	var shot: ClipDirector.Shot = ClipDirector.step(null, f, ctx)
	# into an attack: 3 frames from the legs
	_poke(W, f, &"attack", &"k_l1", 1)
	shot = ClipDirector.step(shot, f, ctx)
	assert_eq(shot.fade, 3, "into an attack")
	assert_null(shot.from, "from the legs' blend")
	var shares: Array[float] = [shot.authored()]
	for i: int in 3:
		_poke(W, f, &"attack", &"k_l1", 2 + i)
		shot = ClipDirector.step(shot, f, ctx)
		shares.append(shot.authored())
	assert_eq(shares[0], 0.0, "the attack's first frame starts the fade")
	assert_gt(shares[1], 0.0)
	assert_lt(shares[2], 1.0)
	assert_eq(shares[3], 1.0, "all of it after 3 frames")
	# a follow-up: 4 frames, from the last clip's pose
	var last_time: float = shot.clip.time
	_poke(W, f, &"attack", &"k_l2", 1, &"k_l1")
	shot = ClipDirector.step(shot, f, ctx)
	assert_eq(shot.fade, 4, "a follow-up")
	assert_eq(shot.from.name, "HumanM/Clip_k_l1", "fading in from the last clip")
	assert_eq(shot.from.time, last_time, "held at its last pose")
	assert_eq(shot.clip.name, "HumanM/Clip_k_l2")
	assert_eq(shot.authored(), 1.0, "authored all through")
	for i: int in 4:
		_poke(W, f, &"attack", &"k_l2", 2 + i)
		shot = ClipDirector.step(shot, f, ctx)
	assert_null(shot.from, "the fade done")
	assert_eq(shot.clip_share(), 1.0)
	# back to the legs: 6 frames
	_poke(W, f, &"free")
	shot = ClipDirector.step(shot, f, ctx)
	assert_eq([shot.drive, shot.fade], [ClipDirector.LEGS, 6], "back to the legs")
	assert_eq(shot.from.name, "HumanM/Clip_k_l2", "the clip fading out")
	assert_eq(shot.authored(), 1.0)
	for i: int in 6:
		_poke(W, f, &"free")
		shot = ClipDirector.step(shot, f, ctx)
	assert_eq(shot.authored(), 0.0, "the legs alone after 6 frames")
	assert_null(shot.from)
	# a dodge-cancel: 2
	_poke(W, f, &"attack", &"k_l1", 1)
	shot = ClipDirector.step(shot, f, ctx)
	_poke(W, f, &"attack", &"k_l1", 15)
	shot = ClipDirector.step(shot, f, ctx)
	_poke(W, f, &"dodge")
	shot = ClipDirector.step(shot, f, ctx)
	assert_eq(shot.fade, 2, "a dodge-cancel")
	# hitstun cuts
	_poke(W, f, &"attack", &"k_l1", 1)
	shot = ClipDirector.step(shot, f, ctx)
	_poke(W, f, &"attack", &"k_l1", 6)
	shot = ClipDirector.step(shot, f, ctx)
	_poke(W, f, &"hitstun")
	shot = ClipDirector.step(shot, f, ctx)
	assert_eq(shot.fade, 0, "hitstun cuts")
	assert_eq(shot.authored(), 0.0, "nothing fades out")
	assert_eq(ClipDirector.FADES[&"stance"], 8, "a stance change fades 8")


func test_a_move_without_a_baked_swing_keeps_the_stand_in() -> void:
	var W: World = SimHelpers.make_world()
	var f: Fighter = W.fighters[0]
	var ctx: ClipDirector.Context = _ctx()
	var move: AttackDef = Moves.KATANA.moves[&"k_l3"]
	var own: Swing = move.swing
	move.swing = null
	_poke(W, f, &"attack", &"k_l3", 1)
	assert_eq(ClipDirector.step(null, f, ctx).drive, ClipDirector.LEGS, "no swing: nothing authored")
	move.swing = _baked(move, [])
	assert_eq(ClipDirector.step(null, f, ctx).drive, ClipDirector.LEGS, "a swing not baked from a clip: nothing authored")
	move.swing = own


func test_without_the_packs_the_fallback_plays() -> void:
	var W: World = SimHelpers.make_world()
	var f: Fighter = W.fighters[0]
	var ctx: ClipDirector.Context = _ctx(&"hunter", false)
	_poke(W, f, &"attack", &"k_l1", 0)
	var cut: AttackDef = f.atk.def
	for frame: int in [0, 10, cut.total_frames()]:
		f.atk.frame = frame
		var clip: ClipDirector.Clip = ClipDirector.attack_clip(f, ctx, float(frame))
		assert_eq(clip.name, "ual/Sword_Attack", "the swing's fallback")
		assert_almost_eq(clip.time, 1.2 * frame / cut.total_frames(), 1e-9, "stretched over the move")
	cut.swing.fallback = &""
	assert_null(ClipDirector.attack_clip(f, ctx, 5.0), "no fallback: the stand-in")


func test_the_rogue_plays_the_hunters_set_for_a_flagged_move() -> void:
	var W: World = SimHelpers.make_world()
	var f: Fighter = W.fighters[0]
	_poke(W, f, &"attack", &"k_l1", 4)
	assert_eq(ClipDirector.attack_clip(f, _ctx(&"rogue"), 4.0).name, "HumanF/Clip_k_l1", "her own set")
	f.atk.def.swing.rogue_humanm = true
	assert_eq(ClipDirector.attack_clip(f, _ctx(&"rogue"), 4.0).name, "HumanM/Clip_k_l1", "flagged: the Hunter's")
	assert_eq(ClipDirector.attack_clip(f, _ctx(&"hunter"), 4.0).name, "HumanM/Clip_k_l1")


func test_a_chain_plays_its_clips_in_turn() -> void:
	var ctx: ClipDirector.Context = _ctx()
	var chain: Array[StringName] = [&"Chain_A", &"Chain_B"]
	var a: ClipDirector.Clip = ClipDirector.chain_clip(chain, &"HumanM", 0.5, ctx)
	assert_eq([a.name, a.time], ["HumanM/Chain_A", 0.5])
	var b: ClipDirector.Clip = ClipDirector.chain_clip(chain, &"HumanM", LENGTH + 0.25, ctx)
	assert_eq(b.name, "HumanM/Chain_B")
	assert_almost_eq(b.time, 0.25, 1e-9)


## Moonsplitter (task 13): wound up and held through the rules' 36-frame
## wind-up, released from the hold as the wave goes out, by its variant.
func test_moonsplitter_holds_its_wind_up_and_cuts_with_the_wave() -> void:
	var W: World = SimHelpers.make_world()
	var f: Fighter = W.fighters[0]
	var lengths: Dictionary[String, float] = {"HumanM/Attack2H01": 1.6, "HumanM/Attack2H03": 1.53, "ual/Sword_Heavy_Combo": 2.0}
	var ctx: ClipDirector.Context = ClipDirector.Context.make(&"hunter", true, lengths)
	f.state = &"ult"
	f.ult = UltState.make(&"moonsplitter", &"windup", 0, &"vertical", 0, false)
	f.ult.pf = 10
	var c: ClipDirector.Clip = ClipDirector.ult_clip(f, ctx)
	assert_eq(c.name, "HumanM/Attack2H01", "the vertical wave's clip")
	assert_almost_eq(c.time * 30.0, 5.0, 1e-6, "raised at 1.0")
	f.ult.pf = 30
	assert_almost_eq(ClipDirector.ult_clip(f, ctx).time * 30.0, 12.0, 1e-6, "held at the top")
	f.ult.phase = &"release"
	f.ult.pf = 3
	assert_almost_eq(ClipDirector.ult_clip(f, ctx).time * 30.0, 15.0, 1e-6, "cutting at 2.0 as the wave goes out")
	f.ult.variant = &"horizontal"
	assert_eq(ClipDirector.ult_clip(f, ctx).name, "HumanM/Attack2H03", "the horizontal wave's clip")
	var shot: ClipDirector.Shot = ClipDirector.step(null, f, ctx)
	assert_eq([shot.drive, shot.move], [ClipDirector.ATTACK, &"moonsplitter"], "it drives")
	var bare: ClipDirector.Context = ClipDirector.Context.make(&"hunter", false, lengths)
	f.ult.phase = &"windup"
	f.ult.pf = 18
	c = ClipDirector.ult_clip(f, bare)
	assert_eq(c.name, "ual/Sword_Heavy_Combo", "without the packs, the fallback")
	assert_almost_eq(c.time, 2.0 * 18.0 / 70.0, 1e-6, "stretched over the wind-up and release")
	f.ult.kind = &"impaler"
	assert_null(ClipDirector.ult_clip(f, ctx), "the other ultimates keep their stand-ins")


# ------------------------------------------------------------------ the shoulder carry (task 18)

## A context for a Greatsword fighter: Heavy Swing's clip and the carry's
## pose, with their lengths.
static func _gs_ctx(libraries: bool = true) -> ClipDirector.Context:
	var lengths: Dictionary[String, float] = {"ual/Sword_Heavy_A": 1.2, "ual/Sword_Idle": 2.0}
	for set_name: StringName in ClipLibraries.SETS:
		lengths["%s/Attack2H01" % set_name] = 1.6
		lengths["%s/%s" % [set_name, ClipDirector.CARRY_POSE]] = 0.33
	return ClipDirector.Context.make(&"hunter", libraries, lengths)


## A Greatsword fighter 8 m from a Katana, walked onto the shoulder: the
## world, the shot after it and the frames walked.
func _walk_onto_the_shoulder(ctx: ClipDirector.Context) -> Array:
	var W: World = SimHelpers.make_world(Moves.GREATSWORD, Moves.KATANA, 8.0)
	var f: Fighter = W.fighters[0]
	var shot: ClipDirector.Shot = ClipDirector.step(null, f, ctx)
	var walked: int = 0
	while not f.shouldered and walked < 60:
		shot = _next(W, shot, ctx, [SimHelpers.move(0.0, 1.0), SimHelpers.idle()])
		walked += 1
	return [W, shot]


func test_the_carry_shows_on_the_upper_body_while_shouldered() -> void:
	var ctx: ClipDirector.Context = _gs_ctx()
	var got: Array = _walk_onto_the_shoulder(ctx)
	var W: World = got[0]
	var shot: ClipDirector.Shot = got[1]
	assert_true(W.fighters[0].shouldered, "walked onto the shoulder")
	assert_eq(shot.drive, ClipDirector.CARRY, "the carry drives")
	assert_eq(shot.clip.name, "HumanM/" + ClipDirector.CARRY_POSE)
	assert_eq(shot.fade, ClipDirector.FADES[&"stance"], "faded in as a stance")
	assert_eq(shot.legs_free(), 1.0, "the legs are the legs' blend's")
	for i: int in ClipDirector.FADES[&"stance"]:
		shot = _next(W, shot, ctx, [SimHelpers.move(0.0, 1.0), SimHelpers.idle()])
	assert_eq(shot.authored(), 1.0, "all of it on the upper body")
	assert_eq(shot.legs_free(), 1.0, "and the legs still walk")
	# standing still keeps it
	for i: int in 10:
		shot = _next(W, shot, ctx)
	assert_eq(shot.drive, ClipDirector.CARRY, "standing still keeps it")


func test_without_the_packs_nothing_shows_the_carry() -> void:
	var ctx: ClipDirector.Context = _gs_ctx(false)
	var got: Array = _walk_onto_the_shoulder(ctx)
	assert_true((got[0] as World).fighters[0].shouldered)
	assert_eq((got[1] as ClipDirector.Shot).drive, ClipDirector.LEGS, "no CC0 carry: the legs")


func test_an_attack_from_the_shoulder_fades_in_over_the_lift() -> void:
	var ctx: ClipDirector.Context = _gs_ctx()
	var got: Array = _walk_onto_the_shoulder(ctx)
	var W: World = got[0]
	var f: Fighter = W.fighters[0]
	var shot: ClipDirector.Shot = got[1]
	for i: int in 10:
		shot = _next(W, shot, ctx)
	shot = _next(W, shot, ctx, [SimHelpers.btn(Btn.LIGHT), SimHelpers.idle()])
	assert_eq([f.state, f.atk.def.id, f.atk.lift], [&"attack", &"g_l1", SimConst.GS_SHOULDER_LIFT_FRAMES], "Heavy Swing from the shoulder")
	assert_eq(shot.drive, ClipDirector.ATTACK)
	assert_eq(shot.fade, SimConst.GS_SHOULDER_LIFT_FRAMES, "the lift is the crossfade")
	assert_eq(shot.from.name, "HumanM/" + ClipDirector.CARRY_POSE, "from the shoulder")
	assert_true(shot.from_carry)
	var first: float = shot.clip.time
	var legs: Array[float] = [shot.legs_free()]
	for i: int in SimConst.GS_SHOULDER_LIFT_FRAMES:
		shot = _next(W, shot, ctx)
		legs.append(shot.legs_free())
		if f.atk.lift_left > 0:
			assert_eq(shot.clip.time, first, "the attack's first frame held through the lift")
	assert_eq(legs[0], 1.0, "the legs walk as the lift starts")
	assert_eq(legs[-1], 0.0, "and are the attack's once it ends")
	for i: int in legs.size() - 1:
		assert_true(legs[i + 1] <= legs[i], "handed over without going back: %s" % [legs])
	assert_null(shot.from, "the fade done")


func test_a_guard_raised_from_the_shoulder_fades_out_over_the_lift() -> void:
	var ctx: ClipDirector.Context = _gs_ctx()
	var got: Array = _walk_onto_the_shoulder(ctx)
	var W: World = got[0]
	var shot: ClipDirector.Shot = got[1]
	for i: int in 10:
		shot = _next(W, shot, ctx)
	shot = _next(W, shot, ctx, [SimHelpers.btn(Btn.BLOCK), SimHelpers.idle()])
	assert_false(W.fighters[0].shouldered, "off the shoulder")
	assert_eq([shot.drive, shot.fade], [ClipDirector.LEGS, SimConst.GS_SHOULDER_LIFT_FRAMES], "back to the legs over the lift")
	assert_eq(shot.legs_free(), 1.0, "the legs stay the legs' blend's as it fades")
	assert_eq(shot.authored(), 1.0, "the carry still all there on its first frame")
