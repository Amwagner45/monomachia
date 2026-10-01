extends GutTest
## Golden replays (plan task 4): replays every recording of the TypeScript rules
## in game/tests/golden/ on the GDScript rules and compares them step by step.
## scripts/golden/record.ts writes the recordings and documents their format;
## tests/golden.test.ts is the same replay on the TypeScript rules.
##
## For each scenario: build the world (kind "world": World.new, then the
## makeWorld placement at the recorded gap; kind "match": World.new, then
## Match.new), apply the "setup" field writes before their step, feed the
## recorded inputs one step at a time and drain the events after each step.
## Compared:
## - every event, in order: the same keys; names, ints and bools exactly,
##   floats within TOL;
## - every sample: the world's frame, hit-stop and time scale; the match phase,
##   round, wins and phase frames; each fighter's state, timers, hp, posture,
##   position, yaw, velocity, flags and attack; the dropped weapons and the
##   slash waves. Floats within TOL.
## Each scenario is its own test. It stops at its first mismatch and fails with
## the step, the world frame, the field path, the expected and actual values,
## and that step's events on both sides.
##
## The recordings are the reference: a mismatch is a porting error in game/sim.
## Never re-record the files or widen TOL to make a replay pass.
##
## Why floats need a tolerance at all: the port is bit-identical to the
## TypeScript (JsMath gives V8's Math.hypot, sin, cos and atan2;
## test_port_regressions.gd checks whole runs bit for bit), but Godot's JSON
## reader is not correctly rounded: it reads some recorded numbers (inputs
## included) a unit in the last place off. That drifts to about 1e-13 over a
## 15,000-step match, far below TOL.

const DIR: String = "res://tests/golden/"
## Absolute tolerance for floats. Ints, names and bools are compared exactly.
const TOL: float = 1e-6
const GUARD_TEST: String = "test_every_golden_file_has_a_test"

## Largest float difference seen in the current replay.
var _max_dev: float = 0.0


func test_every_golden_file_has_a_test() -> void:
	var names: Array[String] = _index()
	assert_gt(names.size(), 0, "index.json lists the scenarios")
	var listed: Array[String] = names.duplicate()
	listed.sort()
	var files: Array[String] = []
	for f: String in DirAccess.get_files_at(DIR):
		if f.get_extension() == "json" and f != "index.json":
			files.append(f.get_basename())
	files.sort()
	assert_eq(listed, files, "index.json lists every golden file in %s" % DIR)
	var tests: Array[String] = []
	for m: Dictionary in (get_script() as Script).get_script_method_list():
		var n: String = m["name"]
		if n.begins_with("test_") and n != GUARD_TEST and not tests.has(n.trim_prefix("test_")):
			tests.append(n.trim_prefix("test_"))
	tests.sort()
	assert_eq(tests, listed, "one test_<name> below per scenario in index.json")


# One test per scenario, in index.json order.

func test_katana_strings() -> void:
	_check("katana_strings")


func test_katana_charged_heavy_autorelease() -> void:
	_check("katana_charged_heavy_autorelease")


func test_katana_parry_timing() -> void:
	_check("katana_parry_timing")


func test_katana_block_from_behind() -> void:
	_check("katana_block_from_behind")


func test_katana_unblockable_and_power_disarms() -> void:
	_check("katana_unblockable_and_power_disarms")


func test_katana_parry_disarm_recall() -> void:
	_check("katana_parry_disarm_recall")


func test_katana_posture_drain() -> void:
	_check("katana_posture_drain")


func test_katana_dodge_and_stomp() -> void:
	_check("katana_dodge_and_stomp")


func test_greatsword_counters() -> void:
	_check("greatsword_counters")


func test_disarmed_brawl() -> void:
	_check("disarmed_brawl")


func test_disarmed_movement() -> void:
	_check("disarmed_movement")


func test_aerial_and_sprint_attacks() -> void:
	_check("aerial_and_sprint_attacks")


func test_dodge_followups() -> void:
	_check("dodge_followups")


func test_strafe_orbit_steps() -> void:
	_check("strafe_orbit_steps")


func test_wall_knockback_ko() -> void:
	_check("wall_knockback_ko")


func test_charged_heavy_trade() -> void:
	_check("charged_heavy_trade")


func test_ult_moonsplitter() -> void:
	_check("ult_moonsplitter")


func test_ult_chord_and_wave_ko() -> void:
	_check("ult_chord_and_wave_ko")


func test_ult_impaler() -> void:
	_check("ult_impaler")


func test_ult_tempest() -> void:
	_check("ult_tempest")


func test_ult_tempest_one_parry() -> void:
	_check("ult_tempest_one_parry")


func test_disarmed_ult_breaker_palm() -> void:
	_check("disarmed_ult_breaker_palm")


func test_daggers_shadow_step_and_chains() -> void:
	_check("daggers_shadow_step_and_chains")


func test_katana_flash() -> void:
	_check("katana_flash")


func test_guard_crusher_and_alt_abilities() -> void:
	_check("guard_crusher_and_alt_abilities")


func test_regress_weapon_swap() -> void:
	_check("regress_weapon_swap")


func test_mirror_katana() -> void:
	_check("mirror_katana")


func test_mirror_greatsword() -> void:
	_check("mirror_greatsword")


func test_mirror_daggers() -> void:
	_check("mirror_daggers")


func test_match_katana_vs_greatsword() -> void:
	_check("match_katana_vs_greatsword")


func test_match_greatsword_vs_daggers() -> void:
	_check("match_greatsword_vs_daggers")


func test_match_daggers_vs_katana() -> void:
	_check("match_daggers_vs_katana")


func test_match_katana_vs_katana() -> void:
	_check("match_katana_vs_katana")


func test_match_greatsword_vs_greatsword() -> void:
	_check("match_greatsword_vs_greatsword")


func test_match_daggers_vs_daggers() -> void:
	_check("match_daggers_vs_daggers")


# ---------------------------------------------------------------------------
# Replay
# ---------------------------------------------------------------------------


func _index() -> Array[String]:
	var names: Array[String] = []
	names.assign(JSON.parse_string(FileAccess.get_file_as_string(DIR + "index.json")))
	return names


## Loads and replays one scenario; passes, or fails with its first mismatch.
func _check(scenario: String) -> void:
	var path: String = DIR + scenario + ".json"
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		fail_test("%s: cannot read %s: %s (line %d)" % [scenario, path, json.get_error_message(), json.get_error_line()])
		return
	var g: Dictionary = json.data
	_max_dev = 0.0
	var msg: String = _replay(scenario, g)
	if msg != "":
		fail_test(msg)
	else:
		pass_test("%s: %d steps, %d events and %d samples match (largest float difference %s)" % [
			scenario, int(g["steps"]), (g["events"] as Array).size(), (g["samples"] as Array).size(), _fmt(_max_dev)])


## Replays a recording and returns "" when everything matches, or a report of
## the first mismatch.
func _replay(scenario: String, g: Dictionary) -> String:
	if g.get("name") != scenario:
		return "%s: the file is named %s" % [scenario, _fmt(g.get("name"))]
	var steps: int = int(g["steps"])
	var inputs: Array = g["inputs"]
	var setup: Array = g["setup"]
	var samples: Array = g["samples"]
	var events: Array = g["events"]
	var every: int = int(g["sample_every"])
	if inputs.size() != steps:
		return "%s: %d input rows for %d steps" % [scenario, inputs.size(), steps]

	var W: World = World.new(_config(g["p1"]), _config(g["p2"]), int(g["seed"]))
	var M: Match = null
	match String(g["kind"]):
		"world":
			# tests/helpers.ts makeWorld, at the recorded gap
			var gap: float = g["gap"]
			var a: Fighter = W.fighters[0]
			var b: Fighter = W.fighters[1]
			a.pos = V3.make(0.0, 0.0, -gap / 2.0)
			b.pos = V3.make(0.0, 0.0, gap / 2.0)
			a.yaw = 0.0
			b.yaw = PI
			a.set_state(&"free")
			b.set_state(&"free")
		"match":
			M = Match.new(W) # emits roundStart, drained with step 0's events
		_:
			W.dispose()
			return "%s: unknown kind %s" % [scenario, _fmt(g["kind"])]

	var msg: String = ""
	var next_setup: int = 0
	var next_event: int = 0
	var next_sample: int = 0
	for i: int in steps:
		while msg == "" and next_setup < setup.size() and int(setup[next_setup]["step"]) == i:
			var bad: String = _apply_setup(W, setup[next_setup])
			if bad != "":
				msg = "%s: setup entry %d (step %d): %s" % [scenario, next_setup, i, bad]
			next_setup += 1
		if msg != "":
			break
		var row: Array = inputs[i]
		var step_inputs: Array[RawInput] = [
			RawInput.make(row[0], row[1], int(row[2])),
			RawInput.make(row[3], row[4], int(row[5])),
		]
		if M != null:
			M.step(step_inputs)
		else:
			W.step(step_inputs)
		var got: Array[Dictionary] = W.drain_events()
		var expected: Array = []
		while next_event < events.size() and int(events[next_event]["step"]) == i:
			expected.append(events[next_event]["e"])
			next_event += 1
		var diff: String = _diff_events(got, expected)
		if diff == "" and (i % every == every - 1 or i == steps - 1):
			if next_sample >= samples.size() or int(samples[next_sample]["step"]) != i:
				diff = "sample: the file has no sample for step %d" % i
			else:
				diff = _diff("sample", _sample(i, W, M), samples[next_sample])
				next_sample += 1
		if diff != "":
			msg = _report(scenario, i, W, M, diff, expected, got)
			break

	if msg == "":
		if next_setup != setup.size():
			msg = "%s: %d setup entries were never applied" % [scenario, setup.size() - next_setup]
		elif next_event != events.size():
			msg = "%s: %d recorded events come after the last step" % [scenario, events.size() - next_event]
		elif next_sample != samples.size():
			msg = "%s: %d recorded samples come after the last step" % [scenario, samples.size() - next_sample]
	W.dispose()
	return msg


## { weapon, abilities }: abilities null means the weapon's default abilities.
func _config(p: Dictionary) -> FighterConfig:
	var ab: Array = [] if p["abilities"] == null else p["abilities"]
	return FighterConfig.make(Moves.WEAPONS[StringName(p["weapon"])], ab)


## Applies one "setup" entry, a direct field write. Returns "" or an error.
func _apply_setup(W: World, s: Dictionary) -> String:
	var f: Fighter = W.fighters[int(s["fighter"])]
	var v: Variant = s["value"]
	match String(s["field"]):
		"hp":
			f.hp = v
		"posture":
			f.posture = v
		"yaw":
			f.yaw = v
		"blind_until":
			f.blind_until = int(v)
		"last_posture_damage":
			f.last_posture_damage = int(v)
		"armed":
			f.armed = v
		"pos":
			f.pos = V3.make(v["x"], v["y"], v["z"]) # a new vector, as the TS
		"weapon":
			f.weapon = Moves.WEAPONS[StringName(v)]
		"abilities":
			# a new array: never change the current one in place, it may be
			# the weapon's default_abilities
			var ids: Array[StringName] = [StringName(v[0]), StringName(v[1])]
			f.abilities = ids
		_:
			return "unknown field %s" % _fmt(s["field"])
	return ""


## A sample in the recording's shape (see scripts/golden/record.ts).
func _sample(i: int, W: World, M: Match) -> Dictionary:
	var m: Variant = null
	if M != null:
		m = {"phase": M.phase, "round": M.round, "wins": [M.wins[0], M.wins[1]], "phaseFrames": M.phase_frames}
	var weapons: Array = []
	for w: DroppedWeapon in W.weapons:
		weapons.append([w.owner, w.pos.x, w.pos.y, w.pos.z, w.grounded])
	var waves: Array = []
	for w: SlashWave in W.waves:
		waves.append([w.owner.id, w.s, w.alive])
	return {
		"step": i,
		"frame": W.frame,
		"hitstop": W.hitstop,
		"timeScale": W.time_scale(),
		"match": m,
		"fighters": [_fighter(W.fighters[0]), _fighter(W.fighters[1])],
		"weapons": weapons,
		"waves": waves,
	}


func _fighter(f: Fighter) -> Dictionary:
	var atk: Variant = null
	if f.atk != null:
		atk = {
			"id": f.atk.def.id,
			"frame": f.atk.frame,
			"charging": f.atk.charging,
			"chargeFrames": f.atk.charge_frames,
			"hitDone": f.atk.hit_done,
		}
	return {
		"state": f.state,
		"sf": f.sf,
		"stateDur": f.state_dur,
		"hp": f.hp,
		"posture": f.posture,
		"x": f.pos.x,
		"y": f.pos.y,
		"z": f.pos.z,
		"yaw": f.yaw,
		"vx": f.vel.x,
		"vy": f.vel.y,
		"vz": f.vel.z,
		"armed": f.armed,
		"blocking": f.blocking,
		"ultUsed": f.ult_used,
		"atk": atk,
	}


# ---------------------------------------------------------------------------
# Comparison
# ---------------------------------------------------------------------------


## The first difference between one step's events, or "".
func _diff_events(got: Array[Dictionary], expected: Array) -> String:
	for k: int in mini(got.size(), expected.size()):
		var d: String = _diff("events[%d] (%s)" % [k, expected[k].get("t")], got[k], expected[k])
		if d != "":
			return d
	if got.size() != expected.size():
		return "events: expected %d at this step, got %d" % [expected.size(), got.size()]
	return ""


## The first difference between a value the port produced and the recorded one
## (as Godot's JSON parser gives it back: every number is a float), or "".
## Ints compare exactly, floats within TOL, names (String or StringName) and
## bools exactly; Dictionaries need the same keys, Arrays the same size.
func _diff(path: String, got: Variant, expected: Variant) -> String:
	match typeof(expected):
		TYPE_FLOAT:
			var e: float = expected
			if typeof(got) == TYPE_INT:
				if float(got) != e:
					return _mismatch(path, expected, got)
			elif typeof(got) == TYPE_FLOAT:
				var d: float = absf(float(got) - e)
				if not (d <= TOL): # also catches NaN
					return _mismatch(path, expected, got)
				_max_dev = maxf(_max_dev, d)
			else:
				return _mismatch(path, expected, got)
		TYPE_STRING:
			if not (typeof(got) == TYPE_STRING or typeof(got) == TYPE_STRING_NAME) or String(got) != expected:
				return _mismatch(path, expected, got)
		TYPE_BOOL:
			if typeof(got) != TYPE_BOOL or bool(got) != bool(expected):
				return _mismatch(path, expected, got)
		TYPE_NIL:
			if got != null:
				return _mismatch(path, expected, got)
		TYPE_DICTIONARY:
			if typeof(got) != TYPE_DICTIONARY:
				return _mismatch(path, expected, got)
			var gd: Dictionary = got
			var ed: Dictionary = expected
			for k: Variant in ed:
				if not gd.has(k):
					return "%s: missing key \"%s\" (expected %s)" % [path, k, _fmt(ed[k])]
			for k: Variant in gd:
				if not ed.has(k):
					return "%s: unexpected key \"%s\" (got %s)" % [path, k, _fmt(gd[k])]
			for k: Variant in ed:
				var d: String = _diff("%s.%s" % [path, k], gd[k], ed[k])
				if d != "":
					return d
		TYPE_ARRAY:
			if typeof(got) != TYPE_ARRAY:
				return _mismatch(path, expected, got)
			var ga: Array = got
			var ea: Array = expected
			if ga.size() != ea.size():
				return "%s: expected %d items, got %d\n    expected: %s\n    got:      %s" % [
					path, ea.size(), ga.size(), _fmt(ea), _fmt(ga)]
			for k: int in ea.size():
				var d: String = _diff("%s[%d]" % [path, k], ga[k], ea[k])
				if d != "":
					return d
		_:
			return "%s: the recording holds an unexpected %s" % [path, type_string(typeof(expected))]
	return ""


func _mismatch(path: String, expected: Variant, got: Variant) -> String:
	return "%s: expected %s, got %s (%s)" % [path, _fmt(expected), _fmt(got), type_string(typeof(got))]


## A value as JSON, floats with 17 significant digits. Whole-number floats
## print as ints, the way the recordings write them (the JSON reader gives
## every number back as a float).
static func _fmt(v: Variant) -> String:
	return JSON.stringify(_whole_as_int(v), "", false, true)


static func _whole_as_int(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var x: float = v
			return int(x) if x == floorf(x) and absf(x) < 9007199254740992.0 else x
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var out: Dictionary = {}
			for k: Variant in d:
				out[k] = _whole_as_int(d[k])
			return out
		TYPE_ARRAY:
			var out: Array = []
			for x: Variant in v:
				out.append(_whole_as_int(x))
			return out
	return v


func _report(scenario: String, i: int, W: World, M: Match, diff: String, expected: Array, got: Array[Dictionary]) -> String:
	var lines: PackedStringArray = []
	var where: String = "step %d, world frame %d" % [i, W.frame]
	if M != null:
		where += ", round %d %s" % [M.round, M.phase]
	lines.append("golden %s: first mismatch at %s" % [scenario, where])
	lines.append("  " + diff)
	lines.append("  events of step %d, recorded by the TypeScript rules:" % i)
	lines.append_array(_event_lines(expected))
	lines.append("  events of step %d, from the GDScript rules:" % i)
	lines.append_array(_event_lines(got))
	return "\n".join(lines)


func _event_lines(events: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	if events.is_empty():
		out.append("    (none)")
	for e: Variant in events:
		out.append("    " + _fmt(e))
	return out
