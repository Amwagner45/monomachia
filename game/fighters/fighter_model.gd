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
##   WeaponLook for their frame), and `attach_weapon()`, which puts a weapon
##   in the hands the way the look's WeaponHold for it says, and closes the
##   holding hands through `hand_grip`;
## - `idle_clip()` / `play_idle()`: the clip to idle in with the held weapon;
## - `apply_palette()`: switches between the look's two palettes.
##
## Every surface is drawn in the toon look (ToonMaterials.fighter_from(): the
## imported texture, normal map and vertex colour kept, drawn from both sides
## like the import, with an ink outline), and every mesh is on the fighters'
## render layer (LookPalette.FIGHTER_LAYER), so the arena's rim light finds
## it. The palettes recolour the toon materials.
##
## Built nodes are not owned by the scene, so they are never saved into it;
## the skeleton alone is owned by this node, so that its unique name resolves.
## The script doesn't run in the editor, where a fighter scene shows empty:
## run fighters/preview/preview.tscn to look at the fighters.

const ANIMATION_LIBRARY: AnimationLibrary = preload("res://assets/quaternius/animations/ual_library.res")
const HEADWEAR_CLOTH: Material = preload("res://fighters/materials/headwear_cloth.tres")
const LIBRARY: StringName = &"ual"
const SKELETON_NAME: StringName = &"GeneralSkeleton"
## The render layers of every fighter mesh.
const LAYERS: int = 1 | LookPalette.FIGHTER_LAYER

## Hand sockets in hand-bone space. After retargeting, a hand bone's +Y runs
## from the wrist to the knuckles and +Z comes out of the palm; +X points to
## the thumb on the right hand and away from it on the left. The socket sits
## in the hollow of a closed fist with +Y out of the thumb side and +X out of
## the knuckles.
const RIGHT_SOCKET: Transform3D = Transform3D(
	Basis(Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)), Vector3(0.0, 0.07, 0.028))
const LEFT_SOCKET: Transform3D = Transform3D(
	Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1)), Vector3(0.0, 0.07, 0.028))

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
			_dress(value)
## Play the idle clip on entering the tree.
@export var autoplay_idle: bool = true

var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var right_hand: Node3D
var left_hand: Node3D
## Closes the hands that hold a weapon and sets their wrists (see
## attach_weapon()).
var hand_grip: HandGrip
## The weapon models attached by attach_weapon().
var weapons: Array[Node3D] = []
## The look's hold for the held weapon, or null.
var hold: WeaponHold

var _built: bool = false
## [MeshInstance3D, surface index, imported material] for each outfit surface.
var _outfit_surfaces: Array[Array] = []
## The same for the hair and eyebrows, and for the headwear's cloth.
var _hair_surfaces: Array[Array] = []
var _headwear_surfaces: Array[Array] = []
var _materials: Dictionary[String, Material] = {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		build()


func _ready() -> void:
	build()
	if autoplay_idle and _built:
		play_idle(0.0)


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
	var head: MeshInstance3D = _take_head()
	_take_headwear(head)
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
	_dress(palette)


## Throws the built model away and assembles it again from the look, in the
## same palette, idling again if it idles on entering the tree.
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
	hold = null
	weapons.clear()
	_outfit_surfaces.clear()
	_hair_surfaces.clear()
	_headwear_surfaces.clear()
	_materials.clear()
	_built = false
	build()
	if autoplay_idle and _built and is_inside_tree():
		play_idle(0.0)


## Dresses the fighter in one of the look's palettes, and remembers it.
func apply_palette(index: int) -> void:
	palette = index


func _dress(index: int) -> void:
	if look == null or look.palettes.is_empty():
		return
	var p: FighterPalette = look.palettes[clampi(index, 0, look.palettes.size() - 1)]
	for entry: Array in _outfit_surfaces:
		_override(entry, "outfit", p, func(m: BaseMaterial3D) -> void:
			if p.outfit_albedo != null:
				m.albedo_texture = p.outfit_albedo)
	for entry: Array in _hair_surfaces:
		_override(entry, "hair", p, func(m: BaseMaterial3D) -> void:
			m.albedo_color = p.hair_color)
	for entry: Array in _headwear_surfaces:
		_override(entry, "headwear", p, func(m: BaseMaterial3D) -> void:
			m.albedo_color = p.headwear_color)


## Gives a surface the toon version of its imported material, recoloured for
## palette `p` by `setup` (on a copy of the import). The toon materials are
## cached, so switching back and forth makes no new ones.
func _override(entry: Array, kind: String, p: FighterPalette, setup: Callable) -> void:
	var base: BaseMaterial3D = entry[2]
	var key: String = "%s:%d:%d" % [kind, p.get_instance_id(), base.get_instance_id()]
	if not _materials.has(key):
		var m: BaseMaterial3D = base.duplicate()
		setup.call(m)
		_materials[key] = ToonMaterials.fighter_from(m)
	(entry[0] as MeshInstance3D).set_surface_override_material(entry[1], _materials[key])


## The clip to idle in with the held weapon.
func idle_clip() -> StringName:
	if hold != null and hold.clip != &"":
		return hold.clip
	return look.idle_clip


## Plays the idle clip for the held weapon.
func play_idle(blend: float = 0.2) -> void:
	play(idle_clip(), blend)


## Plays a clip of the shared library by its name (without "ual/").
func play(clip: StringName, blend: float = 0.2) -> void:
	animation_player.play(String(LIBRARY) + "/" + String(clip), blend)


## Puts a weapon in the hands: one copy in the right hand, and another in
## the left for a paired weapon, held the way the look's hold for it says
## (grip, wrists and idle clip), and closes those hands. Removes any weapon
## held before, and builds the model first if needed. A left hand that holds
## a weapon has its wrist set (to straight when there is no hold) unless the
## hold says to keep the clip's, because the clips leave the left hand open
## and turned for a free hand. (The off hand of a two-handed weapon is placed
## on its OffHandGrip by the arm IK, which comes with the guard poses.)
func attach_weapon(weapon: WeaponLook) -> Array[Node3D]:
	build()
	if not _built:
		push_error("FighterModel.attach_weapon: there is no look to build the fighter from")
		return weapons
	detach_weapons()
	hold = look.hold_for(weapon.id)
	var grip: Transform3D = hold.grip_transform() if hold != null else Transform3D.IDENTITY
	weapons.append(weapon.attach(right_hand, grip))
	hand_grip.right_hand = true
	if hold != null and hold.set_right_wrist:
		hand_grip.set_wrist("Right", hold.right_wrist)
	if weapon.paired:
		weapons.append(weapon.attach(left_hand, grip))
		hand_grip.left_hand = true
		if hold == null or hold.set_left_wrist:
			hand_grip.set_wrist("Left", hold.left_wrist if hold != null else Vector3.ZERO)
	return weapons


func detach_weapons() -> void:
	for w: Node3D in weapons:
		w.get_parent().remove_child(w)
		w.free()
	weapons.clear()
	hold = null
	if hand_grip != null:
		hand_grip.right_hand = false
		hand_grip.left_hand = false
		hand_grip.clear_wrists()


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
## of the full body, keeping the body's materials but with the look's baked
## skin. Returns the head.
func _take_head() -> MeshInstance3D:
	var moved: Array[MeshInstance3D] = _take_meshes(look.body_scene)
	var body: MeshInstance3D = null
	for mi: MeshInstance3D in moved:
		if body == null or mi.mesh.surface_get_array_len(0) > body.mesh.surface_get_array_len(0):
			body = mi
	var full: Mesh = body.mesh
	body.mesh = look.head_mesh
	body.name = &"Head"
	for s: int in mini(full.get_surface_count(), look.head_mesh.get_surface_count()):
		var skin: BaseMaterial3D = (full.surface_get_material(s) as BaseMaterial3D).duplicate()
		if look.skin_albedo != null:
			skin.albedo_texture = look.skin_albedo
		body.set_surface_override_material(s, skin)
	return body


## Adds the look's head wrap (skinned like the head) and hat (on the Head
## bone).
func _take_headwear(head: MeshInstance3D) -> void:
	if look.head_wrap != null:
		var wrap: MeshInstance3D = MeshInstance3D.new()
		wrap.name = &"HeadWrap"
		wrap.mesh = look.head_wrap
		wrap.skin = head.skin
		skeleton.add_child(wrap)
		wrap.skeleton = ^".."
	if look.hat != null:
		var attachment: BoneAttachment3D = BoneAttachment3D.new()
		attachment.name = &"HeadAttachment"
		skeleton.add_child(attachment)
		attachment.bone_name = &"Head"
		var hat: MeshInstance3D = MeshInstance3D.new()
		hat.name = &"Hat"
		hat.mesh = look.hat
		attachment.add_child(hat)


## Puts every mesh on the fighters' layer, finds the surfaces the palettes
## recolour (_dress() puts those in the toon look), and puts every other
## surface (the skin, the eyes, the hat's band) in the toon look now.
func _collect_surfaces() -> void:
	for node: Node in skeleton.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		mi.layers = LAYERS
		for s: int in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			if not (mat is BaseMaterial3D):
				push_error("FighterModel: %s surface %d has no imported material to draw in the toon look" % [mi.name, s])
				continue
			if StringName(mat.resource_name) == look.outfit_material:
				_outfit_surfaces.append([mi, s, mat])
			elif mat.resource_name.begins_with("MI_Hair"):
				_hair_surfaces.append([mi, s, mat])
			elif mat.resource_name == HEADWEAR_CLOTH.resource_name:
				_headwear_surfaces.append([mi, s, mat])
			else:
				var toon: ShaderMaterial = ToonMaterials.fighter_from(mat)
				mi.set_surface_override_material(s, toon)
				# Held here too: a material only the override holds is freed
				# before the mesh instance lets go of it, which the renderer
				# reports.
				_materials["toon:%d:%d" % [mi.get_instance_id(), s]] = toon


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
