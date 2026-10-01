extends GutTest
## Regression tests for the discrepancies found by the line-by-line review of
## the GDScript port against the TypeScript rules:
## - Math.hypot, Math.sin, Math.cos and Math.atan2 computed exactly as V8 does
##   (JsMath), at every place the TypeScript calls them;
## - optional move fields that hold a value the old sentinels treated as unset
##   (a zero or negative multiInterval, a negative guardCrush, dodgeCancelFrom,
##   lungeEnd, hitstop, hitstun or blockstun);
## - the tools: toFixed with 3 digits, Number() and String() of a number, and
##   the soak's handling of a match that crashes.
## The TypeScript reference values are in game/tests/fixtures/port.json,
## written by scripts/port-fixtures.ts. Floats are stored as their bits and
## compared bit for bit.

const H := preload("res://tests/sim/sim_helpers.gd")
const Soak := preload("res://tools/soak.gd")

var _fx: Dictionary
## [AttackDef, field, old value] for each patched move field, undone after each test
var _patches: Array[Array] = []


func before_all() -> void:
	_fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/port.json"))


func after_each() -> void:
	for p: Array in _patches:
		(p[0] as AttackDef).set(p[1], p[2])
	_patches.clear()
	H.dispose_all()


## The double whose big-endian IEEE-754 bits are the 16 hex digits `hex`.
static func _f(hex: String) -> float:
	var b: PackedByteArray = PackedByteArray()
	b.resize(8)
	b.encode_u32(4, hex.substr(0, 8).hex_to_int())
	b.encode_u32(0, hex.substr(8, 8).hex_to_int())
	return b.decode_double(0)


## The bits of x as 16 hex digits (big-endian), as the fixture writes them.
static func _hex(x: float) -> String:
	var b: PackedByteArray = PackedByteArray()
	b.resize(8)
	b.encode_double(0, x)
	return "%08x%08x" % [b.decode_u32(4), b.decode_u32(0)]


## Bit equality, with every NaN equal to every other NaN.
static func _same(got: float, want_hex: String) -> bool:
	var want: float = _f(want_hex)
	if is_nan(want):
		return is_nan(got)
	return _hex(got) == want_hex


## FNV-1a over 32-bit words, as Hash in scripts/port-fixtures.ts.
class Hash:
	var h: int = 2166136261
	var _b: PackedByteArray = PackedByteArray()

	func _init() -> void:
		_b.resize(8)

	func word(w: int) -> void:
		h = ((h ^ (w & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF

	func num(x: float) -> void:
		_b.encode_double(0, 0.0 if x == 0.0 else x)
		word(_b.decode_u32(4))
		word(_b.decode_u32(0))

	func integer(n: int) -> void:
		word(n)

	func text(s: String) -> void:
		for i: int in s.length():
			word(s.unicode_at(i))

	func fighter(f: Fighter) -> void:
		for x: float in [f.pos.x, f.pos.y, f.pos.z, f.vel.x, f.vel.y, f.vel.z, f.yaw, f.hp, f.posture, f.knock_x, f.knock_z]:
			num(x)
		integer(f.sf)
		text(f.state)
		integer(1 if f.armed else 0)

	func step(W: World, inputs: Array[RawInput]) -> void:
		for i: RawInput in inputs:
			num(i.mx)
			num(i.my)
			integer(i.buttons)
		integer(W.frame)
		integer(W.hitstop)
		for f: Fighter in W.fighters:
			fighter(f)
		for e: Dictionary in W.drain_events():
			text(e["t"])


# ------------------------------------------------------------------ Math.* as V8 computes them

func test_hypot_matches_math_hypot_bit_for_bit() -> void:
	var bad: Array[String] = []
	for r: Array in _fx["hypot"]:
		var got: float = JsMath.hypot(_f(r[0]), _f(r[1]))
		if not _same(got, r[2]):
			bad.append("hypot(%s, %s) = %s, want %s" % [r[0], r[1], _hex(got), r[2]])
	assert_eq(bad, [] as Array[String])
	assert_gt((_fx["hypot"] as Array).size(), 100)


func test_sin_and_cos_match_v8_bit_for_bit() -> void:
	var bad: Array[String] = []
	for r: Array in _fx["sincos"]:
		var a: float = _f(r[0])
		if not _same(JsMath.sin(a), r[1]):
			bad.append("sin(%s) = %s, want %s" % [r[0], _hex(JsMath.sin(a)), r[1]])
		if not _same(JsMath.cos(a), r[2]):
			bad.append("cos(%s) = %s, want %s" % [r[0], _hex(JsMath.cos(a)), r[2]])
	assert_eq(bad, [] as Array[String])


func test_atan2_matches_v8_bit_for_bit() -> void:
	var bad: Array[String] = []
	for r: Array in _fx["atan2"]:
		var got: float = JsMath.atan2(_f(r[0]), _f(r[1]))
		if not _same(got, r[2]):
			bad.append("atan2(%s, %s) = %s, want %s" % [r[0], r[1], _hex(got), r[2]])
	assert_eq(bad, [] as Array[String])


func test_fwd_right_and_yaw_to_use_v8_trig() -> void:
	var bad: Array[String] = []
	for r: Array in _fx["sincos"]:
		var a: float = _f(r[0])
		var f: V2 = SimMath.fwd(a)
		if not (_same(f.x, r[1]) and _same(f.z, r[2])):
			bad.append("fwd(%s)" % r[0])
		var rt: V2 = SimMath.right(a)
		if not (_same(-rt.x, r[2]) and _same(rt.z, r[1])):
			bad.append("right(%s)" % r[0])
	for r: Array in _fx["atan2"]:
		var got: float = SimMath.yaw_to(V3.make(), V3.make(_f(r[0]), 0.0, _f(r[1])))
		if not _same(got, r[2]):
			bad.append("yawTo(%s, %s)" % [r[0], r[1]])
	assert_eq(bad, [] as Array[String])


func test_the_stick_deadzone_uses_math_hypot() -> void:
	# Sticks on the deadzone circle where Math.hypot and sqrt(x*x + y*y) fall on
	# different sides of DIR_DEADZONE.
	for r: Array in _fx["deadzone"]:
		assert_eq(InputTracker.dir_index(_f(r[0]), _f(r[1])), int(r[2]), "dirIndex(%s, %s)" % [r[0], r[1]])


func test_the_arena_clamp_uses_math_hypot() -> void:
	# Positions on the clamp circle where Math.hypot and sqrt(x*x + z*z) fall on
	# different sides of ARENA_RADIUS - FIGHTER_RADIUS; one idle step each.
	for r: Array in _fx["clampArena"]:
		var W: World = H.make_world()
		var a: Fighter = W.fighters[0]
		a.pos = V3.make(_f(r[0]), 0.0, _f(r[1]))
		W.fighters[1].pos = V3.make()
		W.step([H.idle(), H.idle()])
		assert_eq([_hex(a.pos.x), _hex(a.pos.z)], [r[2], r[3]], "clamp from (%s, %s)" % [r[0], r[1]])


# ------------------------------------------------------------------ whole runs, bit for bit

## The inputs of duelP0 and duelP1 in scripts/port-fixtures.ts.
static func _duel_p0(i: int) -> RawInput:
	if i < 40:
		return H.move(0.37, 0.91)
	if i < 100:
		return H.move(1.0, 0.0, Btn.BLOCK) if i < 70 else H.move(1.0, 0.0)
	if i == 100 or i == 108 or i == 116:
		return H.btn(Btn.LIGHT)
	if i >= 130 and i < 170:
		return H.move(-0.6, -0.8, Btn.SPRINT)
	if i == 175:
		return H.move(0.7, 0.2, Btn.DODGE)
	if i >= 190 and i < 215:
		return H.btn(Btn.HEAVY)
	if i == 240:
		return H.move(0.0, 1.0, Btn.JUMP)
	if i == 250:
		return H.btn(Btn.LIGHT)
	if i == 300:
		return H.btn(Btn.HEAVY)
	if i >= 270 and i < 330:
		return H.move(-1.0, 0.25)
	return H.idle()


static func _duel_p1(i: int) -> RawInput:
	if i >= 20 and i < 60:
		return H.btn(Btn.BLOCK)
	if i == 70 or i == 78:
		return H.btn(Btn.LIGHT)
	if i >= 90 and i < 120:
		return H.move(-0.45, 0.2)
	if i == 150:
		return H.btn(Btn.HEAVY)
	if i >= 200 and i < 230:
		return H.btn(Btn.BLOCK)
	if i == 260:
		return H.move(-1.0, 0.0, Btn.DODGE)
	if i >= 280 and i < 300:
		return H.move(0.3, -0.95)
	if i == 320:
		return H.btn(Btn.LIGHT)
	return H.idle()


func test_a_scripted_duel_is_bit_identical_to_the_typescript() -> void:
	var spec: Dictionary = _fx["duel"]
	var want: Array = spec["hashes"]
	var every: int = int(spec["every"])
	var W: World = H.make_world()
	var h: Hash = Hash.new()
	var got: Array[int] = []
	for i: int in int(spec["steps"]):
		var inputs: Array[RawInput] = [_duel_p0(i), _duel_p1(i)]
		W.step(inputs)
		h.step(W, inputs)
		if (i + 1) % every == 0:
			got.append(h.h)
	assert_eq(_first_mismatch(got, want, every), "")


func test_a_computer_match_is_bit_identical_to_the_typescript() -> void:
	var spec: Dictionary = _fx["aiMatch"]
	var want: Array = spec["hashes"]
	var every: int = int(spec["every"])
	var W: World = H.track(World.new(FighterConfig.make(Moves.KATANA), FighterConfig.make(Moves.DAGGERS), 1005))
	var M: Match = Match.new(W)
	var ai: Array[AIBrain] = [
		AIBrain.new(W.fighters[0], AIBrain.DIFFICULTY[&"hard"], 16),
		AIBrain.new(W.fighters[1], AIBrain.DIFFICULTY[&"normal"], 82),
	]
	var h: Hash = Hash.new()
	var got: Array[int] = []
	for i: int in int(spec["steps"]):
		var inputs: Array[RawInput] = [ai[0].think(), ai[1].think()]
		M.step(inputs)
		h.step(W, inputs)
		h.text(M.phase)
		if (i + 1) % every == 0:
			got.append(h.h)
	for b: AIBrain in ai:
		b.dispose()
	assert_eq(_first_mismatch(got, want, every), "")


static func _first_mismatch(got: Array[int], want: Array, every: int) -> String:
	for k: int in want.size():
		if k >= got.size() or got[k] != int(want[k]):
			return "the state hash first differs at the checkpoint after step %d" % ((k + 1) * every)
	return ""


# ------------------------------------------------------------------ optional move fields

## Sets a field of Right Cut (k_l1) for this test only.
func _patch(field: String, value: Variant) -> void:
	var def: AttackDef = Moves.KATANA.moves[&"k_l1"]
	_patches.append([def, field, def.get(field)])
	def.set(field, value)


## Runs the "patched" scenario of scripts/port-fixtures.ts and compares it with
## the recorded case: per step the hit-stop, both states, the hits that step,
## the defender's hp and posture; then the state hash and the attacker's position.
func _check_patched(case_name: String, steps: int, p0: Callable, p1: Callable, setup: Callable = Callable()) -> void:
	var want: Dictionary = _fx["sentinels"][case_name]
	var W: World = H.make_world()
	if not setup.is_null():
		setup.call(W)
	var a: Fighter = W.fighters[0]
	var b: Fighter = W.fighters[1]
	var h: Hash = Hash.new()
	for i: int in steps:
		W.step([p0.call(i), p1.call(i)])
		var events: Array[Dictionary] = W.drain_events()
		var hits: int = events.filter(func(e: Dictionary) -> bool: return e["t"] == &"hit").size()
		var row: Array = [W.hitstop, String(a.state), String(b.state), hits, _hex(b.hp), _hex(b.posture)]
		var exp: Array = (want["trace"] as Array)[i]
		var exp_row: Array = [int(exp[0]), exp[1], exp[2], int(exp[3]), exp[4], exp[5]]
		if row != exp_row:
			assert_eq(row, exp_row, "%s: step %d [hitstop, attacker, defender, hits, hp, posture]" % [case_name, i])
			return
		h.integer(W.hitstop)
		h.fighter(a)
		h.fighter(b)
		for e: Dictionary in events:
			h.text(e["t"])
	assert_eq(h.h, int(want["hash"]), "%s: state hash" % case_name)
	assert_eq([_hex(a.pos.x), _hex(a.pos.z)], want["aPos"] as Array, "%s: attacker position" % case_name)


static func _light_at_0(i: int) -> RawInput:
	return H.btn(Btn.LIGHT) if i == 0 else H.idle()


static func _hold_block(_i: int) -> RawInput:
	return H.btn(Btn.BLOCK)


static func _idle(_i: int) -> RawInput:
	return H.idle()


func test_multi_interval_zero_skips_every_active_frame() -> void:
	# TS: (f - S - 1) % 0 is NaN, NaN !== 0, so no frame ever hits (no error).
	_patch("multi_hit", 3)
	_patch("multi_interval", 0)
	_patch("active", 6)
	_check_patched("multiIntervalZero", 30, _light_at_0, _idle)


func test_a_negative_multi_interval_is_used_as_is() -> void:
	_patch("multi_hit", 3)
	_patch("multi_interval", -2)
	_patch("active", 6)
	_check_patched("multiIntervalNegative", 30, _light_at_0, _idle)


func test_a_negative_guard_crush_is_kept() -> void:
	_patch("guard_crush", -0.5)
	_check_patched("guardCrushNegative", 30, _light_at_0, _hold_block, func(W: World) -> void: W.fighters[1].posture = 40.0)


func test_a_negative_dodge_cancel_frame_cancels_at_once() -> void:
	_patch("dodge_cancel_from", -1)
	var p0: Callable = func(i: int) -> RawInput:
		return H.btn(Btn.LIGHT) if i == 0 else (H.btn(Btn.DODGE) if i == 3 else H.idle())
	_check_patched("dodgeCancelNegative", 12, p0, _idle)


func test_a_negative_lunge_end_means_no_lunge() -> void:
	_patch("lunge_end", -1)
	_check_patched("lungeEndNegative", 30, _light_at_0, _idle, func(W: World) -> void: W.fighters[1].pos.z = 4.0)


func test_negative_hitstop_and_hitstun_are_kept() -> void:
	_patch("hitstop", -3)
	_patch("hitstun", -4)
	_check_patched("hitstopNegative", 30, _light_at_0, _idle)


func test_a_negative_blockstun_is_kept() -> void:
	_patch("blockstun", -5)
	_patch("hitstop", -2)
	_check_patched("blockstunNegative", 30, _light_at_0, _hold_block)


# ------------------------------------------------------------------ tools

func test_to_fixed_matches_js_for_0_to_3_digits() -> void:
	var bad: Array[String] = []
	for r: Array in _fx["toFixed"]:
		var got: String = JsFormat.to_fixed(_f(r[0]), int(r[1]))
		if got != r[2]:
			bad.append("(%s).toFixed(%d) = %s, want %s" % [r[0], int(r[1]), got, r[2]])
	assert_eq(bad, [] as Array[String])


func test_number_parses_a_string_like_js_number() -> void:
	var bad: Array[String] = []
	for r: Array in _fx["number"]:
		var got: float = JsFormat.number(r[0])
		if not _same(got, r[1]) or JsFormat.num(got) != r[2]:
			bad.append("Number(%s) = %s (%s), want %s (%s)" % [JSON.stringify(r[0]), _hex(got), JsFormat.num(got), r[1], r[2]])
	assert_eq(bad, [] as Array[String])


func test_num_prints_like_js_string() -> void:
	var bad: Array[String] = []
	for r: Array in _fx["numToString"]:
		var got: String = JsFormat.num(_f(r[0]))
		if got != r[1]:
			bad.append("String(%s) = %s, want %s" % [r[0], got, r[1]])
	assert_eq(bad, [] as Array[String])


func test_soak_reports_a_crashed_match_and_goes_on() -> void:
	# TS: an exception inside a match is caught, counted as a failure and
	# reported as "match m crashed at frame f: <error>"; the next match runs.
	var lines: Array[String] = []
	var out: Callable = func(s: String) -> void: lines.append(s)
	var crash: Callable = func(m: int, frames: int, W: World) -> void:
		if m == 1 and frames == 150:
			W.fighters[1].opp = null # a null dereference inside the rules
	var failures: int = Soak.run(3.0, out, 240, crash)
	var errors: Array = get_errors()
	for e: GutTrackedError in errors:
		e.handled = true
	assert_gt(errors.size(), 0, "the injected fault raised script errors")
	assert_eq(failures, 3, "two unfinished matches and one crash")
	var crashed: Array[String] = lines.filter(func(s: String) -> bool: return s.begins_with("match 1 crashed at frame 150: "))
	assert_eq(crashed.size(), 1, "one crash line for match 1: %s" % [lines])
	assert_eq(lines.filter(func(s: String) -> bool: return s.begins_with("match 1 (")).size(), 0, "match 1 is not also reported as unfinished")
	assert_eq(lines.filter(func(s: String) -> bool: return s.begins_with("match 2 (")).size(), 1, "match 2 still ran")
	assert_true(lines.has("\n3 matches, 3 failures"), "summary: %s" % [lines])


func test_soak_match_count_is_a_js_number() -> void:
	# TS: N = Number(argv[2] ?? 30); for (m = 0; m < N; m++); prints `${N} matches`
	var lines: Array[String] = []
	var out: Callable = func(s: String) -> void: lines.append(s)
	assert_eq(Soak.run(JsFormat.number("1.5"), out, 1), 2, "1.5 runs two matches (neither finishes in 1 frame)")
	assert_true(lines.has("\n1.5 matches, 2 failures"), "%s" % [lines])
	lines.clear()
	assert_eq(Soak.run(JsFormat.number("abc"), out, 1), 0)
	assert_true(lines.has("\nNaN matches, 0 failures"), "%s" % [lines])
