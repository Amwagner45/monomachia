class_name SwingBake
extends RefCounted
## The bake (authored-animation task 6): a clip, or a chain of clips played
## one after another, into a move's frame data and its baked swing. It is a
## pure function of what it is given: a sampled clip (a Callable giving the
## parts' poses at a clip time, in the fighter's own frame, and the clip's
## length; ClipPoser poses the Hunter for it), the clip's markers in source
## frames (ClipManifest.MARKERS) and a speed between 1.0 and 2.0 times the
## clip's 30 fps. It gives back:
## - the clip retimed onto rules frames (ClipTiming: the markers on the
##   move's frames);
## - each part's pose (grip, blade and edge of a striking hand or foot, the
##   coil and pelvis shift of the body) at every rules frame, from 0 to the
##   move's last: a baked swing (SwingFile reads it as baked tracks);
## - the move's startup, active and recovery frames.
##
## file_text() writes a weapon's swing file with a stable key order and
## fixed decimals, so the same bake writes the same bytes. The bake command
## (tools/bake_swings.gd) runs it for the moves the move-clip table names.

## The speeds pick_speed() tries: ClipTiming.MIN_SPEED to MAX_SPEED in these
## steps.
const SPEED_STEP: float = 0.05
## Decimal places written for metres and directions, and for degrees.
const PLACES: int = 4
const DEGREE_PLACES: int = 2
## The order a key's (or a guard pose's) fields are written in.
const FIELD_ORDER: Array[String] = ["frame", "grip", "blade", "edge", "pole", "torso", "pelvis", "pelvis_shift", "ease"]


## What a bake gives back.
class Result:
	var timing: ClipTiming
	## The clip's time (s) at each rules frame, 0 to timing.total().
	var times: PackedFloat64Array = PackedFloat64Array()
	## Each part's pose at each rules frame (Array[Swing.Sample]), by part,
	## in Swing.PARTS' order.
	var tracks: Dictionary[StringName, Array] = {}

	## The swing as a swing file holds it: {"tracks": {part: {"baked": true,
	## "keys": [...]}}}, rounded to the decimals written.
	func record() -> Dictionary:
		var out: Dictionary = {}
		for part: StringName in tracks:
			var keys: Array = []
			var samples: Array = tracks[part]
			for f: int in samples.size():
				var key: Dictionary = {"frame": f}
				key.merge(SwingBake.pose_record(part, samples[f]))
				keys.append(key)
			out[String(part)] = {"baked": true, "keys": keys}
		return {"tracks": out}


## The clip retimed at `speed` by `markers` (ClipTiming.make()): null, with
## an error per mistake.
static func timing(markers: Dictionary, speed: float, errors: Array[String]) -> ClipTiming:
	return ClipTiming.make(markers, speed, errors)


## The speed (ClipTiming.MIN_SPEED to MAX_SPEED in SPEED_STEP steps) whose
## startup lands closest to `startup`, the slowest of those that tie. Bad
## markers give MIN_SPEED.
static func pick_speed(markers: Dictionary, startup: int) -> float:
	var best: float = ClipTiming.MIN_SPEED
	var best_gap: int = 1 << 30
	var steps: int = roundi((ClipTiming.MAX_SPEED - ClipTiming.MIN_SPEED) / SPEED_STEP)
	for i: int in steps + 1:
		var speed: float = snappedf(ClipTiming.MIN_SPEED + SPEED_STEP * i, 0.001)
		var t: ClipTiming = timing(markers, speed, [] as Array[String])
		if t == null:
			return ClipTiming.MIN_SPEED
		var gap: int = absi(t.startup - startup)
		if gap < best_gap:
			best = speed
			best_gap = gap
	return best


## Bakes the sampled clip: `pose` takes a clip time (s) and gives the parts'
## poses then, a Dictionary[StringName, Swing.Sample] holding each of
## `parts`; `length` is the clip's (s). Null, with errors, for a bad marker
## or speed (timing()), a settle past the clip's end, or a part the poses
## lack.
static func bake(pose: Callable, length: float, markers: Dictionary, speed: float, parts: Array[StringName],
		errors: Array[String]) -> Result:
	var t: ClipTiming = timing(markers, speed, errors)
	if t == null:
		return null
	var end: float = length * float(ClipManifest.SOURCE_FPS)
	if t.marks[3] > end + 1e-6:
		errors.append("the settle marker (%s) is past the clip's end (frame %s)" % [ClipTiming.frame_text(t.marks[3]), ClipTiming.frame_text(snappedf(end, 0.01))])
		return null
	var out: Result = Result.new()
	out.timing = t
	var ordered: Array[StringName] = []
	for part: StringName in Swing.PARTS:
		if parts.has(part):
			ordered.append(part)
			out.tracks[part] = []
	for f: int in t.total() + 1:
		var time: float = t.clip_time(float(f))
		out.times.append(time)
		var poses: Dictionary = pose.call(time)
		for part: StringName in ordered:
			if not poses.has(part):
				errors.append("the sampled clip has no %s" % part)
				return null
			out.tracks[part].append(poses[part])
	return out


## The parts a move's swing bakes, beside the body: both hands for a pair
## of weapons (the Daggers); the striking hand, or foot for a kick, for bare
## hands (both hands for a move with both); the main hand otherwise.
static func parts_for(move: AttackDef, weapon: WeaponDef) -> Array[StringName]:
	var out: Array[StringName] = []
	if weapon.id == &"daggers":
		out.assign([&"right_hand", &"left_hand"])
	elif weapon.id == &"fists":
		var limb: String = "foot" if move.type == &"kick" else "hand"
		if move.hand == &"L" or move.hand == &"both":
			out.append(StringName("left_" + limb))
		if move.hand != &"L":
			out.append(StringName("right_" + limb))
		out.sort_custom(func(a: StringName, b: StringName) -> bool: return Swing.PARTS.find(a) < Swing.PARTS.find(b))
	else:
		out.append(&"right_hand")
	out.append(&"body")
	return out


## A pose's fields as a swing file holds them, rounded: a hand or foot's
## grip, blade and edge (and pole, if any), or the body's coils and pelvis
## shift.
static func pose_record(part: StringName, s: Swing.Sample) -> Dictionary:
	if part == &"body":
		var body: Dictionary = {"torso": snappedf(s.torso, pow(10.0, -DEGREE_PLACES)), "pelvis": snappedf(s.pelvis, pow(10.0, -DEGREE_PLACES))}
		if V3.length(s.pelvis_shift) > 0.0:
			body["pelvis_shift"] = _round(s.pelvis_shift)
		return body
	var limb: Dictionary = {"grip": _round(s.grip), "blade": _round(s.blade), "edge": _round(s.edge)}
	if V3.length(s.pole) > 0.0:
		limb["pole"] = _round(s.pole)
	return limb


## The guard of a swing file from one pose of each part (a weapon's idle
## clip's first frame), as the file holds it.
static func guard_record(poses: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for part: StringName in Swing.PARTS:
		if poses.has(part):
			out[String(part)] = pose_record(part, poses[part])
	return out


## A swing file's text: {"guard": {...}, "swings": {move: {"tracks": ...}}}
## with each guard pose and each key on a line of its own, the fields in
## FIELD_ORDER, metres and directions to PLACES decimals and degrees to
## DEGREE_PLACES. Hand-keyed tracks (lists of keys) are written as well as
## baked ones, so a file can be rewritten whole.
static func file_text(guard: Dictionary, swings: Dictionary) -> String:
	var lines: PackedStringArray = ["{", "\t\"guard\": {"]
	var parts: Array = guard.keys()
	for i: int in parts.size():
		lines.append("\t\t\"%s\": %s%s" % [parts[i], _line(guard[parts[i]]), "," if i < parts.size() - 1 else ""])
	lines.append("\t},")
	lines.append("\t\"swings\": {")
	var ids: Array = swings.keys()
	for i: int in ids.size():
		lines.append("\t\t\"%s\": {" % ids[i])
		lines.append("\t\t\t\"tracks\": {")
		var tracks: Dictionary = swings[ids[i]]["tracks"]
		var names: Array = tracks.keys()
		for j: int in names.size():
			var track: Variant = tracks[names[j]]
			var keys: Array = track["keys"] if track is Dictionary else track
			if track is Dictionary:
				lines.append("\t\t\t\t\"%s\": {\"baked\": %s, \"keys\": [" % [names[j], "true" if track["baked"] else "false"])
			else:
				lines.append("\t\t\t\t\"%s\": [" % names[j])
			for k: int in keys.size():
				lines.append("\t\t\t\t\t%s%s" % [_line(keys[k]), "," if k < keys.size() - 1 else ""])
			var comma: String = "," if j < names.size() - 1 else ""
			lines.append("\t\t\t\t]}%s" % comma if track is Dictionary else "\t\t\t\t]%s" % comma)
		lines.append("\t\t\t}")
		lines.append("\t\t}%s" % ("," if i < ids.size() - 1 else ""))
	lines.append("\t}")
	lines.append("}")
	return "\n".join(lines) + "\n"


## One line of a report: a move's speed and frames against today's.
static func report_line(id: StringName, clips: String, t: ClipTiming, move: AttackDef) -> String:
	return "%s (%s ×%.2f): startup %d (today %d), active %d (%d), recovery %d (%d), total %d (%d)" % [
		id, clips, t.speed, t.startup, move.startup, t.active, move.active, t.recovery, move.recovery,
		t.total(), move.total_frames()]


static func _round(v: V3) -> Array:
	var unit: float = pow(10.0, -PLACES)
	return [snappedf(v.x, unit), snappedf(v.y, unit), snappedf(v.z, unit)]


static func _line(d: Dictionary) -> String:
	var fields: PackedStringArray = []
	var names: Array = FIELD_ORDER.filter(func(f: String) -> bool: return d.has(f))
	for extra: Variant in d:
		if not names.has(str(extra)):
			names.append(str(extra))
	for name: String in names:
		fields.append("\"%s\": %s" % [name, _value(name, d[name])])
	return "{%s}" % ", ".join(fields)


static func _value(field: String, v: Variant) -> String:
	if v is Array:
		return "[%s]" % ", ".join((v as Array).map(func(x: Variant) -> String: return _value(field, x)))
	if typeof(v) == TYPE_BOOL:
		return "true" if v else "false"
	if field == "frame":
		return str(int(v))
	return _num(float(v), DEGREE_PLACES if field == "torso" or field == "pelvis" else PLACES)


static func _num(x: float, places: int) -> String:
	var v: float = snappedf(x, pow(10.0, -places))
	if v == 0.0:
		return "0"
	return String.num(v, places)
