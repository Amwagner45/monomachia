extends GutTest
## The Katana's new strings (plan task 9): the spec's Katana table, played
## through the rules. Expected numbers come from the spec, not the code.

const H := preload("res://tests/sim/sim_helpers.gd")
## toBeCloseTo's default precision (2 digits), as the neighbouring tests use
const CLOSE: float = 0.005

## The spec's Katana table, the rows of the light string, its heavy endings
## and the vertical Iai: name, frames (startup, active, recovery), damage, posture, the
## light and heavy follow-ups (&"" for none), and the sides the spec's move
## data gives the weapon (start, end).
const ROWS: Dictionary[StringName, Dictionary] = {
	&"k_l1": {
		"name": "Right Cut", "frames": [11, 3, 16], "damage": 6, "posture": 7,
		"light": &"k_l2", "heavy": &"k_h2", "sides": [&"right", &"left"],
	},
	&"k_l2": {
		"name": "Return Cut", "frames": [10, 3, 16], "damage": 6, "posture": 7,
		"light": &"k_l3", "heavy": &"k_h1f", "sides": [&"left", &"right"],
	},
	&"k_l3": {
		"name": "Kesa Cut", "frames": [11, 3, 17], "damage": 7, "posture": 8,
		"light": &"k_l4", "heavy": &"k_h2", "sides": [&"right", &"left"],
	},
	&"k_l4": {
		"name": "Crown Cut", "frames": [14, 4, 22], "damage": 8, "posture": 10,
		"light": &"", "heavy": &"", "sides": [&"centre", &"centre"],
	},
	# the data counts the sheathe in the startup: 9 + 14 = 23
	&"k_iai": {
		"name": "Iai Slash (vertical)", "frames": [23, 4, 24], "damage": 13, "posture": 16,
		"light": &"", "heavy": &"k_h1f", "sides": [&"left", &"right"],
	},
	&"k_h1f": {
		"name": "Rising Heaven", "frames": [16, 4, 24], "damage": 12, "posture": 15,
		"light": &"", "heavy": &"k_h2", "sides": [&"right", &"left"],
	},
	&"k_h2": {
		"name": "Heaven Splitter", "frames": [22, 4, 28], "damage": 15, "posture": 18,
		"light": &"", "heavy": &"", "sides": [&"centre", &"centre"],
	},
}

## Kesa Cut dodge-cancels from frame 20 (the plan's decisions: startup +
## active + 6, as Right Cut and Return Cut).
const KESA_CUT_CANCEL: int = 20

## The Iai Slash sheathes for 9 frames (a held heavy then stays sheathed, as
## a charge) and draws in 14, so a tapped heavy draws on frame 23 (the
## plan's decisions).
const IAI_SHEATHE: int = 9
const IAI_DRAW: int = 14
## A tapped Iai dodge-cancels from frame 39: startup + active + half its
## recovery, rounded up, as every heavy (23 + 4 + 12).
const IAI_CANCEL: int = 39

## The spec's length of move id in frames: startup + active + recovery.
static func _length(id: StringName) -> int:
	var frames: Array = ROWS[id]["frames"]
	return frames[0] + frames[1] + frames[2]


func after_each() -> void:
	H.dispose_all()


# ------------------------------------------------------------------ helpers

## A string played by fighter 0: its events, each with "step", the step it
## came on, and after each step fighter 0's state, the attack it was in (&""
## outside one), that attack's frame (-1) and whether it was sheathed (holding
## a charge).
class PlayedString:
	extends SimHelpers.Rec
	var state: Array[StringName] = []
	var attack: Array[StringName] = []
	var frame: PackedInt32Array = []
	var sheathed: Array[bool] = []

	## Steps W with fighter 0's input p0 and fighter 1's p1 (null for idle),
	## records the step, and returns its events.
	func step(W: World, p0: RawInput, p1: RawInput = null) -> Array[Dictionary]:
		var i: int = state.size()
		W.step([p0, SimHelpers.idle() if p1 == null else p1])
		var new_events: Array[Dictionary] = W.drain_events()
		for e: Dictionary in new_events:
			e["step"] = i
		events.append_array(new_events)
		var a: Fighter = W.fighters[0]
		var attacking: bool = a.state == &"attack" and a.atk != null
		state.append(a.state)
		attack.append(a.atk.def.id if attacking else &"")
		frame.append(a.atk.frame if attacking else -1)
		sheathed.append(attacking and a.atk.charging)
		return new_events

	## The step of fighter 0's first event of type t (-1 if none).
	func step_of(t: StringName) -> int:
		for e: Dictionary in all(t):
			if _by_fighter_0(e):
				return e["step"]
		return -1

	## Whether fighter 0 made event e (a swing or whiff names its fighter as
	## "f", a hit or block as "attacker").
	static func _by_fighter_0(e: Dictionary) -> bool:
		return e.get("f", e.get("attacker")) == 0

	## The frame fighter 0's last attack id ended on, one past the last frame a
	## step left it in (-1 if it never started): an attack is over on the step
	## its frame reaches startup + active + recovery.
	func ended_on(id: StringName) -> int:
		var i: int = attack.rfind(id)
		return -1 if i < 0 else frame[i] + 1

	## Fighter 0's state on the step its last attack id ended (&"?" if it
	## never started or the run ended first): &"attack" when a follow-up took
	## over.
	func state_after(id: StringName) -> StringName:
		var i: int = attack.rfind(id)
		return &"?" if i < 0 or i + 1 >= state.size() else state[i + 1]

	## The ids of fighter 0's attacks that made events of type t, in order.
	func ids(t: StringName) -> Array[StringName]:
		var out: Array[StringName] = []
		for e: Dictionary in all(t):
			if _by_fighter_0(e):
				out.append(e["attack"])
		return out


## Fighter 0 plays a string of presses (Btn.LIGHT or Btn.HEAVY) for 240 steps
## against an idle Katana gap m away: the first on step 0, each next one on the
## step after the attack before it swings, the first step that attack takes a
## follow-up. With dodge_in set, it also presses dodge so that the press
## first counts on that attack's frame dodge_on, holding the stick to the side
## from then on (a buffered dodge with the stick let go is a backstep).
static func _play(presses: Array[int], gap: float = 2.2, dodge_in: StringName = &"", dodge_on: int = -1) -> PlayedString:
	var W: World = H.make_world(Moves.KATANA, Moves.KATANA, gap)
	var a: Fighter = W.fighters[0]
	var r := PlayedString.new()
	var next: int = 0
	var due: bool = true
	var dodged: bool = false
	for i: int in 240:
		var p0: RawInput = H.idle()
		if due and next < presses.size():
			p0 = H.btn(presses[next])
			next += 1
			due = false
		elif dodged:
			p0 = H.move(1.0, 0.0)
		elif a.state == &"attack" and a.atk.def.id == dodge_in and a.atk.frame == dodge_on - 1:
			p0 = H.move(1.0, 0.0, Btn.DODGE)
			dodged = true
		for e: Dictionary in r.step(W, p0):
			if e["t"] == &"swing" and e["f"] == 0:
				due = true
	return r


# ------------------------------------------------------------------ the light string

func test_four_lights_hit_with_right_cut_return_cut_kesa_cut_and_crown_cut() -> void:
	var r: PlayedString = _play([Btn.LIGHT, Btn.LIGHT, Btn.LIGHT, Btn.LIGHT])
	assert_eq(r.ids(&"hit"), [&"k_l1", &"k_l2", &"k_l3", &"k_l4"] as Array[StringName])


func test_a_heavy_ends_the_string_on_heaven_splitter_or_after_two_lights_on_rising_heaven() -> void:
	var light: int = Btn.LIGHT
	var heavy: int = Btn.HEAVY
	assert_eq(_play([light, heavy]).ids(&"hit"), [&"k_l1", &"k_h2"] as Array[StringName], "L-H: Right Cut, Heaven Splitter")
	assert_eq(
		_play([light, light, heavy]).ids(&"hit"),
		[&"k_l1", &"k_l2", &"k_h1f"] as Array[StringName],
		"L-L-H: Return Cut, Rising Heaven",
	)
	assert_eq(
		_play([light, light, light, heavy]).ids(&"hit"),
		[&"k_l1", &"k_l2", &"k_l3", &"k_h2"] as Array[StringName],
		"L-L-L-H: Kesa Cut, Heaven Splitter",
	)


func test_crown_cut_ends_the_string() -> void:
	for press: int in [Btn.LIGHT, Btn.HEAVY]:
		var r: PlayedString = _play([Btn.LIGHT, Btn.LIGHT, Btn.LIGHT, Btn.LIGHT, press])
		var what: String = "a %s pressed in Crown Cut" % ("light" if press == Btn.LIGHT else "heavy")
		assert_eq(r.ids(&"swing"), [&"k_l1", &"k_l2", &"k_l3", &"k_l4"] as Array[StringName], "%s starts nothing" % what)
		assert_eq(r.ended_on(&"k_l4"), _length(&"k_l4"), "%s: Crown Cut ends on frame 40, startup + active + recovery" % what)
		assert_eq(r.state_after(&"k_l4"), &"free", "%s: then the fighter is free" % what)


func test_stopping_after_any_hit_ends_the_string_when_that_move_ends() -> void:
	var light: int = Btn.LIGHT
	var heavy: int = Btn.HEAVY
	var strings: Array = [
		[light], [light, light], [light, light, light], [light, light, light, light],
		[light, heavy], [light, light, heavy], [light, light, light, heavy],
	]
	for presses: Array in strings:
		var typed: Array[int] = []
		typed.assign(presses)
		var r: PlayedString = _play(typed)
		var hits: Array[StringName] = r.ids(&"hit")
		assert_eq(hits.size(), presses.size(), "every press of %s hits" % [presses])
		if hits.size() != presses.size():
			continue
		var last: StringName = hits.back()
		assert_eq(r.ended_on(last), _length(last), "%s ends on startup + active + recovery" % last)
		assert_eq(r.state_after(last), &"free", "and the fighter is free after %s" % last)


## Plays presses, the last starting attack id, after a hit (2.2 m) and after a
## whiff (10 m), and checks a dodge pressed on its frame cancel - 1 is refused
## there and comes on cancel, and one pressed on cancel comes at once.
func _assert_dodge_cancels_from(presses: Array[int], id: StringName, cancel: int) -> void:
	for gap: float in [2.2, 10.0]:
		var what: String = "%s %s" % [id, "after a hit" if gap < 3.0 else "after a whiff"]
		var early: PlayedString = _play(presses, gap, id, cancel - 1)
		assert_eq(
			[early.ended_on(id), early.state_after(id)],
			[cancel, &"dodge"],
			"%s: a dodge pressed on frame %d is refused there and comes on %d" % [what, cancel - 1, cancel],
		)
		var on_time: PlayedString = _play(presses, gap, id, cancel)
		assert_eq(
			[on_time.ended_on(id), on_time.state_after(id)],
			[cancel, &"dodge"],
			"%s: one pressed on frame %d comes at once" % [what, cancel],
		)


func test_kesa_cut_dodge_cancels_from_frame_20() -> void:
	_assert_dodge_cancels_from([Btn.LIGHT, Btn.LIGHT, Btn.LIGHT], &"k_l3", KESA_CUT_CANCEL)


# ------------------------------------------------------------------ the Iai Slash

func test_a_tapped_heavy_draws_the_iai_on_frame_23() -> void:
	var r: PlayedString = _play([Btn.HEAVY])
	var draw: int = r.step_of(&"swing")
	assert_eq(r.ids(&"swing"), [&"k_iai"] as Array[StringName], "the heavy is the Iai Slash")
	assert_eq(r.frame[draw] if draw >= 0 else -1, IAI_SHEATHE + IAI_DRAW, "drawn on frame 23, the sheathe and the draw")
	assert_eq(r.ids(&"hit"), [&"k_iai"] as Array[StringName], "and it hits")


## Fighter 0 holds heavy for hold steps against an idle Katana 2.2 m away, for
## 240 steps.
static func _hold_heavy(hold: int) -> PlayedString:
	var W: World = H.make_world()
	var r := PlayedString.new()
	for i: int in 240:
		r.step(W, H.btn(Btn.HEAVY) if i < hold else H.idle())
	return r


func test_a_held_iai_stays_sheathed_and_hits_14_frames_after_release() -> void:
	var r: PlayedString = _hold_heavy(60)
	assert_eq(r.sheathed.find(true), IAI_SHEATHE + 1, "sheathed once its 9 frames have passed")
	assert_eq(r.sheathed.rfind(true), 59, "until heavy is let go on step 60")
	assert_eq(r.frame.slice(IAI_SHEATHE, 60).count(IAI_SHEATHE), 60 - IAI_SHEATHE, "its frames stop on 9 meanwhile")
	assert_eq(r.ids(&"hit"), [&"k_iai"] as Array[StringName])
	assert_eq(r.step_of(&"hit") - 60, IAI_DRAW, "the cut lands 14 frames after the release")


func test_an_iai_held_for_2_5_s_releases_by_itself_as_a_stronger_power_attack() -> void:
	var r: PlayedString = _hold_heavy(220)
	var release: int = r.sheathed.rfind(true) + 1
	assert_eq(release, IAI_SHEATHE + 150, "the stance ends 150 frames (2.5 s) after the sheathe, heavy still held")
	assert_eq(r.step_of(&"hit") - release, IAI_DRAW, "and the cut lands 14 frames later")
	var hit: Dictionary = r.find(&"hit")
	assert_almost_eq(float(hit.get("damage", NAN)), 13.0 * 1.8, CLOSE, "a full charge's damage")


func test_the_iai_hits_at_3_8_m_where_right_cut_whiffs() -> void:
	var cut: PlayedString = _play([Btn.LIGHT], 3.8)
	assert_eq(cut.ids(&"whiff"), [&"k_l1"] as Array[StringName], "Right Cut whiffs")
	assert_eq(_play([Btn.HEAVY], 3.8).ids(&"hit"), [&"k_iai"] as Array[StringName], "the Iai hits")


func test_a_sheathed_fighter_cannot_block() -> void:
	# fighter 0 holds heavy to stay sheathed, and holds block too from step
	# 12; the opponent's Right Cut lands while it is sheathed
	var W: World = H.make_world()
	var r := PlayedString.new()
	for i: int in 60:
		var p0: RawInput = H.btn(Btn.HEAVY) if i < 12 else H.btn(Btn.HEAVY, Btn.BLOCK)
		r.step(W, p0, H.btn(Btn.LIGHT) if i == 20 else H.idle())
	var on_fighter_0: Callable = func(e: Dictionary) -> bool: return e["target"] == 0
	var hits: Array[Dictionary] = r.all(&"hit").filter(on_fighter_0)
	assert_eq(hits.size(), 1, "the Right Cut hits")
	if hits.size() == 1:
		assert_true(r.sheathed[int(hits[0]["step"]) - 1], "a sheathed fighter")
	assert_eq(r.all(&"block").filter(on_fighter_0), [] as Array[Dictionary], "holding block blocks nothing")


func test_a_heavy_after_the_iai_gives_rising_heaven() -> void:
	assert_eq(_play([Btn.HEAVY, Btn.HEAVY]).ids(&"hit"), [&"k_iai", &"k_h1f"] as Array[StringName])


func test_the_iai_dodge_cancels_late_in_its_recovery() -> void:
	_assert_dodge_cancels_from([Btn.HEAVY], &"k_iai", IAI_CANCEL)


# ------------------------------------------------------------------ the spec's table

func test_the_rows_built_so_far_match_the_spec_table() -> void:
	for id: StringName in ROWS:
		var row: Dictionary = ROWS[id]
		var m: AttackDef = Moves.KATANA.moves.get(id, null)
		assert_not_null(m, "%s exists" % id)
		if m == null:
			continue
		assert_eq(m.name, row["name"], "%s name" % id)
		assert_eq([m.startup, m.active, m.recovery], row["frames"], "%s frames" % row["name"])
		assert_eq([m.damage, m.posture], [float(row["damage"]), float(row["posture"])], "%s damage and posture" % row["name"])
		assert_eq([m.chain_light, m.chain_heavy], [row["light"], row["heavy"]], "%s follow-ups" % row["name"])
		assert_eq([m.side_start, m.side_end], row["sides"], "%s sides" % row["name"])


func test_kesa_cut_hits_with_the_specs_interim_cone() -> void:
	# until weapon paths decide hits (task 7): a slash from the right shoulder
	# to the left hip (the stand-in's diagonal cut down), 2.2 m and 100° after
	# a 0.35 m lunge, knocking back 0.4 m
	var m: AttackDef = Moves.KATANA.moves[&"k_l3"]
	assert_eq([m.type, m.anim], [&"slash", &"diagDown"], "Kesa Cut is a diagonal slash down")
	assert_eq([m.range, m.arc, m.lunge, m.knockback], [2.2, 100.0, 0.35, 0.4], "range, arc, lunge and knockback")
