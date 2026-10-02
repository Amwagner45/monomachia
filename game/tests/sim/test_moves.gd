extends GutTest
## Checks every field of every weapon and move against the TypeScript data after
## finalizeMoves (game/tests/fixtures/moves.json, written by
## scripts/sim-fixtures.ts), apart from the rebuild's deliberate changes (the
## changes table). The fixture has the TS camelCase keys; a missing key was
## undefined in the TS and must hold the port's sentinel.

## The sentinel each optional field holds when the TS leaves it undefined
## (see attack_def.gd).
const UNSET: Dictionary = {
	"min_range": 0.0,
	"lunge": 0.0,
	"lunge_start": 0,
	"lunge_end": AttackDef.UNSET,
	"unblockable": false,
	"counter": &"",
	"jumpable": false,
	"undodgeable": false,
	"power": false,
	"chain_light": &"",
	"chain_heavy": &"",
	"dodge_cancel_from": AttackDef.UNSET,
	"multi_hit": 0,
	"multi_interval": AttackDef.UNSET,
	"airborne": false,
	"guard_crush": NAN,
	"special": &"",
	"chargeable": false,
	"sound": &"",
	"invuln": [],
	"hop": 0.0,
}

## The demo's data that the rebuild changed on purpose, one row per rule: a
## move of this kind whose field held "was" in the TS (the port's sentinel
## where the TS left it unset) now holds "now", a value or a function of the
## move's TS record. Every move and field no row covers still matches the demo.
## (A static var, as a const can't hold a function.)
static var changes: Array[Dictionary] = [
	# 8.7: the lights' default hitstun (bare hands keep their own 16)
	{"field": "hitstun", "kind": "light", "was": 18, "now": 14},
	# 8.8: heavies dodge-cancel from startup + active + half the recovery,
	# rounded up (the demo gave them no cancel)
	{
		"field": "dodge_cancel_from", "kind": "heavy", "was": AttackDef.UNSET,
		"now": func(ts: Dictionary) -> int: return int(ts["startup"]) + int(ts["active"]) + ceili(float(ts["recovery"]) / 2.0),
	},
]

var _fx: Dictionary


func before_all() -> void:
	_fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/moves.json"))


## Brings a GDScript or JSON value to a common form: numbers as float, names as
## String, arrays as plain Arrays.
static func _norm(v: Variant) -> Variant:
	match typeof(v):
		TYPE_INT:
			return float(v)
		TYPE_STRING_NAME:
			return String(v)
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY:
			var out: Array = []
			for e: Variant in v:
				out.append(_norm(e))
			return out
	return v


static func _same(a: Variant, b: Variant) -> bool:
	var na: Variant = _norm(a)
	var nb: Variant = _norm(b)
	if typeof(na) == TYPE_FLOAT and typeof(nb) == TYPE_FLOAT and is_nan(na) and is_nan(nb):
		return true # the NAN sentinel
	return typeof(na) == typeof(nb) and na == nb


## The value a move's field should hold: its TS value (or sentinel), or a
## changes row's.
static func _wanted(ts: Dictionary, field: String, ts_value: Variant) -> Variant:
	for row: Dictionary in changes:
		if row["field"] == field and _same(ts.get("kind"), row["kind"]) and _same(ts_value, row["was"]):
			var now: Variant = row["now"]
			return (now as Callable).call(ts) if now is Callable else now
	return ts_value


## Compares one AttackDef with its TS record; returns the differences.
func _diff_move(where: String, m: AttackDef, ts: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if m == null:
		return ["%s: missing in GDScript" % where]
	var seen: Dictionary = {}
	for key: String in ts:
		var snake: String = key.to_snake_case()
		seen[snake] = true
		if not AttackDef.KEYS.has(snake):
			out.append("%s: TS field %s has no AttackDef field" % [where, key])
		else:
			var want: Variant = _wanted(ts, snake, ts[key])
			if not _same(m.get(snake), want):
				out.append("%s.%s: got %s, want %s" % [where, snake, m.get(snake), want])
	for snake: String in AttackDef.KEYS:
		if seen.has(snake):
			continue
		if not UNSET.has(snake):
			out.append("%s.%s: unset in TS but finalizeMoves should set it" % [where, snake])
		else:
			var want: Variant = _wanted(ts, snake, UNSET[snake])
			if not _same(m.get(snake), want):
				out.append("%s.%s: got %s, want %s (the TS left it unset)" % [where, snake, m.get(snake), want])
	return out


func test_every_attack_def_field_is_a_key() -> void:
	var props: Array[String] = []
	for p: Dictionary in AttackDef.new().get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			props.append(String(p["name"]))
	assert_eq(props, AttackDef.KEYS)
	var wprops: Array[String] = []
	for p: Dictionary in WeaponDef.new().get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			wprops.append(String(p["name"]))
	assert_eq(wprops, WeaponDef.KEYS)


func test_registry_matches_the_typescript() -> void:
	var ts_weapons: Dictionary = _fx["WEAPONS"]
	assert_eq(_norm(Moves.WEAPONS.keys()), ts_weapons.keys())
	assert_eq(_norm(Moves.PLAYABLE_WEAPONS), _fx["PLAYABLE_WEAPONS"])
	var ts_lunge: Dictionary = _fx["COUNTER_LUNGE"]
	assert_eq(_norm(Moves.COUNTER_LUNGE.keys()), ts_lunge.keys())
	for w: StringName in Moves.COUNTER_LUNGE:
		assert_eq(String(Moves.COUNTER_LUNGE[w]), String(ts_lunge[String(w)]))
	assert_same(Moves.WEAPONS[&"katana"], Moves.KATANA)
	assert_same(Moves.WEAPONS[&"greatsword"], Moves.GREATSWORD)
	assert_same(Moves.WEAPONS[&"daggers"], Moves.DAGGERS)
	assert_same(Moves.WEAPONS[&"fists"], Moves.FISTS)


func test_every_weapon_field_matches_the_typescript() -> void:
	var ts_weapons: Dictionary = _fx["WEAPONS"]
	for wid: String in ts_weapons:
		var ts: Dictionary = ts_weapons[wid]
		var w: WeaponDef = Moves.WEAPONS.get(StringName(wid), null)
		assert_not_null(w, wid)
		if w == null:
			continue
		var diffs: Array[String] = []
		for key: String in ts:
			var snake: String = key.to_snake_case()
			if not WeaponDef.KEYS.has(snake):
				diffs.append("%s: TS field %s has no WeaponDef field" % [wid, key])
			elif snake != "moves" and not _same(w.get(snake), ts[key]):
				diffs.append("%s.%s: got %s, want %s" % [wid, snake, w.get(snake), ts[key]])
		for snake: String in WeaponDef.KEYS:
			if not ts.has(snake.to_camel_case()):
				diffs.append("%s.%s: not in the TS weapon" % [wid, snake])
		assert_eq(diffs, [] as Array[String], wid)


func test_every_move_of_every_weapon_matches_the_typescript() -> void:
	var ts_weapons: Dictionary = _fx["WEAPONS"]
	var compared: int = 0
	for wid: String in ts_weapons:
		var ts_moves: Dictionary = ts_weapons[wid]["moves"]
		var w: WeaponDef = Moves.WEAPONS[StringName(wid)]
		assert_eq(_norm(w.moves.keys()), ts_moves.keys(), "%s move order" % wid)
		var diffs: Array[String] = []
		for mid: String in ts_moves:
			diffs.append_array(_diff_move("%s.%s" % [wid, mid], w.moves.get(StringName(mid), null), ts_moves[mid]))
			compared += 1
		assert_eq(diffs, [] as Array[String], wid)
	# 18 katana + 16 greatsword + 18 daggers + 15 fists
	assert_eq(compared, 67)


func test_every_ultimate_hit_matches_the_typescript() -> void:
	var ts_hits: Dictionary = _fx["ULT_HITS"]
	assert_eq(_norm(Moves.ULT_HITS.keys()), ts_hits.keys())
	var diffs: Array[String] = []
	for mid: String in ts_hits:
		diffs.append_array(_diff_move("ULT_HITS.%s" % mid, Moves.ULT_HITS.get(StringName(mid), null), ts_hits[mid]))
	assert_eq(diffs, [] as Array[String])
	assert_eq(ts_hits.size(), 6)


func test_finalize_keeps_u_impale_dodgeable() -> void:
	var impale: AttackDef = Moves.ULT_HITS[&"u_impale"]
	assert_true(impale.unblockable)
	assert_false(impale.undodgeable)
	assert_true(Moves.ULT_HITS[&"u_burst"].undodgeable)
	assert_true(Moves.KATANA.moves[&"k_thrust"].undodgeable)
	assert_eq(Moves.ULT_HITS[&"u_moon_v"].trail, &"danger")
	assert_eq(Moves.ULT_HITS[&"u_tempest"].trail, &"ult")


func test_values_are_in_their_unions() -> void:
	var all: Array[AttackDef] = []
	for w: WeaponDef in Moves.WEAPONS.values():
		all.append_array(w.moves.values())
		assert_true(WeaponDef.WEAPON_IDS.has(w.id), String(w.id))
		assert_true(WeaponDef.ULTIMATE_IDS.has(w.ultimate), String(w.ultimate))
		assert_true(WeaponDef.WEAPON_CLASSES.has(w.cls), String(w.cls))
	all.append_array(Moves.ULT_HITS.values())
	for m: AttackDef in all:
		assert_true(AttackDef.ATTACK_KINDS.has(m.kind), "%s kind" % m.id)
		assert_true(AttackDef.ATTACK_TYPES.has(m.type), "%s type" % m.id)
		assert_true(AttackDef.HANDS.has(m.hand), "%s hand" % m.id)
		assert_true(AttackDef.TRAILS.has(m.trail), "%s trail" % m.id)
		assert_true(m.counter == &"" or AttackDef.COUNTER_KINDS.has(m.counter), "%s counter" % m.id)
		assert_true(m.sound == &"" or AttackDef.HIT_SOUNDS.has(m.sound), "%s sound" % m.id)
		assert_true(m.special == &"" or AttackDef.SPECIALS.has(m.special), "%s special" % m.id)


func test_get_move_falls_back_to_ultimate_hits() -> void:
	assert_same(Moves.get_move(Moves.KATANA, &"k_l1"), Moves.KATANA.moves[&"k_l1"])
	assert_same(Moves.get_move(Moves.FISTS, &"u_burst"), Moves.ULT_HITS[&"u_burst"])
	assert_eq(Moves.KATANA.moves[&"k_l1"].total_frames(), 30)


func test_get_move_reports_an_unknown_move() -> void:
	assert_null(Moves.get_move(Moves.KATANA, &"g_l1"))
	assert_push_error("Unknown move g_l1 for katana")
