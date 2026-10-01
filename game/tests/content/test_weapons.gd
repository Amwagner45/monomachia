extends GutTest
## The weapon models: each loads, follows the weapon-space convention
## (origin at the main grip, blade along +Y), has its markers, and has the
## size the spec gives it.

## Overall length in metres (pommel to tip), with a tolerance.
const LENGTHS: Dictionary[StringName, float] = {&"katana": 0.99, &"greatsword": 1.6, &"daggers": 0.4}
const LENGTH_TOLERANCE: float = 0.05


func _instance(id: StringName) -> Node3D:
	var look: WeaponLook = WeaponLook.load_id(id)
	var w: Node3D = look.scene.instantiate()
	add_child_autofree(w)
	return w


func test_every_playable_weapon_has_a_look() -> void:
	for id: StringName in Moves.PLAYABLE_WEAPONS:
		assert_has(WeaponLook.IDS, id)
	for id: StringName in WeaponLook.IDS:
		var look: WeaponLook = WeaponLook.load_id(id)
		assert_not_null(look, "%s loads" % id)
		assert_eq(look.id, id)
		assert_not_null(look.scene, "%s has a scene" % id)
		assert_gt(look.trail_width, 0.0, "%s has a trail width" % id)


func test_every_weapon_has_blade_markers_with_the_tip_beyond_the_base() -> void:
	for id: StringName in WeaponLook.IDS:
		var w: Node3D = _instance(id)
		var base: Marker3D = WeaponLook.marker(w, WeaponLook.BLADE_BASE)
		var tip: Marker3D = WeaponLook.marker(w, WeaponLook.BLADE_TIP)
		assert_not_null(base, "%s has BladeBase" % id)
		assert_not_null(tip, "%s has BladeTip" % id)
		if base == null or tip == null:
			continue
		assert_gt(tip.position.length(), base.position.length(), "%s: the tip is farther from the grip than the base" % id)
		assert_gt(base.position.y, 0.0, "%s: the blade starts above the grip (+Y)" % id)
		assert_gt(tip.position.y, base.position.y, "%s: the blade runs along +Y" % id)


func test_two_handed_weapons_have_an_off_hand_grip_below_the_main_one() -> void:
	for id: StringName in WeaponLook.IDS:
		var look: WeaponLook = WeaponLook.load_id(id)
		var off_hand: Marker3D = WeaponLook.marker(_instance(id), WeaponLook.OFF_HAND_GRIP)
		if look.two_handed:
			assert_not_null(off_hand, "%s has OffHandGrip" % id)
			if off_hand != null:
				assert_between(off_hand.position.y, -0.3, -0.1, "%s: the off hand sits below the main hand" % id)
		else:
			assert_null(off_hand, "%s is one-handed" % id)


func test_handedness() -> void:
	assert_true(WeaponLook.load_id(&"katana").two_handed)
	assert_true(WeaponLook.load_id(&"greatsword").two_handed)
	assert_false(WeaponLook.load_id(&"daggers").two_handed)
	assert_true(WeaponLook.load_id(&"daggers").paired, "one dagger in each hand")


func test_weapons_have_their_size() -> void:
	for id: StringName in WeaponLook.IDS:
		var bounds: AABB = _bounds(_instance(id))
		assert_almost_eq(bounds.size.y, LENGTHS[id], LENGTH_TOLERANCE, "%s is %.2f m long" % [id, bounds.size.y])
		assert_lt(bounds.position.y, 0.0, "%s: the grip origin is inside the model" % id)
		assert_gt(bounds.end.y, 0.0, "%s: the grip origin is inside the model" % id)


func test_the_katana_blade_is_072_m_and_curved_back() -> void:
	var w: Node3D = _instance(&"katana")
	var tip: Vector3 = WeaponLook.marker(w, WeaponLook.BLADE_TIP).position
	var base: Vector3 = WeaponLook.marker(w, WeaponLook.BLADE_BASE).position
	assert_almost_eq(tip.y - base.y, 0.69, 0.03, "blade from the habaki to the point")
	assert_lt(tip.x, -0.02, "the point curves back, away from the edge (+X)")
	var mesh: Mesh = (w.get_node(^"Mesh") as MeshInstance3D).mesh
	assert_eq(mesh.get_surface_count(), 6, "blade, habaki, tsuba, rim, wrap, fittings")
	for s: int in mesh.get_surface_count():
		assert_not_null(mesh.surface_get_material(s), "katana surface %d has a material" % s)


func test_weapons_attach_to_a_socket_at_the_grip_offset() -> void:
	var socket: Node3D = Node3D.new()
	add_child_autofree(socket)
	var look: WeaponLook = WeaponLook.load_id(&"greatsword")
	var w: Node3D = look.attach(socket)
	assert_eq(w.get_parent(), socket)
	assert_eq(w.transform, look.grip_offset)


## The bounds of every mesh of a weapon instance, in its own space.
static func _bounds(w: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	for node: Node in w.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		var xf: Transform3D = mi.transform
		var p: Node = mi.get_parent()
		while p != w:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var box: AABB = xf * mi.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out
