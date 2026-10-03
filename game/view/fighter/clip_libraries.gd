class_name ClipLibraries
extends RefCounted
## The Iglesias clip libraries: one AnimationLibrary per clip set (HumanM,
## HumanF), written by the import tool (tools/import_clips.gd) from the packs
## on the developer's PC into a gitignored folder, so the exported game packs
## them but the public repo never holds them (docs/specs/authored-animation.md,
## Licence). A fresh clone has no libraries: available() is false and the
## game plays the committed CC0 fallback clips instead.
##
## Tracks address bones as `%GeneralSkeleton:<profile bone>`, like the UAL
## library, so a clip plays on any FighterModel. Clips keep their manifest
## names (game/assets/kevin_iglesias/clip_manifest.json).

const FOLDER: String = "res://assets/kevin_iglesias/library"
## The clip sets, in the order the import tool writes them.
const SETS: Array[StringName] = [&"HumanM", &"HumanF"]


## Where a set's library is saved.
static func path(set_name: StringName) -> String:
	return FOLDER.path_join("iglesias_%s.res" % String(set_name).to_lower())


## True when every set's library is there.
static func available() -> bool:
	for set_name: StringName in SETS:
		if not ResourceLoader.exists(path(set_name)):
			return false
	return true


## A set's library, or null when it hasn't been imported.
static func load_set(set_name: StringName) -> AnimationLibrary:
	var p: String = path(set_name)
	if not ResourceLoader.exists(p):
		return null
	return load(p) as AnimationLibrary
