class_name Swing
extends RefCounted
## A move's swing (task 7): the path its weapon travels through the move, as
## key poses in the fighter's own space. The same path will decide hits and
## drive the animation. Swings are read from the per-weapon files under
## game/sim/moves/swings/ (see SwingFile) into AttackDef.swing.
##
## A swing holds tracks, one per part of the body that it moves (PARTS), and
## each track holds keys sorted by frame. Frames count as AttackState.frame
## does: 0 when the move starts, up to the move's total frames.
## - A hand track moves a weapon (or a fist): each key holds the grip and the
##   weapon's orientation, its blade (weapon +Y) and its edge (weapon +X),
##   plus an optional tweak of the elbow's pole. A foot track moves a foot the
##   same way, its pole being the knee's.
## - The body track holds the torso and pelvis coil and the pelvis shift.
## Positions and directions are (right, up, forward) from the fighter's feet,
## as SimMath.local_to_world takes them. A key's ease scales the speed through
## it: 0 stops there (a cocked hold, a settle), 1 is the even default.

const PARTS: Array[StringName] = [&"right_hand", &"left_hand", &"right_foot", &"left_foot", &"body"]


## One key pose of a track. Hand and foot keys use frame, grip, blade, edge,
## pole and ease; body keys use frame, torso, pelvis, pelvis_shift and ease.
class KeyPose:
	var frame: int = 0
	## the grip, metres (right, up, forward) from the fighter's feet
	var grip: V3 = V3.make()
	## the blade's direction, unit length
	var blade: V3 = V3.make(0.0, 1.0, 0.0)
	## the edge's direction, unit length and square to the blade
	var edge: V3 = V3.make(1.0, 0.0, 0.0)
	## added to the elbow's (or knee's) default pole direction
	var pole: V3 = V3.make()
	## coil about the spine in degrees, positive turning toward the fighter's right
	var torso: float = 0.0
	var pelvis: float = 0.0
	## metres (right, up, forward) the pelvis moves from its rest
	var pelvis_shift: V3 = V3.make()
	## speed through the key: 0 stops there, 1 is even
	var ease: float = 1.0


var _tracks: Dictionary[StringName, Array] = {}


## Adds the track for `part` (one of PARTS), its keys sorted by frame.
func add_track(part: StringName, keys: Array[KeyPose]) -> void:
	_tracks[part] = keys


## The parts this swing has tracks for, in the order they were added.
func parts() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_tracks.keys())
	return out


## The keys of the track for `part`, or none.
func track(part: StringName) -> Array[KeyPose]:
	if not _tracks.has(part):
		return [] as Array[KeyPose]
	return _tracks[part]
