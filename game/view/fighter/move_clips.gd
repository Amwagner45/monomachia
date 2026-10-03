class_name MoveClips
extends RefCounted
## The move-clip table (game/assets/kevin_iglesias/move_clips.json): for each
## weapon, the clip its swings' guard is read from (its idle) and, for each
## move fitted to a clip, the clip (or the chain of clips, played one after
## another) and the speed it plays at. The bake (tools/bake_swings.gd) bakes
## each move's swing from it; without a speed the bake picks the one whose
## startup lands closest to the move's (SwingBake.pick_speed()). Clip ids
## are the clip manifest's (ClipManifest). It holds no animation data, so it
## is committed.
##
##   {"katana": {"guard": "CombatIdle1H01",
##               "moves": {"k_l1": {"clips": ["Attack1H01_R"], "speed": 1.4,
##                                  "fallback": "Sword_Light_A"}}}}
##
## An "about" field may say what the file is.
##
## A chain's markers are its first clip's wind-up start and its last clip's
## contact, contact end and settle, counted from the chain's start (markers()).
## A move may give its own instead ("marks": all four, in source frames from
## the chain's start), where one clip serves moves of different timings: a
## light started from a heavy clip's wound-up pose, say (task 10).

const PATH: String = "res://assets/kevin_iglesias/move_clips.json"
const WEAPON_FIELDS: Array[String] = ["guard", "moves"]
const MOVE_FIELDS: Array[String] = ["clips", "speed", "fallback", "marks"]


## One move fitted to its clips.
class Entry:
	var move: StringName = &""
	## Played one after another.
	var clips: Array[StringName] = []
	## Times the clips' 30 fps; NAN to have the bake pick it.
	var speed: float = NAN
	## The committed CC0 clip (in FighterModel.LIBRARY) played without the
	## Iglesias packs, the clip table's fallback; empty for none.
	var fallback: StringName = &""
	## The move's own markers (ClipManifest.MARKERS, source frames from the
	## chain's start) in place of the manifest's; empty for the manifest's.
	var marks: Dictionary = {}


## Weapon id -> the clip its guard is read from.
var guards: Dictionary[StringName, StringName] = {}
## Weapon id -> move id -> its entry, in the file's order.
var moves: Dictionary[StringName, Dictionary] = {}
## What is wrong with the file, one line each; empty when it read cleanly.
var errors: PackedStringArray = []


## Reads the table, checking its weapons and moves against the rules'
## (Moves.WEAPONS) and its clips against `manifest`.
static func read(manifest: ClipManifest, path: String = PATH) -> MoveClips:
	var t: MoveClips = MoveClips.new()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		t.errors.append("%s is not a JSON object" % path)
		return t
	for wkey: Variant in data:
		if str(wkey) == "about":
			continue
		var wid := StringName(str(wkey))
		if not Moves.WEAPONS.has(wid):
			t.errors.append("%s: not a weapon" % wid)
			continue
		var w: Variant = data[wkey]
		if not w is Dictionary:
			t.errors.append("%s: not an object" % wid)
			continue
		for field: Variant in w:
			if not WEAPON_FIELDS.has(str(field)):
				t.errors.append("%s: unknown field %s" % [wid, field])
		var guard := StringName(str(w.get("guard", "")))
		if not manifest.clips.has(guard):
			t.errors.append("%s: the guard clip %s is not in the clip manifest" % [wid, guard])
		t.guards[wid] = guard
		var entries: Dictionary[StringName, Entry] = {}
		var listed: Variant = w.get("moves", {})
		if not listed is Dictionary:
			t.errors.append("%s: moves must be an object" % wid)
			listed = {}
		for mkey: Variant in listed:
			var e: Entry = t._entry(wid, StringName(str(mkey)), listed[mkey], manifest)
			if e != null:
				entries[e.move] = e
		t.moves[wid] = entries
	return t


## The entries of a weapon's moves (Dictionary[StringName, Entry]), by move.
func of(weapon_id: StringName) -> Dictionary:
	return moves.get(weapon_id, {})


## A move's markers in source frames from its chain's start: the first
## clip's wind-up start and the last clip's other markers, after the clips
## before it (`lengths`: each clip's length in source frames).
static func markers(e: Entry, manifest: ClipManifest, lengths: PackedFloat64Array) -> Dictionary:
	if not e.marks.is_empty():
		return e.marks.duplicate()
	var first: ClipManifest.Clip = manifest.clips[e.clips[0]]
	var last: ClipManifest.Clip = manifest.clips[e.clips[-1]]
	var before: float = 0.0
	for i: int in e.clips.size() - 1:
		before += lengths[i]
	var out: Dictionary = {}
	for name: String in ClipManifest.MARKERS:
		out[name] = float(first.markers[name]) if name == "windup" else before + float(last.markers[name])
	return out


func _entry(wid: StringName, id: StringName, d: Variant, manifest: ClipManifest) -> Entry:
	var at: String = "%s.%s" % [wid, id]
	if not (Moves.WEAPONS[wid] as WeaponDef).moves.has(id):
		errors.append("%s: not a move of the %s" % [at, wid])
		return null
	if not d is Dictionary:
		errors.append("%s: not an object" % at)
		return null
	for field: Variant in d:
		if not MOVE_FIELDS.has(str(field)):
			errors.append("%s: unknown field %s" % [at, field])
	var e: Entry = Entry.new()
	e.move = id
	var clips: Variant = (d as Dictionary).get("clips")
	if not clips is Array or (clips as Array).is_empty():
		errors.append("%s: needs clips, a list of clip ids" % at)
		return null
	for c: Variant in clips:
		if not manifest.clips.has(StringName(str(c))):
			errors.append("%s: %s is not in the clip manifest" % [at, c])
			return null
		e.clips.append(StringName(str(c)))
	if (d as Dictionary).has("speed"):
		var s: Variant = d["speed"]
		if not (s is float or s is int) or float(s) < ClipTiming.MIN_SPEED or float(s) > ClipTiming.MAX_SPEED:
			errors.append("%s: speed must be a number from %.1f to %.1f" % [at, ClipTiming.MIN_SPEED, ClipTiming.MAX_SPEED])
			return null
		e.speed = float(s)
	if (d as Dictionary).has("fallback"):
		var fb := StringName(str(d["fallback"]))
		if not FighterModel.ANIMATION_LIBRARY.has_animation(fb):
			errors.append("%s: the fallback %s is not in the CC0 library" % [at, fb])
			return null
		e.fallback = fb
	if (d as Dictionary).has("marks"):
		var m: Variant = d["marks"]
		var ok: bool = m is Dictionary and (m as Dictionary).size() == ClipManifest.MARKERS.size()
		if ok:
			for name: String in ClipManifest.MARKERS:
				var v: Variant = (m as Dictionary).get(name)
				ok = ok and (v is float or v is int) and float(v) >= 0.0
		if not ok:
			errors.append("%s: marks must give %s, each a frame number" % [at, ", ".join(ClipManifest.MARKERS)])
			return null
		for name: String in ClipManifest.MARKERS:
			e.marks[name] = float(m[name])
	return e
