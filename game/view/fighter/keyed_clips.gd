class_name KeyedClips
extends RefCounted
## The hand-keyed clips: our own CC0 work, committed, so they play with or
## without the Iglesias packs. Each is keyed from a key-pose file in
## KEYS_FOLDER (KeyedPose) by tools/build_keyed_clips.gd, which writes them
## all into one AnimationLibrary at PATH. Tracks address bones as
## `%GeneralSkeleton:<profile bone>`, like the other libraries, so a clip
## plays on either fighter.
##
## - Mikiri_Stomp: the stomp counter (dodging into a thrust), after Sekiro's
##   mikiri counter: the hop onto the spear, the foot pinning it, the press
##   held as the attacker's posture breaks, and the rise to a ready stance,
##   fitted to the stomp state's 26 frames (Fighter.begin_stomp()).

const LIBRARY: StringName = &"keyed"
const PATH: String = "res://assets/authored/keyed_library.tres"
const KEYS_FOLDER: String = "res://assets/authored/keys"
const STOMP: StringName = &"Mikiri_Stomp"


## The library, or null before the builder has written it.
static func load_library() -> AnimationLibrary:
	if not ResourceLoader.exists(PATH):
		return null
	return load(PATH) as AnimationLibrary


## A clip's name in a tree that has the library.
static func anim_name(clip: StringName) -> String:
	return "%s/%s" % [LIBRARY, clip]
