extends GutTest
## The Katana's new strings (plan task 9): the spec's Katana table, played
## through the rules. Expected numbers come from the spec, not the code.

const H := preload("res://tests/sim/sim_helpers.gd")

## The spec's Katana table, the rows of the light string and its heavy
## endings: name, frames (startup, active, recovery), damage, posture, the
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

## The spec's length of move id in frames: startup + active + recovery.
static func _length(id: StringName) -> int:
	var frames: Array = ROWS[id]["frames"]
	return frames[0] + frames[1] + frames[2]


func after_each() -> void:
	H.dispose_all()


# ------------------------------------------------------------------ helpers

## A string played by fighter 0: its events, and after each step its state,
## the attack it was in (&"" outside one) and that attack's frame (-1).
class StringRun:
	extends SimHelpers.Rec
	var state: Array[StringName] = []
	var attack: Array[StringName] = []
	var frame: PackedInt32Array = []

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

	## The ids of fighter 0's attacks that made events of type t, in order
	## (a swing or whiff names its fighter as "f", a hit or block as "attacker").
	func ids(t: StringName) -> Array[StringName]:
		var out: Array[StringName] = []
		for e: Dictionary in all(t):
			if e.get("f", e.get("attacker")) == 0:
				out.append(e["attack"])
		return out


## Fighter 0 plays a string of presses (Btn.LIGHT or Btn.HEAVY) for n steps
## against an idle Katana gap m away: the first on step 0, each next one on the
## step after the attack before it swings, the first step that attack takes a
## follow-up. With dodge_in set, it also presses dodge so that the press
## first counts on that attack's frame dodge_on, holding the stick to the side
## from then on (a buffered dodge with the stick let go is a backstep).
static func _play(
	presses: Array[int], gap: float = 2.2, dodge_in: StringName = &"", dodge_on: int = -1, n: int = 240
) -> StringRun:
	var W: World = H.make_world(Moves.KATANA, Moves.KATANA, gap)
	var a: Fighter = W.fighters[0]
	var r := StringRun.new()
	var next: int = 0
	var due: bool = true
	var dodged: bool = false
	for i: int in n:
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
		W.step([p0, H.idle()])
		var events: Array[Dictionary] = W.drain_events()
		r.events.append_array(events)
		for e: Dictionary in events:
			if e["t"] == &"swing" and e["f"] == 0:
				due = true
		var attacking: bool = a.state == &"attack" and a.atk != null
		r.state.append(a.state)
		r.attack.append(a.atk.def.id if attacking else &"")
		r.frame.append(a.atk.frame if attacking else -1)
	return r


# ------------------------------------------------------------------ the light string

func test_four_lights_hit_with_right_cut_return_cut_kesa_cut_and_crown_cut() -> void:
	var r: StringRun = _play([Btn.LIGHT, Btn.LIGHT, Btn.LIGHT, Btn.LIGHT])
	assert_eq(r.ids(&"hit"), [&"k_l1", &"k_l2", &"k_l3", &"k_l4"] as Array[StringName])


func test_a_heavy_ends_the_string_on_heaven_splitter_or_after_two_lights_on_rising_heaven() -> void:
	var L: int = Btn.LIGHT
	var Hv: int = Btn.HEAVY
	assert_eq(_play([L, Hv]).ids(&"hit"), [&"k_l1", &"k_h2"] as Array[StringName], "L-H: Right Cut, Heaven Splitter")
	assert_eq(
		_play([L, L, Hv]).ids(&"hit"), [&"k_l1", &"k_l2", &"k_h1f"] as Array[StringName], "L-L-H: Return Cut, Rising Heaven"
	)
	assert_eq(
		_play([L, L, L, Hv]).ids(&"hit"),
		[&"k_l1", &"k_l2", &"k_l3", &"k_h2"] as Array[StringName],
		"L-L-L-H: Kesa Cut, Heaven Splitter",
	)


func test_crown_cut_ends_the_string() -> void:
	for press: int in [Btn.LIGHT, Btn.HEAVY]:
		var r: StringRun = _play([Btn.LIGHT, Btn.LIGHT, Btn.LIGHT, Btn.LIGHT, press])
		var what: String = "a %s pressed in Crown Cut" % ("light" if press == Btn.LIGHT else "heavy")
		assert_eq(r.ids(&"swing"), [&"k_l1", &"k_l2", &"k_l3", &"k_l4"] as Array[StringName], "%s starts nothing" % what)
		assert_eq(r.ended_on(&"k_l4"), _length(&"k_l4"), "%s: Crown Cut ends on frame 40, startup + active + recovery" % what)
		assert_eq(r.state_after(&"k_l4"), &"free", "%s: then the fighter is free" % what)


func test_stopping_after_any_hit_ends_the_string_when_that_move_ends() -> void:
	var L: int = Btn.LIGHT
	var Hv: int = Btn.HEAVY
	var strings: Array = [[L], [L, L], [L, L, L], [L, L, L, L], [L, L, Hv], [L, Hv]]
	for presses: Array in strings:
		var typed: Array[int] = []
		typed.assign(presses)
		var r: StringRun = _play(typed)
		var hits: Array[StringName] = r.ids(&"hit")
		assert_eq(hits.size(), presses.size(), "every press of %s hits" % [presses])
		if hits.size() != presses.size():
			continue
		var last: StringName = hits.back()
		assert_eq(r.ended_on(last), _length(last), "%s ends on startup + active + recovery" % last)
		assert_eq(r.state_after(last), &"free", "and the fighter is free after %s" % last)


func test_kesa_cut_dodge_cancels_from_frame_20() -> void:
	var L: int = Btn.LIGHT
	for gap: float in [2.2, 10.0]:
		var what: String = "after a hit" if gap < 3.0 else "after a whiff"
		var early: StringRun = _play([L, L, L], gap, &"k_l3", KESA_CUT_CANCEL - 1)
		assert_eq(
			[early.ended_on(&"k_l3"), early.state_after(&"k_l3")],
			[KESA_CUT_CANCEL, &"dodge"],
			"%s: a dodge pressed on frame 19 is refused there and comes on 20" % what,
		)
		var on_time: StringRun = _play([L, L, L], gap, &"k_l3", KESA_CUT_CANCEL)
		assert_eq(
			[on_time.ended_on(&"k_l3"), on_time.state_after(&"k_l3")],
			[KESA_CUT_CANCEL, &"dodge"],
			"%s: one pressed on frame 20 comes at once" % what,
		)


# ------------------------------------------------------------------ the spec's table

func test_the_light_string_and_its_heavy_endings_match_the_spec_table() -> void:
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
