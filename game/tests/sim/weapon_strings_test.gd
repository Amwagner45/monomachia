class_name WeaponStringsTest
extends GutTest
## What each weapon's strings test (plan tasks 9-11) shares. A test names its
## weapon and the spec's table of its moves in _init, plays its strings
## through _play and _run (see PlayedString), and checks them with the
## asserts below. Expected numbers come from the spec, not the code.

const H := preload("res://tests/sim/sim_helpers.gd")
## toBeCloseTo's default precision (2 digits), as the neighbouring tests use
const CLOSE: float = 0.005
## The buttons that start a follow-up.
const LIGHT_OR_HEAVY: Array[int] = [Btn.LIGHT, Btn.HEAVY]

## The weapon fighter 0 holds.
var weapon: WeaponDef
## The spec's table of the weapon's moves, by id: name, frames (startup,
## active, recovery), damage, posture, the light and heavy follow-ups (&""
## for none), and the sides the spec's move data gives the weapon (start,
## end).
var rows: Dictionary[StringName, Dictionary]


func after_each() -> void:
	H.dispose_all()


## The spec's length of move id in frames: startup + active + recovery.
func _length(id: StringName) -> int:
	var frames: Array = rows[id]["frames"]
	return frames[0] + frames[1] + frames[2]


## presses as the spec writes a string: "L-L-H".
static func _named(presses: Array[int]) -> String:
	var out: PackedStringArray = []
	for press: int in presses:
		out.append("L" if press == Btn.LIGHT else "H")
	return "-".join(out)


## Fighter 0 plays a string of presses with the weapon against an idle Katana
## gap m away (see PlayedString.play: the first on step 0, each next one on
## the step after the attack before it swings; mx the stick's sideways push
## throughout; a dodge pressed on attack dodge_in's frame dodge_on).
func _play(
	presses: Array[int], gap: float = 2.2, mx: float = 0.0, dodge_in: StringName = &"", dodge_on: int = -1
) -> PlayedString:
	return PlayedString.play(weapon, presses, gap, mx, dodge_in, dodge_on)


## Fighter 0, holding the weapon, plays the input p0 gives each step (step
## index -> RawInput) for n steps against an idle Katana gap m away.
func _run(p0: Callable, gap: float = 2.2, n: int = 240) -> PlayedString:
	return PlayedString.run(weapon, p0, gap, n)


## Plays presses (the stick at mx), then each of buttons as the last of swings
## swings, and checks that it starts nothing: the swings stay swings, and the
## last of them ends on startup + active + recovery, leaving the fighter free.
func _assert_starts_nothing_in(presses: Array[int], swings: Array[StringName], buttons: Array[int], mx: float = 0.0) -> void:
	var id: StringName = swings.back()
	for press: int in buttons:
		var played: Array[int] = presses.duplicate()
		played.append(press)
		var r: PlayedString = _play(played, 2.2, mx)
		var what: String = "a %s pressed in %s" % ["light" if press == Btn.LIGHT else "heavy", rows[id]["name"]]
		assert_eq(r.ids(&"swing"), swings, "%s starts nothing" % what)
		assert_eq(r.ended_on(id), _length(id), "%s: it ends on startup + active + recovery" % what)
		assert_eq(r.state_after(id), &"free", "%s: then the fighter is free" % what)


## Plays presses (the stick at mx) and checks each one hits, and that the
## string then stops: its last move, one of the spec's rows, ends on startup
## + active + recovery, leaving the fighter free.
func _assert_stops_after(presses: Array[int], mx: float = 0.0) -> void:
	var r: PlayedString = _play(presses, 2.2, mx)
	var what: String = "%s%s" % [_named(presses), " sideways" if mx != 0.0 else ""]
	var hits: Array[StringName] = r.ids(&"hit")
	assert_eq(hits.size(), presses.size(), "every press of %s hits" % what)
	if hits.size() != presses.size():
		return
	var last: StringName = hits.back()
	if not rows.has(last):
		fail_test("%s ends on %s, none of the spec's rows" % [what, last])
		return
	var last_name: String = rows[last]["name"]
	assert_eq(r.ended_on(last), _length(last), "%s: %s ends on startup + active + recovery" % [what, last_name])
	assert_eq(r.state_after(last), &"free", "%s: and the fighter is free after %s" % [what, last_name])


## Checks each of the spec's rows against the weapon's move: its name,
## frames, damage and posture, follow-ups and sides.
func _assert_rows_match_the_spec() -> void:
	for id: StringName in rows:
		var row: Dictionary = rows[id]
		var m: AttackDef = weapon.moves.get(id, null)
		assert_not_null(m, "%s exists" % id)
		if m == null:
			continue
		assert_eq(m.name, row["name"], "%s name" % id)
		assert_eq([m.startup, m.active, m.recovery], row["frames"], "%s frames" % row["name"])
		assert_eq([m.damage, m.posture], [float(row["damage"]), float(row["posture"])], "%s damage and posture" % row["name"])
		assert_eq([m.chain_light, m.chain_heavy], [row["light"], row["heavy"]], "%s follow-ups" % row["name"])
		assert_eq([m.side_start, m.side_end], row["sides"], "%s sides" % row["name"])
