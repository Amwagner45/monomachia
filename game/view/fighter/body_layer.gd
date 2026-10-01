class_name BodyLayer
extends SkeletonModifier3D
## The fighter's procedural body pose, laid over the playing clip before the
## arm and leg IK (see FighterRig): a lean about the ground, the hips turned
## and moved, the spine twisted and bent over its three bones, and the head
## turned. Everything is in skeleton space, the fighter's own frame: +Z
## forward, +X to the fighter's left, +Y up, metres from the ground. With
## every value at zero the clip's pose is left alone.
##
## Each turn is applied as a rotation in skeleton space, parent first, so
## that it means the same whatever the clip does.

## How a spine twist or bend is shared over the spine's bones.
const SPINE_SHARE: Dictionary[StringName, float] = {&"Spine": 0.28, &"Chest": 0.36, &"UpperChest": 0.36}
## How a head turn is shared over the neck and head.
const HEAD_SHARE: Dictionary[StringName, float] = {&"Neck": 0.45, &"Head": 0.55}

## The whole body leaning about the ground under it, as a rotation vector
## (axis times angle in radians): leaning into acceleration.
var lean: Vector3 = Vector3.ZERO
## The hips, and the legs with them, turned about the vertical (radians,
## positive to the fighter's left).
var pelvis_yaw: float = 0.0
## Both legs turned further at the hips.
var thigh_yaw: float = 0.0
## The spine twisted about the vertical, shared over SPINE_SHARE; often
## against pelvis_yaw, to keep the chest square.
var spine_yaw: float = 0.0
## The spine bent forward (positive) or back.
var spine_pitch: float = 0.0
## The spine bent sideways, positive tipping the top to the fighter's right.
var spine_roll: float = 0.0
## The head turned (positive to the left) and nodded (positive down), shared
## over HEAD_SHARE.
var head_yaw: float = 0.0
var head_pitch: float = 0.0
## The hips moved, in skeleton space: a dip, a weight shift.
var hips_offset: Vector3 = Vector3.ZERO

var _ids: Dictionary[StringName, int] = {}


## Turns a bone by `turn`, a rotation in skeleton space, about its own
## origin: its new global rotation is `turn` times its old one, and its
## children turn with it.
static func rot_global(sk: Skeleton3D, bone: int, turn: Quaternion) -> void:
	var parent: int = sk.get_bone_parent(bone)
	var parent_q: Quaternion = Quaternion.IDENTITY
	if parent >= 0:
		parent_q = sk.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	var local: Quaternion = sk.get_bone_pose_rotation(bone)
	sk.set_bone_pose_rotation(bone, (parent_q.inverse() * turn * parent_q * local).normalized())


## Sets every value back to zero.
func clear() -> void:
	lean = Vector3.ZERO
	pelvis_yaw = 0.0
	thigh_yaw = 0.0
	spine_yaw = 0.0
	spine_pitch = 0.0
	spine_roll = 0.0
	head_yaw = 0.0
	head_pitch = 0.0
	hips_offset = Vector3.ZERO


func _process_modification_with_delta(_delta: float) -> void:
	var sk: Skeleton3D = get_skeleton()
	if sk == null:
		return
	if lean.length() > 1e-5:
		rot_global(sk, _id(sk, &"Root"), Quaternion(lean.normalized(), lean.length()))
	if absf(pelvis_yaw) > 1e-5:
		rot_global(sk, _id(sk, &"Hips"), Quaternion(Vector3.UP, pelvis_yaw))
	if absf(thigh_yaw) > 1e-5:
		for thigh: StringName in [&"LeftUpperLeg", &"RightUpperLeg"]:
			rot_global(sk, _id(sk, thigh), Quaternion(Vector3.UP, thigh_yaw))
	if hips_offset != Vector3.ZERO:
		var hips: int = _id(sk, &"Hips")
		var root_q: Quaternion = sk.get_bone_global_pose(_id(sk, &"Root")).basis.get_rotation_quaternion()
		sk.set_bone_pose_position(hips, sk.get_bone_pose_position(hips) + root_q.inverse() * hips_offset)
	for bone_name: StringName in SPINE_SHARE:
		var bone: int = _id(sk, bone_name)
		var share: float = SPINE_SHARE[bone_name]
		if absf(spine_yaw) > 1e-5:
			rot_global(sk, bone, Quaternion(Vector3.UP, spine_yaw * share))
		var b: Basis = sk.get_bone_global_pose(bone).basis.orthonormalized()
		if absf(spine_pitch) > 1e-5:
			rot_global(sk, bone, Quaternion(b.x, spine_pitch * share))
		if absf(spine_roll) > 1e-5:
			rot_global(sk, bone, Quaternion(b.z, spine_roll * share))
	for bone_name: StringName in HEAD_SHARE:
		var bone: int = _id(sk, bone_name)
		var share: float = HEAD_SHARE[bone_name]
		if absf(head_yaw) > 1e-5:
			rot_global(sk, bone, Quaternion(Vector3.UP, head_yaw * share))
		if absf(head_pitch) > 1e-5:
			var b: Basis = sk.get_bone_global_pose(bone).basis.orthonormalized()
			rot_global(sk, bone, Quaternion(b.x, head_pitch * share))


func _id(sk: Skeleton3D, bone_name: StringName) -> int:
	if not _ids.has(bone_name):
		_ids[bone_name] = sk.find_bone(bone_name)
	return _ids[bone_name]
