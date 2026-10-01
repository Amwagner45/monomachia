class_name FighterStandin
extends Node3D
## A stand-in fighter until the real ones (tasks 13-15): a 1.8 m capsule in the
## side's palette, a hood in the fighter's tone, a nose showing where it
## faces, two arm lines, and a stick weapon as long as the weapon (katana
## 0.95 m, greatsword 1.6 m, two 0.4 m daggers; fists when bare-handed).
##
## MatchView places it every frame from the host's blended position and yaw
## and poses it with StickPose from the rules' state: guard and block, the
## attack's sweep from wind-up through the strike to the follow-through, a
## reel when hit or parried, a fall on KO, raised weapon on victory, a red
## blade while an unblockable winds up, gold for ultimates. A floor ring in
## the palette colour and a shadow keep it readable from any camera.

## Palette colours by index: side 0 takes 0 (red) and side 1 takes 1 (blue)
## by default, as the demo's two fighters did.
const PALETTES: Array[Color] = [
	Color(0.7, 0.16, 0.13),
	Color(0.18, 0.4, 0.72),
	Color(0.18, 0.58, 0.45),
	Color(0.78, 0.58, 0.16),
]
## The fighter's own tone (hood and belt): the Rogue dark, the Hunter brown.
const TONES: Dictionary[StringName, Color] = {
	&"rogue": Color(0.12, 0.11, 0.14),
	&"hunter": Color(0.42, 0.28, 0.15),
}
const BLADE_COLOR: Color = Color(0.8, 0.82, 0.88)
## A blade's own light when nothing glows, so the thin stand-in blades read
## against a dark arena and sky.
const BLADE_SHEEN: float = 0.45
const HILT_COLOR: Color = Color(0.12, 0.1, 0.1)
const GLOW_COLORS: Dictionary[StringName, Color] = {
	&"danger": Color(1.0, 0.16, 0.08),
	&"charge": Color(1.0, 0.85, 0.55),
	&"ult": Color(1.0, 0.75, 0.2),
}

## How much of a body flash fades per world frame (the demo faded 6 per
## second).
const FLASH_FADE_PER_FRAME: float = 0.1

const HEIGHT: float = 1.8
const RADIUS: float = 0.28

var fighter_id: StringName = &"rogue"
var palette: int = 0
var weapon_id: StringName = &"katana"
var side: int = 0
## The last pose applied, for tests and debugging.
var last_pose: StickPose.Pose

var _built: bool = false
var _body: Node3D
var _torso_mat: StandardMaterial3D
var _blade_mats: Array[StandardMaterial3D] = []
var _hands: Array[Node3D] = []
var _blades: Array[MeshInstance3D] = []
var _hilts: Array[MeshInstance3D] = []
var _fists: Array[MeshInstance3D] = []
var _arms: Array[MeshInstance3D] = []
var _floor: Node3D
## The body flash: its strength when lit, the world frame it was lit on, and
## what is left of it now. Timed on the rules' frames, not the wall clock, so
## it holds through hit-stop and a screenshot stepped without rendering
## doesn't carry stale flashes.
var _flash_strength: float = 0.0
var _flash_frame: int = 0
var _flash: float = 0.0
var _flash_color: Color = Color.WHITE


func _ready() -> void:
	if not _built:
		_build()


## Sets the fighter, palette and weapon (rebuilding the meshes).
func setup(p_fighter: StringName, p_palette: int, p_weapon: StringName, p_side: int) -> void:
	fighter_id = p_fighter
	palette = p_palette
	weapon_id = p_weapon
	side = p_side
	_build()


func palette_color() -> Color:
	return PALETTES[posmod(palette, PALETTES.size())]


## Briefly lights the body (a hit) from the world frame `frame` on. A weaker
## flash than what is left of the current one doesn't replace it.
func flash(color: Color, strength: float, frame: int) -> void:
	if strength >= flash_left(frame):
		_flash_strength = strength
		_flash_frame = frame
	_flash_color = color


## What is left of the body flash at a world frame.
func flash_left(frame: int) -> float:
	return maxf(0.0, _flash_strength - FLASH_FADE_PER_FRAME * float(maxi(0, frame - _flash_frame)))


## Places and poses the stand-in for this frame. pos and yaw come from
## MatchHost.display_position() and display_yaw(); alpha from MatchHost.alpha().
func update_from(f: Fighter, pos: Vector3, yaw: float, alpha: float, _delta: float, time: float) -> void:
	if not _built:
		_build()
	position = pos
	rotation = Vector3(0.0, yaw, 0.0)
	var p: StickPose.Pose = StickPose.compute(f, alpha, time)
	last_pose = p
	# the body: lean, crouch, spin, and the fall after a KO (backwards, onto
	# the floor)
	_body.rotation = Vector3(lerpf(p.lean, -PI / 2.0, p.down), p.spin, 0.0)
	_body.position = Vector3(0.0, lerpf(-p.crouch, RADIUS, p.down), 0.0)
	# the floor marks stay on the floor while the fighter jumps
	_floor.position = Vector3(0.0, -pos.y + 0.006, 0.0)

	var bare: bool = p.bare
	var dual: bool = weapon_id == &"daggers"
	var right: StickPose.Hand = p.right
	var left: StickPose.Hand = p.left
	if p.two_handed and not bare:
		# the off hand holds the grip just below the leading hand
		left = StickPose.Hand.make(right.pos - right.dir * 0.14, right.dir)
	_place(0, right, not bare, bare)
	_place(1, left, not bare and dual, bare)
	_arm(0, Vector3(-StickPose.SHOULDER_X, StickPose.SHOULDER_Y, 0.0), right.pos)
	_arm(1, Vector3(StickPose.SHOULDER_X, StickPose.SHOULDER_Y, 0.0), left.pos)

	var glow: Color = GLOW_COLORS.get(p.glow, Color.BLACK)
	for m: StandardMaterial3D in _blade_mats:
		if p.glow != &"" and p.glow_amount > 0.0:
			m.emission = glow
			m.emission_energy_multiplier = 2.5 * p.glow_amount
		else:
			m.emission = BLADE_COLOR
			m.emission_energy_multiplier = BLADE_SHEEN

	_flash = flash_left(f.world.frame if f.world != null else _flash_frame)
	var dim: float = 0.55 if f.state == &"ko" else 1.0
	_torso_mat.albedo_color = (_base_color() * dim).lerp(_flash_color, minf(0.6, _flash))
	_torso_mat.emission = _flash_color
	_torso_mat.emission_energy_multiplier = _flash * 1.5


func _base_color() -> Color:
	var tone: Color = TONES.get(fighter_id, Color(0.3, 0.3, 0.3))
	var c: Color = palette_color().lerp(tone, 0.25)
	c.a = 1.0
	return c


func _place(i: int, hand: StickPose.Hand, blade_visible: bool, fist_visible: bool) -> void:
	var node: Node3D = _hands[i]
	node.position = hand.pos
	node.basis = basis_along(hand.dir)
	_blades[i].visible = blade_visible
	_hilts[i].visible = blade_visible
	_fists[i].visible = fist_visible


func _arm(i: int, shoulder: Vector3, hand: Vector3) -> void:
	var arm: MeshInstance3D = _arms[i]
	var d: Vector3 = hand - shoulder
	var length: float = maxf(0.01, d.length())
	arm.position = (shoulder + hand) / 2.0
	var b: Basis = basis_along(d / length)
	b.y = b.y * length
	arm.basis = b


## A basis whose Y axis points along d.
static func basis_along(d: Vector3) -> Basis:
	var y: Vector3 = d.normalized() if d.length() > 1e-6 else Vector3.UP
	var ref: Vector3 = Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x: Vector3 = ref.cross(y).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Basis(x, y, z)


# ------------------------------------------------------------------ building

func _material(color: Color, metallic: float = 0.0, roughness: float = 0.8) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	m.emission_enabled = true
	m.emission = Color.BLACK
	return m


func _mesh(parent: Node, mesh: Mesh, mat: Material, at: Vector3, node_name: String) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


func _build() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.free()
	_hands.clear()
	_blades.clear()
	_hilts.clear()
	_fists.clear()
	_arms.clear()
	_blade_mats.clear()
	_built = true
	var tone: Color = TONES.get(fighter_id, Color(0.3, 0.3, 0.3))
	var accent: Color = palette_color()

	_floor = Node3D.new()
	_floor.name = "FloorMarks"
	add_child(_floor)
	var shadow_mat: StandardMaterial3D = StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.45)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var shadow: CylinderMesh = CylinderMesh.new()
	shadow.top_radius = 0.38
	shadow.bottom_radius = 0.38
	shadow.height = 0.004
	_mesh(_floor, shadow, shadow_mat, Vector3.ZERO, "Shadow")
	var ring_mat: StandardMaterial3D = StandardMaterial3D.new()
	ring_mat.albedo_color = accent.lightened(0.2)
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = 0.5
	ring.outer_radius = 0.56
	ring.rings = 48
	ring.ring_segments = 4
	var ring_mi: MeshInstance3D = _mesh(_floor, ring, ring_mat, Vector3(0.0, 0.002, 0.0), "SideRing")
	ring_mi.scale = Vector3(1.0, 0.05, 1.0)

	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_torso_mat = _material(_base_color())
	var torso: CapsuleMesh = CapsuleMesh.new()
	torso.radius = RADIUS
	torso.height = HEIGHT
	_mesh(_body, torso, _torso_mat, Vector3(0.0, HEIGHT / 2.0, 0.0), "Torso")
	var tone_mat: StandardMaterial3D = _material(tone)
	var hood: SphereMesh = SphereMesh.new()
	hood.radius = 0.25
	hood.height = 0.42
	_mesh(_body, hood, tone_mat, Vector3(0.0, 1.6, -0.03), "Hood")
	var belt: CylinderMesh = CylinderMesh.new()
	belt.top_radius = RADIUS + 0.02
	belt.bottom_radius = RADIUS + 0.03
	belt.height = 0.12
	_mesh(_body, belt, tone_mat, Vector3(0.0, 0.98, 0.0), "Belt")
	var nose: BoxMesh = BoxMesh.new()
	nose.size = Vector3(0.1, 0.07, 0.24)
	_mesh(_body, nose, _material(Color(0.92, 0.86, 0.78)), Vector3(0.0, 1.58, 0.28), "Nose")

	var arm_mat: StandardMaterial3D = _material(tone.lightened(0.15))
	var length: float = StickPose.LENGTH.get(weapon_id, 0.9)
	var two_handed: bool = weapon_id == &"katana" or weapon_id == &"greatsword"
	var hilt_len: float = 0.24 if two_handed else 0.1
	var blade_w: float = 0.075 if weapon_id == &"greatsword" else 0.05
	for i: int in 2:
		var arm_mesh: CylinderMesh = CylinderMesh.new()
		arm_mesh.top_radius = 0.045
		arm_mesh.bottom_radius = 0.05
		arm_mesh.height = 1.0
		arm_mesh.radial_segments = 8
		_arms.append(_mesh(_body, arm_mesh, arm_mat, Vector3.ZERO, "Arm%s" % ("R" if i == 0 else "L")))

		var hand: Node3D = Node3D.new()
		hand.name = "Hand%s" % ("R" if i == 0 else "L")
		_body.add_child(hand)
		_hands.append(hand)
		var blade_mat: StandardMaterial3D = _material(BLADE_COLOR, 0.15, 0.3)
		_blade_mats.append(blade_mat)
		var blade: BoxMesh = BoxMesh.new()
		blade.size = Vector3(blade_w, maxf(0.05, length - 0.04), 0.035)
		_blades.append(_mesh(hand, blade, blade_mat, Vector3(0.0, 0.04 + (length - 0.04) / 2.0, 0.0), "Blade"))
		var hilt: BoxMesh = BoxMesh.new()
		hilt.size = Vector3(0.04, hilt_len, 0.04)
		var hilt_mi: MeshInstance3D = _mesh(hand, hilt, _material(HILT_COLOR), Vector3(0.0, 0.04 - hilt_len / 2.0, 0.0), "Hilt")
		var guard: BoxMesh = BoxMesh.new()
		guard.size = Vector3(0.12, 0.025, 0.08)
		_mesh(hilt_mi, guard, _material(HILT_COLOR.lightened(0.3)), Vector3(0.0, hilt_len / 2.0, 0.0), "Guard")
		_hilts.append(hilt_mi)
		var fist: SphereMesh = SphereMesh.new()
		fist.radius = 0.075
		fist.height = 0.15
		_fists.append(_mesh(hand, fist, arm_mat, Vector3.ZERO, "Fist"))
