extends SceneTree
## Port of scripts/soak.ts.
##
## Headless robot matches: computer vs computer at full speed.
## Verifies matches finish without errors and reports how often each mechanic occurs.
##
## usage: node scripts/godot.mjs soak [matches]     (or: npm run soak:godot -- 40)
##
## Port notes:
## - The match count is the first user argument (after --); the default is 30.
## - It uses the same seeds as the TS soak, so the printed report is
##   identical: compare it with `npx tsx scripts/soak.ts <matches>`. Numbers
##   are printed with JsFormat (JS toFixed and console.log of an object).
## - GDScript has no exceptions: a failed sanity check (the TS throw) ends the
##   match and is reported as a crash, as the TS catch does.
## - The exit code is 1 on any failure. If a script error aborts the run,
##   _process() still quits, with exit code 1.

## Stays 1 unless _soak() runs to its end.
var _exit_code: int = 1


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var n: int = int(args[0]) if args.size() > 0 else 30
	_soak(n)


func _process(_delta: float) -> bool:
	quit(_exit_code)
	return true


func _soak(N: int) -> void:
	var rng: Rng = Rng.new(2026)
	var diffs: Array[StringName] = [&"easy", &"normal", &"hard"]
	var totals: Dictionary[String, int] = {}
	var total_rounds: int = 0
	var total_round_frames: int = 0
	var longest: int = 0
	## weapon id -> [wins, losses], in insertion order
	var wins_by_weapon: Dictionary[String, Array] = {}
	var failures: int = 0

	for m: int in N:
		var w0: StringName = rng.pick(Moves.PLAYABLE_WEAPONS)
		var w1: StringName = rng.pick(Moves.PLAYABLE_WEAPONS)
		var d0: StringName = rng.pick(diffs)
		var d1: StringName = rng.pick(diffs)
		var W: World = World.new(FighterConfig.make(Moves.WEAPONS[w0]), FighterConfig.make(Moves.WEAPONS[w1]), 1000 + m)
		var M: Match = Match.new(W)
		var ai: Array[AIBrain] = [
			AIBrain.new(W.fighters[0], AIBrain.DIFFICULTY[d0], 11 + m),
			AIBrain.new(W.fighters[1], AIBrain.DIFFICULTY[d1], 77 + m),
		]
		var frames: int = 0
		var round_start: int = 0
		const LIMIT: int = 60 * 60 * 12 # 12 minutes of game time
		var error: String = "" # the TS throw
		while M.phase != &"matchEnd" and frames < LIMIT:
			M.step([ai[0].think(), ai[1].think()])
			frames += 1
			for e: Dictionary in W.drain_events():
				match e["t"]:
					&"fight":
						round_start = frames
					&"roundOver":
						var length: int = frames - round_start # len
						total_rounds += 1
						total_round_frames += length
						longest = maxi(longest, length)
					&"parry":
						_add(totals, "parry:" + String(e["kind"]))
					&"counter":
						_add(totals, "counter:" + String(e["kind"]))
					&"hit":
						_add(totals, "hits")
					&"block":
						_add(totals, "blocks")
					&"disarm":
						_add(totals, "disarm:" + String(e["reason"]))
					&"ultStart":
						_add(totals, "ult:" + String(e["ult"]))
					&"ultChoice":
						_add(totals, "ult:disarmedChoice")
					&"recall":
						_add(totals, "recall")
					&"pickup":
						_add(totals, "rearm")
					&"stagger":
						_add(totals, "stagger")
					&"evade":
						_add(totals, "evade")
					&"ko":
						if int(e["winner"]) < 0:
							_add(totals, "doubleKO")
			# sanity checks
			for f: Fighter in W.fighters:
				if M.phase == &"fight" and f.posture_full():
					_add(totals, "framesAtFullPosture")
				if not is_finite(f.pos.x) or not is_finite(f.pos.z) or not is_finite(f.hp):
					error = "NaN state"
					break
				if sqrt(f.pos.x * f.pos.x + f.pos.z * f.pos.z) > 12.0:
					error = "left the arena"
					break
				if f.posture < -1e-6 or f.posture > 100.0001:
					error = "posture out of range " + JsFormat.num(f.posture)
					break
			if error != "":
				break
		if error != "":
			failures += 1
			print("match %d crashed at frame %d: Error: %s" % [m, frames, error])
		elif M.phase != &"matchEnd":
			failures += 1
			print("match %d (%s/%s vs %s/%s) did not finish: wins %d,%d" % [m, w0, d0, w1, d1, M.wins[0], M.wins[1]])
		else:
			if not wins_by_weapon.has(String(w0)):
				wins_by_weapon[String(w0)] = [0, 0]
			if not wins_by_weapon.has(String(w1)):
				wins_by_weapon[String(w1)] = [0, 0]
			wins_by_weapon[String(w0 if M.match_winner == 0 else w1)][0] += 1
			wins_by_weapon[String(w1 if M.match_winner == 0 else w0)][1] += 1
		for brain: AIBrain in ai:
			brain.dispose()
		W.dispose()

	var rounds: int = maxi(1, total_rounds)
	print("\n%d matches, %d failures" % [N, failures])
	print("rounds: %d, avg round %s s, longest %s s" % [
		total_rounds,
		JsFormat.to_fixed(float(total_round_frames) / float(rounds) / 60.0, 1),
		JsFormat.to_fixed(float(longest) / 60.0, 1),
	])
	print("per round:")
	# Object.entries(totals).sort(): the default sort compares "key,value" strings.
	var keys: Array[String] = []
	keys.assign(totals.keys())
	keys.sort_custom(func(a: String, b: String) -> bool: return "%s,%d" % [a, totals[a]] < "%s,%d" % [b, totals[b]])
	for k: String in keys:
		print("  %s %s" % [k.rpad(22), JsFormat.to_fixed(float(totals[k]) / float(rounds), 2)])
	print("match wins/losses by weapon: " + JsFormat.inspect(wins_by_weapon))
	_exit_code = 1 if failures > 0 else 0


static func _add(totals: Dictionary[String, int], k: String, v: int = 1) -> void:
	totals[k] = totals.get(k, 0) + v
