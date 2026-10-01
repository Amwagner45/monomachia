class_name HandGrip
extends SkeletonModifier3D
## Closes a fighter's hands into fists around a weapon's handle, whatever the
## playing clip does with the fingers, and sets the wrists the weapon's hold
## asks for (see WeaponHold). FighterModel adds one to its skeleton and turns
## a hand on when it holds a weapon.
##
## After retargeting, each finger bone's +Y runs along the finger and +Z
## comes out of the palm, so turning a bone about its own +X curls it in.
## The fist and the wrist are set from the rest pose, so they don't depend on
## the clip.

const FINGERS: Array[String] = ["Index", "Middle", "Ring", "Little"]
## Curl of each finger segment, in degrees.
const CURL: Dictionary[String, float] = {"Proximal": 78.0, "Intermediate": 88.0, "Distal": 50.0}
## The little finger closes tighter than the index, as on a real grip.
const SPREAD: Dictionary[String, float] = {"Index": 0.92, "Middle": 1.0, "Ring": 1.05, "Little": 1.12}
## The thumb swings across the front of the handle, then wraps over the
## fingers.
const THUMB_SWING: float = 30.0
const THUMB_CURL: Dictionary[String, float] = {"Proximal": 28.0, "Distal": 38.0}

@export var right_hand: bool = false
@export var left_hand: bool = false

## Wrist rotations from straight, by side ("Right", "Left"); a side that
## isn't here keeps the clip's wrist.
var wrists: Dictionary[String, Quaternion] = {}

var _ids: Dictionary[String, int] = {}


## Sets a wrist (side "Right" or "Left") to `degrees` from straight (see
## WeaponHold.right_wrist).
func set_wrist(side: String, degrees: Vector3) -> void:
	wrists[side] = Quaternion.from_euler(degrees * (PI / 180.0))


func clear_wrists() -> void:
	wrists.clear()


func _process_modification_with_delta(_delta: float) -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null:
		return
	for side: String in wrists:
		_set_from_rest(sk, side + "Hand", wrists[side])
	if right_hand:
		_close(sk, "Right")
	if left_hand:
		_close(sk, "Left")


func _close(sk: Skeleton3D, side: String) -> void:
	for finger: String in FINGERS:
		for segment: String in CURL:
			_curl(sk, side + finger + segment, CURL[segment] * SPREAD[finger])
	# The metacarpal swings about the hand's length (the hand bone's Y, in
	# the metacarpal's parent space) toward the palm. The hand's X points to
	# the thumb on the right hand and away from it on the left, so the turn is
	# mirrored.
	var swing: float = deg_to_rad(THUMB_SWING) * (-1.0 if side == "Right" else 1.0)
	_set_from_rest(sk, side + "ThumbMetacarpal", Quaternion(Vector3.UP, swing), true)
	for segment: String in THUMB_CURL:
		_curl(sk, side + "Thumb" + segment, THUMB_CURL[segment])


func _curl(sk: Skeleton3D, bone_name: String, degrees: float) -> void:
	_set_from_rest(sk, bone_name, Quaternion(Vector3.RIGHT, deg_to_rad(degrees)))


## Sets a bone to its rest rotation turned by `turn`, in the bone's own
## space or, with `in_parent`, in its parent's.
func _set_from_rest(sk: Skeleton3D, bone_name: String, turn: Quaternion, in_parent: bool = false) -> void:
	if not _ids.has(bone_name):
		_ids[bone_name] = sk.find_bone(bone_name)
	var bone: int = _ids[bone_name]
	if bone < 0:
		return
	var rest: Quaternion = sk.get_bone_rest(bone).basis.get_rotation_quaternion()
	sk.set_bone_pose_rotation(bone, turn * rest if in_parent else rest * turn)
