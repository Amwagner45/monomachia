extends SceneTree
## The bake command (authored-animation task 6): bakes each move the
## move-clip table (MoveClips) fits to a clip into its weapon's swing file,
## game/sim/moves/swings/<weapon>.json, from HumanM on the Hunter (SwingBake,
## ClipPoser), and prints a report of each move's speed and frames against
## today's. Needs the clip libraries (`node scripts/godot.mjs clips`).
##
##   node scripts/godot.mjs bake [--weapon=<id>] [--check]
##
## - --weapon: only that weapon (default: every weapon with a move fitted);
## - --check: write nothing; exit 1 if a file would change.
##
## A move whose baked frames differ from its frame data is marked in the
## report: its frame data is retuned by hand in game/sim/moves/<weapon>.gd,
## in the same commit as its swing (the file is refused until then). Moves
## of the file the table doesn't fit (baked before) are kept; the guard is
## read afresh from the weapon's idle clip. Exits 2 without the libraries.

const SET: StringName = &"HumanM"
const EXIT_NO_LIBRARIES: int = 2


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var only: StringName = &""
	for a: String in args:
		if a.begins_with("--weapon="):
			only = StringName(a.substr(9))
	quit(run(only, args.has("--check")))


## Bakes the table's weapons (or only `only`) and writes their files, or
## with `check` compares them. Returns the exit code.
func run(only: StringName, check: bool) -> int:
	if not ClipLibraries.available():
		printerr("bake_swings: no clip libraries; run `node scripts/godot.mjs clips` (needs the packs, see .assets-src-path)")
		return EXIT_NO_LIBRARIES
	var manifest: ClipManifest = ClipManifest.read()
	var table: MoveClips = MoveClips.read(manifest)
	if not manifest.errors.is_empty() or not table.errors.is_empty():
		printerr("bake_swings: mistakes in the tables:\n  " + "\n  ".join(manifest.errors + table.errors))
		return 1
	if only != &"" and not table.moves.has(only):
		printerr("bake_swings: %s is not in the move-clip table" % only)
		return 1
	var code: int = 0
	for wid: StringName in table.moves:
		if (only != &"" and wid != only) or table.of(wid).is_empty():
			continue
		var path: String = SwingFile.path_for(wid)
		var old: String = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
		var out: Dictionary = bake_weapon(wid, table, manifest, root, old)
		print("%s:\n  %s" % [wid, "\n  ".join(out["report"])])
		if not (out["errors"] as Array).is_empty():
			printerr("bake_swings: %s:\n  %s" % [wid, "\n  ".join(out["errors"])])
			code = 1
			continue
		if check:
			if out["text"] != old:
				printerr("bake_swings: %s differs from a fresh bake" % path)
				code = 1
			continue
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SwingFile.DIR))
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		f.store_string(out["text"])
		f.close()
		print("  wrote %s" % path)
	return code


## Bakes weapon `wid`'s moves the table fits, on a Hunter put under
## `parent` (and freed after), over the swing file text `old` (empty for
## none): {"text": the new file, "report": a line per move, "errors": []}.
static func bake_weapon(wid: StringName, table: MoveClips, manifest: ClipManifest, parent: Node, old: String) -> Dictionary:
	var weapon: WeaponDef = Moves.WEAPONS[wid]
	var errors: Array[String] = []
	var report: PackedStringArray = []
	var model: FighterModel = FighterLook.instantiate_fighter(&"hunter")
	model.autoplay_idle = false
	parent.add_child(model)
	if WeaponLook.IDS.has(wid):
		model.attach_weapon(WeaponLook.load_id(wid))
	model.animation_player.add_animation_library(SET, ClipLibraries.load_set(SET))
	var kept: Dictionary = {}
	if old != "":
		var data: Variant = JSON.parse_string(old)
		if data is Dictionary and (data as Dictionary).get("swings") is Dictionary:
			kept = data["swings"]
	var baked: Dictionary = {}
	var entries: Dictionary = table.of(wid)
	for id: StringName in entries:
		var e: MoveClips.Entry = entries[id]
		var move: AttackDef = weapon.moves[id]
		var chain: Array[String] = []
		var lengths: PackedFloat64Array = PackedFloat64Array()
		for clip: StringName in e.clips:
			chain.append("%s/%s" % [SET, clip])
			lengths.append(model.animation_player.get_animation(chain[-1]).length * ClipManifest.SOURCE_FPS)
		var poser: ClipPoser = ClipPoser.new(model, chain)
		var markers: Dictionary = MoveClips.markers(e, manifest, lengths)
		var speed: float = e.speed if not is_nan(e.speed) else SwingBake.pick_speed(markers, move.startup)
		var why: Array[String] = []
		var r: SwingBake.Result = SwingBake.bake(poser.pose, poser.length, markers, speed, SwingBake.parts_for(move, weapon), why)
		if r == null:
			errors.append("%s: %s" % [id, "; ".join(why)])
			continue
		baked[String(id)] = r.record()
		var line: String = SwingBake.report_line(id, " + ".join(e.clips), r.timing, move)
		if r.timing.total() != move.total_frames() or r.timing.startup != move.startup or r.timing.active != move.active:
			line += "  <- retune in sim/moves/%s.gd" % wid
		report.append(line)
	# the moves in their weapon's order, those not baked now kept as they were
	var swings: Dictionary = {}
	var used: Dictionary[StringName, bool] = {}
	for id: StringName in weapon.moves:
		var record: Variant = baked.get(String(id), kept.get(String(id)))
		if record == null:
			continue
		swings[String(id)] = record
		for part: Variant in (record as Dictionary)["tracks"]:
			used[StringName(str(part))] = true
	var guard_poses: Dictionary = ClipPoser.new(model, ["%s/%s" % [SET, table.guards[wid]]] as Array[String]).pose(0.0)
	var guard: Dictionary = {}
	for part: StringName in guard_poses:
		if used.has(part):
			guard[part] = guard_poses[part]
	parent.remove_child(model)
	model.free()
	var text: String = SwingBake.file_text(SwingBake.guard_record(guard), swings) if not swings.is_empty() else old
	return {"text": text, "report": report, "errors": errors}
