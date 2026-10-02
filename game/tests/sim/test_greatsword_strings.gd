extends WeaponStringsTest
## The Greatsword's new strings (plan task 10): the spec's Greatsword table,
## played through the rules. Expected numbers come from the spec, not the
## code.

## The spec's Greatsword table, the rows built so far (10.1: the L-L-H; see
## WeaponStringsTest.rows). Overhead Strike's heavy follow-up, g_h2, becomes
## Low Sweep in 10.2.
const ROWS: Dictionary[StringName, Dictionary] = {
	&"g_l1": {
		"name": "Heavy Swing", "frames": [14, 4, 22], "damage": 9, "posture": 11,
		"light": &"g_l2", "heavy": &"g_h1", "sides": [&"right", &"left"],
	},
	&"g_l2": {
		"name": "Backswing", "frames": [11, 4, 22], "damage": 9, "posture": 11,
		"light": &"", "heavy": &"g_h1", "sides": [&"left", &"right"],
	},
	&"g_h1": {
		"name": "Overhead Strike", "frames": [26, 5, 32], "damage": 18, "posture": 22,
		"light": &"", "heavy": &"g_h2", "sides": [&"centre", &"right"],
	},
}

## A heavy held past its frame 9 charges, standing still, and releases by
## itself 150 frames (2.5 s) later as a full charge, 1.8 times as strong (the
## demo's charge, which Overhead Strike keeps from Crushing Blow).
const CHARGE_FROM: int = 9
const CHARGE_MAX: int = 150



func _init() -> void:
	weapon = Moves.GREATSWORD
	rows = ROWS


# ------------------------------------------------------------------ the momentum lights

func test_two_lights_then_a_heavy_hit_with_heavy_swing_backswing_and_overhead_strike() -> void:
	var light: int = Btn.LIGHT
	var heavy: int = Btn.HEAVY
	assert_eq(_play([light, light]).ids(&"hit"), [&"g_l1", &"g_l2"] as Array[StringName], "L-L: Heavy Swing, Backswing")
	assert_eq(
		_play([light, light, heavy]).ids(&"hit"),
		[&"g_l1", &"g_l2", &"g_h1"] as Array[StringName],
		"L-L-H: Heavy Swing, Backswing, Overhead Strike",
	)
	assert_eq(_play([light, heavy]).ids(&"hit"), [&"g_l1", &"g_h1"] as Array[StringName], "L-H: Heavy Swing, Overhead Strike")


func test_backswing_swings_sooner_than_heavy_swing_riding_its_momentum() -> void:
	var r: PlayedString = _play([Btn.LIGHT, Btn.LIGHT])
	var swung_on: Array[int] = []
	for e: Dictionary in r.all(&"swing"):
		if e["f"] == 0:
			swung_on.append(r.frame[int(e["step"])])
	assert_eq(swung_on, [14, 11] as Array[int], "Heavy Swing swings on its frame 14, and Backswing on its 11")


func test_a_light_starts_nothing_after_backswing() -> void:
	_assert_starts_nothing_in([Btn.LIGHT, Btn.LIGHT], [&"g_l1", &"g_l2"], [Btn.LIGHT])


# ------------------------------------------------------------------ Overhead Strike

func test_a_heavy_from_neutral_is_overhead_strike() -> void:
	assert_eq(_play([Btn.HEAVY]).ids(&"hit"), [&"g_h1"] as Array[StringName])


func test_a_held_heavy_charges_overhead_strike_standing_still() -> void:
	# heavy held for 60 steps with the stick to the right
	var r: PlayedString = _run(func(i: int) -> RawInput: return H.move(1.0, 0.0, Btn.HEAVY) if i < 60 else H.idle())
	assert_eq(r.charging.find(true), CHARGE_FROM + 1, "charging once its first 9 frames have passed")
	assert_eq(r.charging.rfind(true), 59, "until heavy is let go on step 60")
	assert_eq(r.walked(0, 60), 0.0, "standing still meanwhile, the stick to the side")
	assert_eq(r.ids(&"hit"), [&"g_h1"] as Array[StringName], "then Overhead Strike hits")
	var startup: int = ROWS[&"g_h1"]["frames"][0]
	assert_eq(r.step_of(&"hit") - 60, startup - CHARGE_FROM, "17 frames after the release: the rest of its 26-frame startup")


func test_an_overhead_strike_held_for_2_5_s_releases_by_itself_as_a_stronger_power_attack() -> void:
	var r: PlayedString = _run(func(i: int) -> RawInput: return H.btn(Btn.HEAVY) if i < 220 else H.idle())
	var release: int = r.charging.rfind(true) + 1
	assert_eq(release, CHARGE_FROM + CHARGE_MAX, "the charge ends 150 frames (2.5 s) in, heavy still held")
	assert_eq(r.ids(&"hit"), [&"g_h1"] as Array[StringName], "and Overhead Strike hits")
	assert_almost_eq(float(r.find(&"hit").get("damage", NAN)), 18.0 * 1.8, CLOSE, "with a full charge's damage")


func test_overhead_strike_charges_as_the_l_l_hs_finisher_too() -> void:
	# a held heavy charges however the heavy started, as the demo's Twin Fang
	# does after the Daggers' lights: the L-L-H pressed as _play presses it,
	# with the heavy then held to the end
	var tapped: PlayedString = _play([Btn.LIGHT, Btn.LIGHT, Btn.HEAVY])
	var swung: Array[int] = []
	for e: Dictionary in tapped.all(&"swing"):
		if e["f"] == 0:
			swung.append(e["step"])
	assert_eq(swung.size(), 3, "the L-L-H swings three times")
	if swung.size() < 3:
		return
	var second_light: int = swung[0] + 1
	var heavy_from: int = swung[1] + 1
	var held_finisher: Callable = func(i: int) -> RawInput:
		if i == 0 or i == second_light:
			return H.btn(Btn.LIGHT)
		return H.btn(Btn.HEAVY) if i >= heavy_from else H.idle()
	var r: PlayedString = _run(held_finisher)
	var charged_from: int = r.charging.find(true)
	assert_eq(
		[r.attack[charged_from], r.frame[charged_from]] if charged_from >= 0 else [],
		[&"g_h1", CHARGE_FROM],
		"Overhead Strike charges from its frame 9",
	)
	assert_eq(r.ids(&"hit"), [&"g_l1", &"g_l2", &"g_h1"] as Array[StringName], "and the string hits three times")
	assert_almost_eq(float(r.all(&"hit").back().get("damage", NAN)), 18.0 * 1.8, CLOSE, "the last as a full charge, released by itself")


func test_a_light_starts_no_backswing_out_of_overhead_strike() -> void:
	_assert_starts_nothing_in([Btn.HEAVY], [&"g_h1"], [Btn.LIGHT])
	_assert_starts_nothing_in([Btn.LIGHT, Btn.LIGHT, Btn.HEAVY], [&"g_l1", &"g_l2", &"g_h1"], [Btn.LIGHT])


func test_stopping_after_any_hit_ends_the_string_when_that_move_ends() -> void:
	var light: int = Btn.LIGHT
	var heavy: int = Btn.HEAVY
	var strings: Array = [[light], [light, light], [heavy], [light, heavy], [light, light, heavy]]
	for presses: Array in strings:
		var typed: Array[int] = []
		typed.assign(presses)
		_assert_stops_after(typed)


# ------------------------------------------------------------------ the spec's table

func test_its_rows_match_the_spec_table() -> void:
	_assert_rows_match_the_spec()


func test_overhead_strike_is_an_overhead_with_crushing_blows_cone() -> void:
	# until weapon paths decide hits (task 7): an overhead (the stand-in's
	# overhead pose) with Crushing Blow's reach, width, lunge, knockback and
	# hitstop
	var m: AttackDef = Moves.GREATSWORD.moves[&"g_h1"]
	assert_eq([m.type, m.anim], [&"overhead", &"overhead"], "an overhead")
	assert_eq(
		[m.range, m.arc, m.lunge, m.lunge_start, m.lunge_end, m.knockback, m.hitstop],
		[3.1, 90.0, 0.7, 10, 30, 1.6, 9],
		"range, arc, lunge and its window, knockback and hitstop",
	)


func test_backswings_lunge_and_dodge_cancel_keep_pace_with_its_faster_start() -> void:
	# the lunge ends one frame after the cut starts, and the dodge cancel
	# opens 8 frames after the cut ends, as Heavy Swing's do (15 and 26)
	var m: AttackDef = Moves.GREATSWORD.moves[&"g_l2"]
	assert_eq([m.lunge, m.lunge_end, m.dodge_cancel_from], [0.4, 12, 23])
