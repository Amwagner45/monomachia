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
	_poke(W, f, &"attack", &"k_l3", 1)
	assert_eq(ClipDirector.step(null, f, ctx).drive, ClipDirector.LEGS, "no swing: nothing authored")
	var hand_keyed: Swing = _baked(Moves.KATANA.moves[&"k_l3"], [])
	Moves.KATANA.moves[&"k_l3"].swing = hand_keyed
	assert_eq(ClipDirector.step(null, f, ctx).drive, ClipDirector.LEGS, "a swing not baked from a clip: nothing authored")
	Moves.KATANA.moves[&"k_l3"].swing = null


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
