extends GutTest
## The fighter scenes: they load and assemble without errors, their skeleton
## is the retargeted humanoid one, the shared clips drive it, they have hand
## sockets and two palettes, and the body is cut down to the head.

const BONE_MAP: String = "res://assets/quaternius/ual_bone_map.tres"
## Profile bones with no Quaternius source bone.
const UNMAPPED: Array[StringName] = [&"LeftEye", &"RightEye", &"Jaw"]


func _fighter(id: StringName) -> FighterModel:
	var f: FighterModel = FighterLook.instantiate_fighter(id)
	add_child_autofree(f)
	return f


func test_there_are_two_fighters() -> void:
	assert_eq(FighterLook.IDS.size(), 2)
	assert_has(FighterLook.IDS, &"rogue")
	assert_has(FighterLook.IDS, &"hunter")


func test_every_fighter_scene_loads_and_assembles() -> void:
	for id: StringName in FighterLook.IDS:
		var f: FighterModel = _fighter(id)
		assert_not_null(f.look, "%s has a look" % id)
		assert_eq(f.look.id, id)
		assert_not_null(f.skeleton, "%s has a skeleton" % id)
		var meshes: Array[Node] = f.skeleton.find_children("*", "MeshInstance3D", true, false)
		# Outfit parts (several meshes each), hair, head, eyes and eyebrows.
		assert_gt(meshes.size(), f.look.outfit_parts.size() + f.look.hair.size() + 2, "%s has all its parts" % id)
		for node: Node in meshes:
			var mi: MeshInstance3D = node
			assert_eq(mi.get_node(mi.skeleton), f.skeleton, "%s: %s is skinned to the fighter's skeleton" % [id, mi.name])


func test_the_bone_map_maps_53_humanoid_bones() -> void:
	var bone_map: BoneMap = load(BONE_MAP)
	var profile: SkeletonProfile = bone_map.profile
	assert_eq(profile.bone_size, 56)
	var mapped: int = 0
	for i: int in profile.bone_size:
		if bone_map.get_skeleton_bone_name(profile.get_bone_name(i)) != &"":
			mapped += 1
	assert_eq(mapped, 53)


func test_every_fighter_skeleton_has_all_53_humanoid_bones() -> void:
	var profile: SkeletonProfileHumanoid = SkeletonProfileHumanoid.new()
	for id: StringName in FighterLook.IDS:
		var f: FighterModel = _fighter(id)
		var found: int = 0
		for i: int in profile.bone_size:
			var bone: StringName = profile.get_bone_name(i)
			if UNMAPPED.has(bone):
				continue
			assert_gt(f.skeleton.find_bone(bone), -1, "%s has bone %s" % [id, bone])
			found += 1
		assert_eq(found, 53, id)
		assert_eq(f.skeleton.get_bone_count(), 65, "%s keeps the 65-bone Quaternius skeleton" % id)


func test_the_skeleton_is_the_unique_node_the_clips_address() -> void:
	for id: StringName in FighterLook.IDS:
		var f: FighterModel = _fighter(id)
		assert_eq(f.get_node(^"%GeneralSkeleton"), f.skeleton, id)


func test_the_shared_clips_drive_every_fighter() -> void:
	for id: StringName in FighterLook.IDS:
		var f: FighterModel = _fighter(id)
		var ap: AnimationPlayer = f.animation_player
		assert_true(ap.has_animation("ual/" + String(f.look.idle_clip)), "%s idle clip" % id)
		assert_true(ap.has_animation("ual/" + String(f.look.walk_clip)), "%s walk clip" % id)
		var thigh: int = f.skeleton.find_bone(&"LeftUpperLeg")
		var rest: Quaternion = f.skeleton.get_bone_rest(thigh).basis.get_rotation_quaternion()
		f.play(f.look.walk_clip, 0.0)
		ap.seek(0.3, true)
		var posed: Quaternion = f.skeleton.get_bone_pose_rotation(thigh)
		assert_gt(rad_to_deg(posed.angle_to(rest)), 5.0, "%s's walk clip moves the thigh" % id)


func test_every_fighter_has_hand_sockets() -> void:
	for id: StringName in FighterLook.IDS:
		var f: FighterModel = _fighter(id)
		for pair: Array in [[f.right_hand, &"RightHand"], [f.left_hand, &"LeftHand"]]:
			var socket: Node3D = pair[0]
			assert_not_null(socket, "%s %s socket" % [id, pair[1]])
			var attachment: BoneAttachment3D = socket.get_parent() as BoneAttachment3D
			assert_not_null(attachment)
			assert_eq(attachment.bone_name, String(pair[1]))
			assert_eq(attachment.get_parent(), f.skeleton)


func test_attaching_weapons_fills_the_right_hands() -> void:
	var f: FighterModel = _fighter(&"rogue")
	var held: Array[Node3D] = f.attach_weapon(WeaponLook.load_id(&"daggers"))
	assert_eq(held.size(), 2, "one dagger per hand")
	assert_eq(held[0].get_parent(), f.right_hand)
	assert_eq(held[1].get_parent(), f.left_hand)
	assert_true(f.hand_grip.right_hand and f.hand_grip.left_hand)
	held = f.attach_weapon(WeaponLook.load_id(&"greatsword"))
	assert_eq(held.size(), 1)
	assert_eq(held[0].get_parent(), f.right_hand)
	assert_eq(f.left_hand.get_child_count(), 0, "the daggers were removed")
	assert_false(f.hand_grip.left_hand)


func test_signature_weapons() -> void:
	assert_eq((load(FighterLook.path_for(&"rogue")) as FighterLook).signature_weapon, &"daggers")
	assert_eq((load(FighterLook.path_for(&"hunter")) as FighterLook).signature_weapon, &"greatsword")


func test_every_fighter_has_two_different_palettes() -> void:
	for id: StringName in FighterLook.IDS:
		var f: FighterModel = _fighter(id)
		assert_eq(f.look.palettes.size(), 2, id)
		var a: FighterPalette = f.look.palettes[0]
		var b: FighterPalette = f.look.palettes[1]
		assert_not_null(a.outfit_albedo, "%s palette A is baked" % id)
		assert_not_null(b.outfit_albedo, "%s palette B is baked" % id)
		assert_ne(a.outfit_albedo, b.outfit_albedo)
		assert_ne(a.trim_color, b.trim_color, "%s palettes differ in trim" % id)
		f.apply_palette(0)
		assert_eq(_outfit_texture(f), a.outfit_albedo, "%s wears palette A" % id)
		f.apply_palette(1)
		assert_eq(_outfit_texture(f), b.outfit_albedo, "%s wears palette B" % id)


func _outfit_texture(f: FighterModel) -> Texture2D:
	for node: Node in f.skeleton.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		for s: int in mi.mesh.get_surface_count():
			var override: Material = mi.get_surface_override_material(s)
			if override is BaseMaterial3D and StringName(override.resource_name) == f.look.outfit_material:
				return (override as BaseMaterial3D).albedo_texture
	return null


func test_no_fighter_material_misses_a_texture() -> void:
	for id: StringName in FighterLook.IDS:
		var f: FighterModel = _fighter(id)
		for node: Node in f.skeleton.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = node
			for s: int in mi.mesh.get_surface_count():
				var mat: BaseMaterial3D = mi.get_active_material(s) as BaseMaterial3D
				assert_not_null(mat, "%s %s surface %d has a material" % [id, mi.name, s])
				if mat == null:
					continue
				assert_not_null(mat.albedo_texture, "%s %s (%s) has its base colour" % [id, mi.name, mat.resource_name])
				if mat.normal_enabled:
					assert_not_null(mat.normal_texture, "%s %s (%s) has its normal map" % [id, mi.name, mat.resource_name])


func test_the_body_is_cut_down_to_the_head_and_neck() -> void:
	for id: StringName in FighterLook.IDS:
		var look: FighterLook = load(FighterLook.path_for(id))
		var body_scene: Node = look.body_scene.instantiate()
		var body: MeshInstance3D = null
		for node: Node in body_scene.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = node
			if body == null or mi.mesh.surface_get_array_len(0) > body.mesh.surface_get_array_len(0):
				body = mi
		var head_binds: Array[int] = []
		for i: int in body.skin.get_bind_count():
			if body.skin.get_bind_name(i) in [&"Head", &"Neck"]:
				head_binds.append(i)
		var arrays: Array = look.head_mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per: int = bones.size() / verts.size()
		var lowest: float = 1.0
		for v: int in verts.size():
			var w: float = 0.0
			for k: int in per:
				if head_binds.has(bones[v * per + k]):
					w += weights[v * per + k]
			lowest = minf(lowest, w)
		assert_gt(lowest, 0.499, "%s: every head vertex is mostly on the head and neck" % id)
		var full_tris: int = body.mesh.surface_get_array_index_len(0) / 3
		var head_tris: int = look.head_mesh.surface_get_array_index_len(0) / 3
		assert_between(head_tris, 1000, full_tris / 3, "%s: the head keeps %d of %d triangles" % [id, head_tris, full_tris])
		body_scene.free()
