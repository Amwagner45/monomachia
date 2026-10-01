extends Node3D
## The stand-in arena until the Moonlit Shrine lands (task 17): a flat dark
## floor out to the wall at SimConst.ARENA_RADIUS with a ring along the wall, a
## lower apron outside it so the follow camera never looks into the void, a
## few pillars for scale, a moon light and a dark sky. Built in code from the
## rules' radius, so it follows when task 8 changes it.
##
## It carries the arena seams the real arena will fill (see ArenaScenes):
## Spawn0, Spawn1, Gate0 and Gate1 markers.

const FLOOR_COLOR: Color = Color(0.075, 0.07, 0.085)
const LINE_COLOR: Color = Color(0.2, 0.17, 0.2)
const WALL_COLOR: Color = Color(0.42, 0.12, 0.1)
const APRON_COLOR: Color = Color(0.04, 0.037, 0.045)
const PILLAR_COLOR: Color = Color(0.3, 0.27, 0.26)

## Apron reach past the wall (m): wider than the camera's clamp margin.
@export var apron: float = 5.5
@export var pillar_count: int = 8
## Pillar ring distance past the wall (m).
@export var pillar_offset: float = 1.8
@export var pillar_height: float = 4.5


func _ready() -> void:
	var r: float = SimConst.ARENA_RADIUS
	_build_environment()
	_build_floor(r)
	_build_wall(r)
	_build_pillars(r)
	_build_markers(r)


func _material(color: Color, roughness: float = 0.9, emission: float = 0.0) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


func _mesh(mesh: Mesh, mat: Material, at: Vector3, node_name: String) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	add_child(mi)
	return mi


func _build_environment() -> void:
	var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.025, 0.03, 0.07)
	sky_mat.sky_horizon_color = Color(0.2, 0.12, 0.17)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.1, 0.07, 0.09)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.015)
	var sky: Sky = Sky.new()
	sky.sky_material = sky_mat
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.08, 0.11)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	var we: WorldEnvironment = WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	add_child(we)

	var moon: DirectionalLight3D = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.85, 0.85, 1.0)
	moon.light_energy = 1.1
	moon.shadow_enabled = true
	moon.rotation_degrees = Vector3(-50.0, 150.0, 0.0)
	add_child(moon)

	var rim: DirectionalLight3D = DirectionalLight3D.new()
	rim.name = "Rim"
	rim.light_color = Color(0.95, 0.55, 0.4)
	rim.light_energy = 0.35
	rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	rim.rotation_degrees = Vector3(-20.0, -30.0, 0.0)
	add_child(rim)


func _build_floor(r: float) -> void:
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = r
	disc.bottom_radius = r
	disc.height = 0.2
	disc.radial_segments = 96
	_mesh(disc, _material(FLOOR_COLOR), Vector3(0.0, -0.1, 0.0), "Floor")

	var outer: CylinderMesh = CylinderMesh.new()
	outer.top_radius = r + apron
	outer.bottom_radius = r + apron - 1.5
	outer.height = 1.2
	outer.radial_segments = 96
	_mesh(outer, _material(APRON_COLOR), Vector3(0.0, -0.75, 0.0), "Apron")

	# Rings every 3 m and a centre mark, so movement reads against the floor.
	var line_mat: StandardMaterial3D = _material(LINE_COLOR)
	var ring_r: float = 3.0
	while ring_r < r - 0.5:
		_flat_ring(ring_r, 0.035, line_mat, "Line%d" % int(ring_r))
		ring_r += 3.0
	var mark: CylinderMesh = CylinderMesh.new()
	mark.top_radius = 0.25
	mark.bottom_radius = 0.25
	mark.height = 0.01
	_mesh(mark, line_mat, Vector3(0.0, 0.005, 0.0), "CentreMark")


func _flat_ring(radius: float, half_width: float, mat: Material, node_name: String) -> void:
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = radius - half_width
	ring.outer_radius = radius + half_width
	ring.rings = 96
	ring.ring_segments = 4
	var mi: MeshInstance3D = _mesh(ring, mat, Vector3(0.0, 0.004, 0.0), node_name)
	mi.scale = Vector3(1.0, 0.05, 1.0)


func _build_wall(r: float) -> void:
	# A low wall along the rules' wall line, its inner face at the radius.
	var wall: TorusMesh = TorusMesh.new()
	wall.inner_radius = r
	wall.outer_radius = r + 0.4
	wall.rings = 128
	wall.ring_segments = 12
	var mi: MeshInstance3D = _mesh(wall, _material(WALL_COLOR, 0.7, 0.15), Vector3(0.0, 0.3, 0.0), "Wall")
	mi.scale = Vector3(1.0, 1.5, 1.0)


func _build_pillars(r: float) -> void:
	var mat: StandardMaterial3D = _material(PILLAR_COLOR, 0.95)
	var cap_mat: StandardMaterial3D = _material(WALL_COLOR.darkened(0.2), 0.8)
	for i: int in pillar_count:
		var a: float = TAU * float(i) / float(pillar_count)
		var at: Vector3 = Vector3(sin(a), 0.0, cos(a)) * (r + pillar_offset)
		var shaft: CylinderMesh = CylinderMesh.new()
		shaft.top_radius = 0.32
		shaft.bottom_radius = 0.4
		shaft.height = pillar_height
		_mesh(shaft, mat, at + Vector3(0.0, pillar_height / 2.0, 0.0), "Pillar%d" % i)
		var cap: BoxMesh = BoxMesh.new()
		cap.size = Vector3(1.1, 0.25, 1.1)
		var cap_mi: MeshInstance3D = _mesh(cap, cap_mat, at + Vector3(0.0, pillar_height + 0.12, 0.0), "Cap%d" % i)
		cap_mi.rotation.y = a
	# Two warm lanterns by the side pillars.
	for side: float in [-1.0, 1.0]:
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.name = "Lantern%s" % ("L" if side < 0.0 else "R")
		lamp.light_color = Color(1.0, 0.55, 0.25)
		lamp.light_energy = 2.0
		lamp.omni_range = 9.0
		lamp.position = Vector3(side * (r + 0.6), 2.2, 0.0)
		add_child(lamp)


func _build_markers(r: float) -> void:
	var spots: Dictionary[String, Vector3] = {
		"Spawn0": Vector3(0.0, 0.0, -3.2),
		"Spawn1": Vector3(0.0, 0.0, 3.2),
		"Gate0": Vector3(0.0, 0.0, -(r + 3.0)),
		"Gate1": Vector3(0.0, 0.0, r + 3.0),
	}
	for key: String in spots:
		var m: Marker3D = Marker3D.new()
		m.name = key
		m.position = spots[key]
		add_child(m)
