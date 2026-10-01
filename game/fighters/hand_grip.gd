class_name HandGrip
extends SkeletonModifier3D
## Closes a fighter's hands into fists around a weapon's handle, whatever the
## playing clip does with the fingers. FighterModel adds one to its skeleton
## and turns a hand on when it holds a weapon.
##
## After retargeting, each finger bone's +Y runs along the finger and +Z
## comes out of the palm, so turning a bone about its own +X curls it in.
## The fist is set from the rest pose, so it doesn't depend on the clip.

const FINGERS: Array[String] = ["Index", "Middle", "Ring", "Little"]
## Curl of each finger segment, in degrees.
const CURL: Dictionary[String, float] = {"Proximal": 72.0, "Intermediate": 85.0, "Distal": 45.0}
## The little finger closes tighter than the index, as on a real grip.
const SPREAD: Dictionary[String, float] = {"Index": 0.9, "Middle": 1.0, "Ring": 1.05, "Little": 1.1}
## The thumb wraps over the fingers.
const THUMB_CURL: Dictionary[String, float] = {"Proximal": 25.0, "Distal": 35.0}

@export var right_hand: bool = false
@export var left_hand: bool = false

var _ids: Dictionary[String, int] = {}


func _process_modification_with_delta(_delta: float) -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null:
		return
	if right_hand:
		_close(sk, "Right")
	if left_hand:
		_close(sk, "Left")


func _close(sk: Skeleton3D, side: String) -> void:
	for finger: String in FINGERS:
		for segment: String in CURL:
			_curl(sk, side + finger + segment, CURL[segment] * SPREAD[finger])
	for segment: String in THUMB_CURL:
		_curl(sk, side + "Thumb" + segment, THUMB_CURL[segment])


func _curl(sk: Skeleton3D, bone_name: String, degrees: float) -> void:
	if not _ids.has(bone_name):
		_ids[bone_name] = sk.find_bone(bone_name)
	var bone: int = _ids[bone_name]
	if bone < 0:
		return
	var rest: Quaternion = sk.get_bone_rest(bone).basis.get_rotation_quaternion()
	sk.set_bone_pose_rotation(bone, rest * Quaternion(Vector3.RIGHT, deg_to_rad(degrees)))
