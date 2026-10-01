class_name FighterModel
extends Node3D
## A fighter's rigged model, assembled from its FighterLook when the scene is
## instantiated (or, for a FighterModel made in code, when it enters the tree
## or `build()` is called). A fighter's scene is just this node with its look.
##
## What it exposes to the presentation code:
## - `skeleton`: the Skeleton3D, retargeted to Godot's humanoid profile
##   (bones Hips, Spine, Chest, ..., RightHand) and owned as the unique node
##   %GeneralSkeleton, which the clips' tracks address;
## - `animation_player`: an AnimationPlayer whose root is this node, holding
##   the shared clip library as "ual" (play "ual/Idle"), ready to drive an
##   AnimationTree;
## - `right_hand` / `left_hand`: weapon sockets on the hand bones (see
##   WeaponLook for their frame), and `attach_weapon()`, which also closes the
##   holding hands through `hand_grip`;
## - `apply_palette()`: switches between the look's two palettes.
##
## Built nodes are not owned by the scene, so they are never saved into it;
## the skeleton alone is owned by this node, so that its unique name resolves.
## The script doesn't run in the editor, where a fighter scene shows empty:
## run fighters/preview/preview.tscn to look at the fighters.

const ANIMATION_LIBRARY: AnimationLibrary = preload("res://assets/quaternius/animations/ual_library.res")
const LIBRARY: StringName = &"ual"
const SKELETON_NAME: StringName = &"GeneralSkeleton"

## Hand sockets in hand-bone space. After retargeting, a hand bone's +Y runs
## from the wrist to the knuckles and +Z comes out of the palm; +X points to
## the thumb on the right hand and away from it on the left. The socket sits
## in the hollow of a closed fist with +Y out of the thumb side and +X out of
## the knuckles.
const RIGHT_SOCKET: Transform3D = Transform3D(
	Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)), Vector3(0.0, 0.075, 0.03))
const LEFT_SOCKET: Transform3D = Transform3D(
	Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1)), Vector3(0.0, 0.075, 0.03))

@export var look: FighterLook:
	set(value):
		look = value
		if _built:
			rebuild()
## Which of the look's palettes to wear (0 or 1).
@export var palette: int = 0:
	set(value):
		palette = value
		if _built:
			apply_palette(value)
## Play the look's idle clip on entering the tree.
@export var autoplay_idle: bool = true

var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var right_hand: Node3D
var left_hand: Node3D
## Closes the hands that hold a weapon (see attach_weapon()).
var hand_grip: HandGrip
## The weapon models attached by attach_weapon().
var weapons: Array[Node3D] = []

var _built: bool = false
## [MeshInstance3D, surface index, imported material] for each outfit surface.
var _outfit_surfaces: Array[Array] = []
## The same for the hair and eyebrows.
var _hair_surfaces: Array[Array] = []
var _materials: Dictionary[String, Material] = {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		build()


func _ready() -> void:
	build()
	if autoplay_idle and _built:
		play(look.idle_clip, 0.0)


## Assembles the model from the look. Does nothing if already built.
func build() -> void:
	if _built or look == null or look.outfit_parts.is_empty():
		return
	_built = true
	skeleton = _take_skeleton(look.outfit_parts[0])
	for i: int in range(1, look.outfit_parts.size()):
		_take_meshes(look.outfit_parts[i])
	for part: PackedScene in look.hair:
		_take_meshes(part)
	_take_head()
	_collect_surfaces()
	animation_player = AnimationPlayer.new()
	animation_player.name = &"AnimationPlayer"
	add_child(animation_player)
	animation_player.root_node = ^".."
	animation_player.add_animation_library(LIBRARY, ANIMATION_LIBRARY)
	right_hand = _add_socket(&"RightHand", RIGHT_SOCKET)
	left_hand = _add_socket(&"LeftHand", LEFT_SOCKET)
	hand_grip = HandGrip.new()
	hand_grip.name = &"HandGrip"
	skeleton.add_child(hand_grip)
	apply_palette(palette)


## Throws the built model away and assembles it again from the look.
func rebuild() -> void:
	for child: Node in [skeleton, animation_player]:
		if child != null:
			remove_child(child)
			child.free()
	skeleton = null
	animation_player = null
	right_hand = null
	left_hand = null
	hand_grip = null
	weapons.clear()
	_outfit_surfaces.clear()
	_hair_surfaces.clear()
	_materials.clear()
	_built = false
	build()


## Dresses the fighter in one of the look's palettes.
func apply_palette(index: int) -> void:
	if look == null or look.palettes.is_empty():
		return
	var p: FighterPalette = look.palettes[clampi(index, 0, look.palettes.size() - 1)]
	for entry: Array in _outfit_surfaces:
		var base: BaseMaterial3D = entry[2]
		var key: String = "outfit:%d:%d" % [p.get_instance_id(), base.get_instance_id()]
		if not _materials.has(key):
			var m: BaseMaterial3D = base.duplicate()
			if p.outfit_albedo != null:
				m.albedo_texture = p.outfit_albedo
			_materials[key] = m
		(entry[0] as MeshInstance3D).set_surface_override_material(entry[1], _materials[key])
	for entry: Array in _hair_surfaces:
		var base: BaseMaterial3D = entry[2]
		var key: String = "hair:%d:%d" % [p.get_instance_id(), base.get_instance_id()]
		if not _materials.has(key):
			var m: BaseMaterial3D = base.duplicate()
			m.albedo_color = p.hair_color
			_materials[key] = m
		(entry[0] as MeshInstance3D).set_surface_override_material(entry[1], _materials[key])


## Plays a clip of the shared library by its name (without "ual/").
func play(clip: StringName, blend: float = 0.2) -> void:
	animation_player.play(String(LIBRARY) + "/" + String(clip), blend)


## Puts a weapon in the hands: one copy in the right hand, and another in
## the left for a paired weapon, and closes those hands. Removes any weapon
## held before. (The off hand of a two-handed weapon is placed on its
## OffHandGrip by the arm IK, which comes with the guard poses.)
func attach_weapon(weapon: WeaponLook) -> Array[Node3D]:
	detach_weapons()
	weapons.append(weapon.attach(right_hand))
	hand_grip.right_hand = true
	if weapon.paired:
		weapons.append(weapon.attach(left_hand))
		hand_grip.left_hand = true
	return weapons


func detach_weapons() -> void:
	for w: Node3D in weapons:
		w.get_parent().remove_child(w)
		w.free()
	weapons.clear()
	hand_grip.right_hand = false
	hand_grip.left_hand = false


## Instantiates a part, keeps its skeleton (with the part's meshes on it) as
## the fighter's skeleton, and frees the rest.
func _take_skeleton(part: PackedScene) -> Skeleton3D:
	var root: Node = part.instantiate()
	var skel: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var xf: Transform3D = _transform_in(skel, root)
	skel.get_parent().remove_child(skel)
	_clear_owner(skel)
	root.free()
	skel.name = SKELETON_NAME
	skel.transform = xf
	add_child(skel)
	skel.owner = self
	skel.unique_name_in_owner = true
	return skel


## Moves every mesh of a part onto the fighter's skeleton.
func _take_meshes(part: PackedScene) -> Array[MeshInstance3D]:
	var root: Node = part.instantiate()
	var moved: Array[MeshInstance3D] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		var xf: Transform3D = mi.transform
		mi.get_parent().remove_child(mi)
		_clear_owner(mi)
		skeleton.add_child(mi)
		mi.transform = xf
		mi.skeleton = ^".."
		moved.append(mi)
	root.free()
	return moved


## Brings in the body's eyes and eyebrows, and its head-only mesh in place
## of the full body (keeping the body's skin and materials).
func _take_head() -> void:
	var moved: Array[MeshInstance3D] = _take_meshes(look.body_scene)
	var body: MeshInstance3D = null
	for mi: MeshInstance3D in moved:
		if body == null or mi.mesh.surface_get_array_len(0) > body.mesh.surface_get_array_len(0):
			body = mi
	var full: Mesh = body.mesh
	body.mesh = look.head_mesh
	body.name = &"Head"
	for s: int in mini(full.get_surface_count(), look.head_mesh.get_surface_count()):
		body.set_surface_override_material(s, full.surface_get_material(s))


## Finds the surfaces the palettes recolour.
func _collect_surfaces() -> void:
	for node: Node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		for s: int in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			if not (mat is BaseMaterial3D):
				continue
			if StringName(mat.resource_name) == look.outfit_material:
				_outfit_surfaces.append([mi, s, mat])
			elif mat.resource_name.begins_with("MI_Hair"):
				_hair_surfaces.append([mi, s, mat])


func _add_socket(bone: StringName, offset: Transform3D) -> Node3D:
	var attachment: BoneAttachment3D = BoneAttachment3D.new()
	attachment.name = StringName(String(bone) + "Attachment")
	skeleton.add_child(attachment)
	attachment.bone_name = bone
	var socket: Node3D = Node3D.new()
	socket.name = StringName(String(bone) + "Socket")
	socket.transform = offset
	attachment.add_child(socket)
	return socket


## A node's transform relative to one of its ancestors.
static func _transform_in(node: Node3D, ancestor: Node) -> Transform3D:
	var xf: Transform3D = node.transform
	var p: Node = node.get_parent()
	while p != null and p != ancestor:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	if ancestor is Node3D:
		xf = (ancestor as Node3D).transform * xf
	return xf


static func _clear_owner(node: Node) -> void:
	node.owner = null
	for child: Node in node.get_children():
		_clear_owner(child)
