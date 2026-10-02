extends GutTest
## The Moonlit Shrine as every match's arena (plan task 17.10): with the
## rules' wall at the shrine's 15 m, fighters and dropped weapons stay inside
## its parapet, and the match cameras, with a fighter backed against the
## wall, never pass through its props.

const SHRINE_SCENE := "res://arenas/moonlit_shrine/moonlit_shrine.tscn"
## The camera's clearance: no prop within this of the camera (its near
## plane is 0.1 m away, and a little more keeps a pillar from filling the view).
const CLEARANCE: float = 0.3

var def: ArenaDef


func before_each() -> void:
	def = ArenaScenes.def(ArenaScenes.MOONLIT_SHRINE)


func after_each() -> void:
	SimHelpers.dispose_all()


func test_a_default_match_is_fought_on_the_shrine() -> void:
	assert_eq(MatchConfig.DEFAULT_ARENA, ArenaScenes.MOONLIT_SHRINE)
	assert_eq(def.walkable_radius, SimConst.ARENA_RADIUS, "the rules' wall is the shrine's")
	assert_eq(ArenaScenes.scene_path(MatchConfig.DEFAULT_ARENA), SHRINE_SCENE)


func test_computer_matches_keep_fighters_and_dropped_weapons_inside_the_parapet() -> void:
	var furthest_body: float = 0.0
	var furthest_weapon: float = 0.0
	var dropped: int = 0
	for seed_value: int in [11, 12, 13]:
		var W: World = SimHelpers.track(World.new(FighterConfig.make(Moves.KATANA), FighterConfig.make(Moves.GREATSWORD), seed_value))
		var M: Match = Match.new(W)
		var brains: Array[AIBrain] = [
			AIBrain.new(W.fighters[0], AIBrain.DIFFICULTY[&"hard"], seed_value),
			AIBrain.new(W.fighters[1], AIBrain.DIFFICULTY[&"hard"], seed_value + 100),
		]
		for _i: int in 60 * 60 * 6:
			M.step([brains[0].think(), brains[1].think()])
			for e: Dictionary in W.drain_events():
				if e["t"] == &"disarm":
					dropped += 1
			for f: Fighter in W.fighters:
				furthest_body = maxf(furthest_body, JsMath.hypot(f.pos.x, f.pos.z) + SimConst.FIGHTER_RADIUS)
			for w: DroppedWeapon in W.weapons:
				furthest_weapon = maxf(furthest_weapon, JsMath.hypot(w.pos.x, w.pos.z))
			if M.phase == &"matchOver":
				break
		for b: AIBrain in brains:
			b.dispose()
	assert_lte(furthest_body, def.wall_inner_radius(), "no fighter's body passes the parapet's inner face")
	assert_gt(furthest_body, 10.0, "the fighters used the room")
	assert_gt(dropped, 0, "weapons were dropped")
	assert_lt(furthest_weapon, def.wall_inner_radius(), "dropped weapons stay inside the parapet")


## A physics space holding the shrine's props and the gates' rope barriers,
## one static body per mesh, named after it.
func _prop_space() -> PhysicsDirectSpaceState3D:
	var shrine: Node3D = (load(SHRINE_SCENE) as PackedScene).instantiate()
	add_child_autofree(shrine)
	var meshes: Array[Node] = shrine.find_children("*", "MeshInstance3D", true, false).filter(
		func(n: Node) -> bool: return n.get_parent().name == &"Props" or String(n.get_parent().name).begins_with("GateRope"))
	assert_gt(meshes.size(), 10, "the shrine has its props")
	for mi: Node in meshes:
		var body := StaticBody3D.new()
		body.name = mi.name
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces((mi as MeshInstance3D).mesh.get_faces())
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = (mi as MeshInstance3D).global_transform
		body.add_child(cs)
		add_child_autofree(body)
	await wait_physics_frames(2)
	return get_viewport().world_3d.direct_space_state


## Each camera position the sweep takes: the player backed against the wall
## at every degree, the opponent 2.5, 6 or 12 m away at bearings from straight
## in to 60 degrees either side. One path per (bearing, distance), in order
## round the wall.
func _paths(rig: CameraRig, watch: bool) -> Dictionary:
	var paths: Dictionary = {}
	var r: float = SimConst.ARENA_RADIUS - SimConst.FIGHTER_RADIUS
	for bearing: float in [-60.0, -30.0, 0.0, 30.0, 60.0]:
		for d: float in [2.5, 6.0, 12.0]:
			for sway: float in ([-1.0, 0.0, 1.0] if watch else [0.0]):
				var path: PackedVector3Array = PackedVector3Array()
				for deg: int in 360:
					var player: Vector3 = ShrineLayout.polar(deg, r)
					var inward: Vector3 = (-player).normalized().rotated(Vector3.UP, deg_to_rad(bearing))
					var opponent: Vector3 = player + inward * d
					var direction: Vector3 = Vector3(opponent.x - player.x, 0.0, opponent.z - player.z).normalized()
					var target: Dictionary
					if watch:
						var t: float = asin(sway) / rig.watch_sway_speed
						target = rig.watch_target(player, opponent, direction, t)
					else:
						target = rig.follow_target(player, opponent, direction)
					path.append(rig.clamp_to_arena(target["pos"]))
				paths["%s bearing %d, %s m%s" % ["watch" if watch else "follow", bearing, d, ", sway %d" % sway if watch else ""]] = path
	return paths


## The props each path's camera comes within CLEARANCE of or passes
## through, one line per path and prop: "path: prop at degrees".
func _hits(space: PhysicsDirectSpaceState3D, paths: Dictionary) -> Array[String]:
	var ball := SphereShape3D.new()
	ball.radius = CLEARANCE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ball
	var at: Dictionary[String, PackedInt32Array] = {}
	for key: String in paths:
		var path: PackedVector3Array = paths[key]
		for i: int in path.size():
			var names: Array[String] = []
			query.transform = Transform3D(Basis(), path[i])
			for hit: Dictionary in space.intersect_shape(query, 4):
				names.append(String((hit["collider"] as Node).name))
			var ray := PhysicsRayQueryParameters3D.create(path[i], path[(i + 1) % path.size()])
			ray.hit_back_faces = true
			var through: Dictionary = space.intersect_ray(ray)
			if not through.is_empty():
				names.append(String((through["collider"] as Node).name))
			for n: String in names:
				var k: String = "%s: %s" % [key, n]
				if not at.has(k):
					at[k] = PackedInt32Array()
				if not at[k].has(i):
					at[k].append(i)
	var out: Array[String] = []
	for k: String in at:
		out.append("%s at %s deg" % [k, at[k]])
	return out


func test_the_follow_camera_at_the_wall_never_passes_through_a_prop() -> void:
	var space: PhysicsDirectSpaceState3D = await _prop_space()
	var rig: CameraRig = autofree(CameraRig.new())
	rig.apply_arena(def.camera_max_radius, def.camera_far)
	var hits: Array[String] = _hits(space, _paths(rig, false))
	assert_eq(hits.size(), 0, "camera inside a prop:\n%s" % "\n".join(hits.slice(0, 40)))


func test_the_watch_camera_at_the_wall_never_passes_through_a_prop() -> void:
	var space: PhysicsDirectSpaceState3D = await _prop_space()
	var rig: CameraRig = autofree(CameraRig.new())
	rig.mode = CameraRig.Mode.WATCH
	rig.apply_arena(def.camera_max_radius, def.camera_far)
	var hits: Array[String] = _hits(space, _paths(rig, true))
	assert_eq(hits.size(), 0, "camera inside a prop:\n%s" % "\n".join(hits.slice(0, 40)))
