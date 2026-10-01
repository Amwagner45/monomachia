extends GutTest
## Computer opponent parity with the TypeScript rules.
##
## Every golden of kind "match" (game/tests/golden/, see scripts/golden/record.ts)
## was recorded from two TypeScript AIBrains playing a full Match. This test
## rebuilds the same world, match and brains (difficulties and seeds from the
## file, constructed as scripts/soak.ts does), and on every step checks that
## the GDScript brains produce exactly the recorded inputs before feeding them
## to Match.step: stick axes within 1e-9, buttons exactly.
##
## The training dummy is checked against input hashes computed on the
## TypeScript rules (TRAINING_TS).

const GOLDEN_DIR: String = "res://tests/golden/"
const AXIS_EPS: float = 1e-9


func test_brains_reproduce_every_recorded_match() -> void:
	var names: Array = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_DIR + "index.json"))
	var checked: int = 0
	for n: Variant in names:
		var g: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_DIR + String(n) + ".json"))
		if g["kind"] != "match":
			continue
		checked += 1
		var res: Dictionary = _replay(g)
		assert_eq(res["divergence"], "", "%s: the brains' inputs match the recording" % n)
		assert_eq(res["steps"], int(g["steps"]), "%s: every recorded step was checked" % n)
	assert_eq(checked, 6, "six computer-vs-computer goldens")


## The training dummy has no golden: these rows were computed once on the
## TypeScript rules with the same loop as _run_dummy() (a one-off script, the
## counterlab setup with a normal AIBrain, seed 3, as the opponent, 900 frames).
## Columns: dummy weapon, behaviour, hash of the dummy's inputs, hash of the
## opponent brain's inputs, number of events.
const TRAINING_TS: Array = [
	[&"katana", &"idle", 18928174, 742802046, 20],
	[&"katana", &"block", 149590661, 706812111, 30],
	[&"katana", &"lights", 271113821, 71571802, 54],
	[&"katana", &"heavies", 549089881, 234484374, 47],
	[&"katana", &"random", 638851728, 598948748, 50],
	[&"katana", &"fight", 720519920, 329417224, 47],
	[&"greatsword", &"random", 894814593, 673046620, 48],
	[&"daggers", &"random", 241634207, 244123034, 53],
]
const TRAINING_FRAMES: int = 900
const HASH_P: int = 1000000007


func test_training_dummy_behaviours_match_the_typescript_rules() -> void:
	for row: Array in TRAINING_TS:
		var got: Array[int] = _run_dummy(row[0], row[1])
		var label: String = "%s %s" % [row[0], row[1]]
		assert_eq(got[0], int(row[2]), label + ": the dummy's inputs match")
		assert_eq(got[1], int(row[3]), label + ": the opponent brain's inputs match")
		assert_eq(got[2], int(row[4]), label + ": the event count matches")


## Returns [dummy input hash, opponent input hash, event count].
static func _run_dummy(weapon: StringName, behaviour: StringName) -> Array[int]:
	var W: World = World.new(FighterConfig.make(Moves.WEAPONS[weapon]), FighterConfig.make(Moves.KATANA), 5)
	for f: Fighter in W.fighters:
		f.set_state(&"free")
	var dummy: TrainingBrain = TrainingBrain.new(W.fighters[0])
	dummy.set_behaviour(behaviour)
	var ai: AIBrain = AIBrain.new(W.fighters[1], AIBrain.DIFFICULTY[&"normal"], 3)
	var h0: int = 0
	var h1: int = 0
	var events: int = 0
	for _i: int in TRAINING_FRAMES:
		var in0: RawInput = dummy.think()
		var in1: RawInput = ai.think()
		h0 = _mix(h0, in0)
		h1 = _mix(h1, in1)
		W.step([in0, in1])
		events += W.drain_events().size()
		for f: Fighter in W.fighters:
			f.hp = 100.0
			f.posture = 0.0
			if f.state == &"ko":
				f.set_state(&"free")
	dummy.dispose()
	ai.dispose()
	W.dispose()
	return [h0, h1, events]


static func _mix(h: int, r: RawInput) -> int:
	return (
		(h * 33 + r.buttons * 7 + SimMath.js_round((r.mx + 2.0) * 100.0) * 3 + SimMath.js_round((r.my + 2.0) * 100.0))
		% HASH_P
	)


static func _cfg(p: Dictionary) -> FighterConfig:
	var abilities: Array = [] if p["abilities"] == null else p["abilities"]
	return FighterConfig.make(Moves.WEAPONS[StringName(p["weapon"])], abilities)


## Plays the golden's match with fresh brains. Returns { "divergence": the
## first mismatch described, or "", "steps": steps checked without one }.
static func _replay(g: Dictionary) -> Dictionary:
	var W: World = World.new(_cfg(g["p1"]), _cfg(g["p2"]), int(g["seed"]))
	var M: Match = Match.new(W)
	var specs: Array = g["ai"]
	var ai: Array[AIBrain] = []
	for k: int in 2:
		var spec: Dictionary = specs[k]
		ai.append(AIBrain.new(W.fighters[k], AIBrain.DIFFICULTY[StringName(spec["difficulty"])], int(spec["seed"])))
	var inputs: Array = g["inputs"]
	var divergence: String = ""
	var steps: int = 0
	for i: int in int(g["steps"]):
		# scripts/soak.ts host order: fighter 0's brain thinks first
		var got: Array[RawInput] = [ai[0].think(), ai[1].think()]
		var row: Array = inputs[i]
		for k: int in 2:
			var exp_mx: float = row[k * 3]
			var exp_my: float = row[k * 3 + 1]
			var exp_buttons: int = int(row[k * 3 + 2])
			var r: RawInput = got[k]
			if absf(r.mx - exp_mx) > AXIS_EPS or absf(r.my - exp_my) > AXIS_EPS or r.buttons != exp_buttons:
				divergence = (
					"step %d (world frame %d), fighter %d: expected mx %.12f my %.12f buttons %d, got mx %.12f my %.12f buttons %d; %s; %s"
					% [
						i, W.frame, k, exp_mx, exp_my, exp_buttons, r.mx, r.my, r.buttons,
						_describe(W.fighters[0]), _describe(W.fighters[1]),
					]
				)
				break
		if divergence != "":
			break
		M.step(got)
		W.drain_events()
		steps = i + 1
	for b: AIBrain in ai:
		b.dispose()
	W.dispose()
	return {"divergence": divergence, "steps": steps}


static func _describe(f: Fighter) -> String:
	var atk: String = "-"
	if f.atk != null:
		atk = "%s frame %d%s" % [f.atk.def.id, f.atk.frame, " charging" if f.atk.charging else ""]
	return "f%d %s sf %d atk %s hp %s posture %s armed %s pos (%.6f, %.6f, %.6f) yaw %.6f" % [
		f.id, f.state, f.sf, atk, f.hp, f.posture, f.armed, f.pos.x, f.pos.y, f.pos.z, f.yaw,
	]
