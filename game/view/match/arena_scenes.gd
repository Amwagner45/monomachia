class_name ArenaScenes
extends RefCounted
## The arenas a match can be fought in: arena id -> scene path. The match view
## loads the arena named by MatchConfig.arena_id from here, so a real arena
## drops in by adding (or fixing) one line, without touching the host or the
## view.
##
## An arena scene's root is a Node3D centred on the arena's middle, floor at
## y = 0, wall at SimConst.ARENA_RADIUS. It may hold Marker3D children named
## Spawn0, Spawn1, Gate0 and Gate1 (spawn points and gate anchors); the rules
## still place the fighters themselves (World.reset_round).
##
## An id whose scene doesn't exist yet (the Moonlit Shrine while its lane is
## still building it) falls back to the stand-in.

const STANDIN: StringName = &"standin"
const MOONLIT_SHRINE: StringName = &"moonlit_shrine"

const SCENES: Dictionary[StringName, String] = {
	STANDIN: "res://view/match/standin_arena.tscn",
	MOONLIT_SHRINE: "res://arenas/moonlit_shrine/moonlit_shrine.tscn",
}


static func has(id: StringName) -> bool:
	return SCENES.has(id)


## The scene path for an arena id: its own scene when it exists, else the
## stand-in's.
static func scene_path(id: StringName) -> String:
	var path: String = SCENES.get(id, "")
	if path != "" and ResourceLoader.exists(path):
		return path
	return SCENES[STANDIN]


## A new instance of the arena (the stand-in when the id is unknown or its
## scene is missing).
static func instantiate(id: StringName) -> Node3D:
	var packed: PackedScene = load(scene_path(id))
	return packed.instantiate() as Node3D
