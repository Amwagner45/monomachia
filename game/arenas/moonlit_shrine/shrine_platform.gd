class_name ShrinePlatform
extends RefCounted
## Builds the Moonlit Shrine's courtyard: the paved floor and its stone edge,
## the parapet that stops fighters, a landing at each gate with steps down,
## each gate's rope barrier, and flat pebbles along the foot of the parapet.
## Everything stands outside the walkable circle except the floor and the
## pebbles.
##
## Each gate's rope barrier is its own node (GateRope0, GateRope1, by gate
## index), so the match intro can drop it while a fighter walks in.

const STONE_FLOOR: Shader = preload("res://shaders/stone_floor.gdshader")

## Ledge height: the rock shelf around the courtyard (task 17.5), just below
## the floor. The plinth and the gate steps reach down to it.
const LEDGE_Y := -0.3
## Half the width of a parapet post, and how much wider the posts beside a
## gate opening are.
const POST_HALF := 0.16
const END_POST_WIDEN := 1.3

## Kits whose meshes get smoothed outline normals and the prop outline.
const OUTLINED: Array[StringName] = [&"landing", &"parapet", &"stone_dark", &"rope"]
const NO_SHADOW: Array[StringName] = [&"paper", &"pebbles"]


## Builds the platform under a new Node3D named Platform.
static func build(layout: ShrineLayout, def: ArenaDef) -> Node3D:
	var root := Node3D.new()
	root.name = "Platform"
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.seed
	_floor(root, layout, def)
	var mats: Dictionary[StringName, Material] = ShrineProps.materials()
	var kits := MeshKitSet.new()
	_parapet(kits, layout, def, rng)
	_gates(kits, root, layout, def, mats)
	_pebbles(kits, layout, def, rng)
	var meshes := Node3D.new()
	meshes.name = "Props"
	root.add_child(meshes)
	kits.finish(meshes, mats, OUTLINED, NO_SHADOW)
	return root


static func _floor(root: Node3D, layout: ShrineLayout, def: ArenaDef) -> void:
	var kit := MeshKit.new()
	kit.disc(Transform3D.IDENTITY, def.floor_radius, 96, 6)
	var mat: ShaderMaterial = ToonMaterials.make_with_shader(STONE_FLOOR, ToonMaterials.OutlineKind.NONE, {
		&"centre_radius": layout.centre_radius,
		&"ring_width": layout.ring_width,
		&"tile_length": layout.tile_length,
		&"brush_noise": 0.06,
		&"wall_radius": def.wall_inner_radius(),
	})
	var floor_mi := MeshKit.instance(kit.commit(), mat, false)
	floor_mi.name = "Floor"
	floor_mi.layers = LookPalette.GROUND_LAYER
	root.add_child(floor_mi)
	# The courtyard's stone edge, down to the rock ledge.
	var plinth := MeshKit.new()
	plinth.lathe(Transform3D.IDENTITY, PackedVector2Array([
		Vector2(def.floor_radius + 0.25, LEDGE_Y - 0.25), Vector2(def.floor_radius + 0.08, -0.08),
		Vector2(def.floor_radius, 0.0),
	]), 128, false, false)
	var plinth_mi := MeshKit.instance(plinth.commit(true), ToonMaterials.prop(LookPalette.STONE_DARK, 0.4), false)
	plinth_mi.name = "Plinth"
	root.add_child(plinth_mi)


## Angle of parapet post i, in degrees.
static func post_angle(layout: ShrineLayout, i: int) -> float:
	return (i + 0.5) * 360.0 / layout.post_count


## Angle (degrees, from +Z toward +X) of each gate anchor in def.
static func gate_angles(def: ArenaDef) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for g: Transform3D in def.gate_anchors:
		out.append(rad_to_deg(atan2(g.origin.x, g.origin.z)))
	return out


## How far apart two angles are (degrees, 0 to 180).
static func _angle_apart(a: float, b: float) -> float:
	return absf(wrapf(a - b, -180.0, 180.0))


## Whether angle a (degrees) is within margin degrees of a gate.
static func near_gate(a: float, def: ArenaDef, margin: float) -> bool:
	for g: float in gate_angles(def):
		if _angle_apart(a, g) < margin:
			return true
	return false


## Whether post i is left out to open the parapet at a gate.
static func post_in_gate(layout: ShrineLayout, def: ArenaDef, i: int) -> bool:
	return near_gate(post_angle(layout, i), def, layout.gate_opening_deg)


## Centres of every parapet post (arena space), for the tests.
static func post_positions(layout: ShrineLayout, def: ArenaDef) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i: int in layout.post_count:
		if not post_in_gate(layout, def, i):
			out.append(ShrineLayout.polar(post_angle(layout, i), def.wall_radius))
	return out


static func _parapet(kits: MeshKitSet, layout: ShrineLayout, def: ArenaDef, rng: RandomNumberGenerator) -> void:
	var stone: MeshKit = kits.kit(&"parapet")
	var half_t: float = def.wall_thickness * 0.5
	var curb_h := 0.17
	stone.color = Color(0.92, 0.92, 0.94)
	stone.lathe(Transform3D.IDENTITY, PackedVector2Array([
		Vector2(def.wall_radius + half_t, -0.02), Vector2(def.wall_radius + half_t, curb_h),
		Vector2(def.wall_radius - half_t, curb_h), Vector2(def.wall_radius - half_t, -0.02),
	]), 160, false, false)
	var top: float = def.wall_height
	var n: int = layout.post_count
	for i: int in n:
		if post_in_gate(layout, def, i):
			continue
		var a: float = post_angle(layout, i)
		var basis := Basis(Vector3.UP, deg_to_rad(a))
		var c: Vector3 = ShrineLayout.polar(a, def.wall_radius)
		stone.color = Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.18))
		var end_post: bool = post_in_gate(layout, def, (i + 1) % n) or post_in_gate(layout, def, (i - 1 + n) % n)
		var damaged: bool = layout.damaged_posts.has(i)
		var w: float = POST_HALF * 2.0 * (END_POST_WIDEN if end_post else 1.0)
		var h: float = top - curb_h + (0.25 if end_post else 0.0) - (0.38 if damaged else 0.0)
		stone.box(Transform3D(basis, c + Vector3(0, curb_h + h * 0.5, 0)), Vector3(w, h, w))
		if damaged:
			continue
		stone.box(Transform3D(basis, c + Vector3(0, curb_h + h + 0.035, 0)), Vector3(w + 0.08, 0.07, w + 0.08))
		stone.lathe(Transform3D(basis, c + Vector3(0, curb_h + h + 0.07, 0)), PackedVector2Array([
			Vector2(0.0, 0.0), Vector2(w * 0.38, 0.0), Vector2(w * 0.45, 0.07), Vector2(w * 0.26, 0.17), Vector2(0.0, 0.26),
		]), 8, false)
	# Rails between neighbouring posts.
	for i: int in n:
		var j: int = (i + 1) % n
		if post_in_gate(layout, def, i) or post_in_gate(layout, def, j):
			continue
		var a0: float = post_angle(layout, i)
		var a1: float = a0 + 360.0 / n
		var mid: float = deg_to_rad((a0 + a1) * 0.5)
		var basis := Basis(Vector3.UP, mid)
		var p0: Vector3 = ShrineLayout.polar(a0, def.wall_radius)
		var p1: Vector3 = ShrineLayout.polar(a1, def.wall_radius)
		var centre: Vector3 = (p0 + p1) * 0.5
		var length: float = p0.distance_to(p1) - POST_HALF * 2.0 + 0.04
		stone.color = Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.12))
		stone.box(Transform3D(basis, centre + Vector3(0, 0.45, 0)), Vector3(length, 0.09, 0.13))
		if layout.broken_rails.has(i):
			var stub: float = length * 0.28
			var tangent: Vector3 = basis.x
			stone.box(Transform3D(basis.rotated(tangent.cross(Vector3.UP), 0.12), centre - tangent * (length - stub) * 0.5 + Vector3(0, top - 0.11, 0)),
				Vector3(stub, 0.12, 0.17))
			stone.box(Transform3D(basis, centre + tangent * (length - stub) * 0.5 + Vector3(0, top - 0.1, 0)),
				Vector3(stub * 0.8, 0.12, 0.17))
			# The broken middle lies just outside, on the floor's edge.
			var outward: Vector3 = basis.z
			var rubble: MeshKit = kits.kit(&"stone_dark")
			rubble.box(Transform3D(Basis(Vector3.UP, mid + 0.4).rotated(outward, 0.2), centre + outward * 0.62 + Vector3(0, 0.05, 0)),
				Vector3(length * 0.35, 0.12, 0.17))
		else:
			stone.box(Transform3D(basis, centre + Vector3(0, top - 0.1, 0)), Vector3(length, 0.12, 0.17))


## Each gate's landing, level with the floor, with two steps down to the
## ledge, and its rope barrier. The torii that stand on the landings come
## with task 17.4.
static func _gates(kits: MeshKitSet, root: Node3D, layout: ShrineLayout, def: ArenaDef,
		mats: Dictionary[StringName, Material]) -> void:
	var span_angle: float = _gate_end_angle(layout, def)
	var angles: PackedFloat32Array = gate_angles(def)
	var stone: MeshKit = kits.kit(&"landing")
	stone.color = Color(0.86, 0.86, 0.9)
	for side: int in def.gate_anchors.size():
		# The anchor stands at the gate, facing into the arena: its local +z
		# points outward.
		var xform: Transform3D = def.gate_anchor(side)
		var gate_r: float = Vector2(xform.origin.x, xform.origin.z).length()
		var angle: float = angles[side]
		var near_z: float = def.floor_radius - 0.3 - gate_r
		var far_z: float = 3.0
		stone.box(xform * Transform3D(Basis(), Vector3(0, -0.36, (near_z + far_z) * 0.5)), Vector3(layout.torii_span + 1.4, 0.7, far_z - near_z))
		for k: int in 2:
			stone.box(xform * Transform3D(Basis(), Vector3(0, -0.12 - 0.17 * k - 0.35, far_z + 0.3 + 0.45 * k)),
				Vector3(layout.torii_span + 1.0 - k * 0.4, 0.7, 0.6))
		# A rope barrier across the parapet opening, tied to the outer faces of
		# the end posts so its sag stays outside the walkable circle.
		var rope_r: float = def.wall_radius + def.wall_thickness * 0.3
		var a: Vector3 = ShrineLayout.polar(angle - span_angle, rope_r, def.wall_height + 0.1)
		var b: Vector3 = ShrineLayout.polar(angle + span_angle, rope_r, def.wall_height + 0.1)
		var rope_kits := MeshKitSet.new()
		ShrineProps.shimenawa(rope_kits, a, b, 0.32, 5, 0.085)
		var rope := Node3D.new()
		rope.name = "GateRope%d" % side
		root.add_child(rope)
		rope_kits.finish(rope, mats, OUTLINED, NO_SHADOW)


## Angle of the gate end posts from the gate axis.
static func _gate_end_angle(layout: ShrineLayout, def: ArenaDef) -> float:
	var gate: float = gate_angles(def)[0]
	var best: float = 180.0
	for i: int in layout.post_count:
		if not post_in_gate(layout, def, i):
			best = minf(best, _angle_apart(post_angle(layout, i), gate))
	return best


## Flat pebbles along the inside foot of the parapet, clear of the gates:
## the only things inside the walkable circle, and never in the way.
static func _pebbles(kits: MeshKitSet, layout: ShrineLayout, def: ArenaDef, rng: RandomNumberGenerator) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = layout.seed
	noise.frequency = 3.0
	var pebbles: MeshKit = kits.kit(&"pebbles")
	for i: int in layout.pebble_count:
		var a: float = rng.randf_range(0.0, 360.0)
		while near_gate(a, def, 12.0):
			a = rng.randf_range(0.0, 360.0)
		var r: float = rng.randf_range(def.walkable_radius - 0.5, def.wall_inner_radius() - 0.05)
		var size: float = rng.randf_range(0.04, 0.08)
		pebbles.color = Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.3))
		var b := Basis(Vector3(rng.randf(), 1.0, rng.randf()).normalized(), rng.randf_range(0, TAU)) \
			.scaled(Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.45, 0.8), rng.randf_range(0.8, 1.3)))
		pebbles.sphere(Transform3D(b, ShrineLayout.polar(a, r, size * 0.25)), size, 7, 4, noise, size * 0.35)
