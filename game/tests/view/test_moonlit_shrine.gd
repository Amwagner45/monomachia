extends GutTest
## The Moonlit Shrine, built headless: the arena's own lights, ink-wash pass
## and night sky, with its fog and the moon ahead of player one where the
## layout puts it; the markers the match reads, a floor at y = 0 under the
## spawns, a parapet, gate ropes and props outside the walkable circle with
## only flat pebbles inside it, the torii on the gate landings, the lanterns'
## lights, halos and flicker, bought art in place of a procedural prop, the
## ledge under the props, the rock under the rim left out per camera by the
## cameras above the courtyard, the floating rocks bobbing, and the chosen
## preset applied.

const SCENE := "res://arenas/moonlit_shrine/moonlit_shrine.tscn"
const SKY_SHADER: Shader = preload("res://shaders/sky_moonlit.gdshader")

var arena: MoonlitShrine
var _services: Node
var _saved_preset: StringName


func before_all() -> void:
	_services = get_tree().root.get_node("GameServices")
	arena = (load(SCENE) as PackedScene).instantiate()
	add_child(arena)


func before_each() -> void:
	_saved_preset = _settings().graphics_preset_id


## Puts back the saved preset, and the shared arena in it.
func after_each() -> void:
	_settings().graphics_preset_id = _saved_preset
	GraphicsApplier.apply_to_tree(_services.call("graphics_preset"), arena)


func after_all() -> void:
	arena.free()


func _settings() -> GameSettings:
	return _services.get("settings") as GameSettings


func test_it_carries_its_arena_data_and_layout() -> void:
	assert_eq(arena.def, ArenaScenes.def(ArenaScenes.MOONLIT_SHRINE), "the shrine's ArenaDef, which the camera reads")
	assert_eq(arena.def.scene_path, SCENE)
	assert_not_null(arena.layout)


func test_its_markers_match_the_arena_data() -> void:
	for side: int in 2:
		var spawn := arena.get_node("Spawn%d" % side) as Marker3D
		var gate := arena.get_node("Gate%d" % side) as Marker3D
		assert_true(spawn.transform.is_equal_approx(arena.def.spawn_point(side)), "Spawn%d" % side)
		assert_true(gate.transform.is_equal_approx(arena.def.gate_anchor(side)), "Gate%d" % side)


func _environment(shrine: MoonlitShrine) -> Environment:
	return (shrine.get_node("WorldEnvironment") as WorldEnvironment).environment


## A parameter of shrine's sky, once its shader is known to declare it: a
## misspelt name would set nothing, so the test reads only real uniforms.
func _sky_param(shrine: MoonlitShrine, param: StringName) -> Variant:
	var sky := _environment(shrine).sky.sky_material as ShaderMaterial
	var names: Array = sky.shader.get_shader_uniform_list().map(func(u: Dictionary) -> String: return u["name"])
	assert_has(names, String(param), "%s is a uniform of the sky" % param)
	return sky.get_shader_parameter(param)


func test_its_environment_is_its_own_copy_of_the_night_sky() -> void:
	assert_not_null(arena.def.environment, "the shrine's data brings its sky")
	var env: Environment = _environment(arena)
	assert_ne(env, arena.def.environment, "a copy, so presets don't edit the resource")
	assert_eq(env.background_mode, Environment.BG_SKY)
	var sky := env.sky.sky_material as ShaderMaterial
	assert_eq(sky.shader, SKY_SHADER)
	assert_ne(sky, arena.def.environment.sky.sky_material, "its own sky, so the moon set on it leaves the resource alone")
	assert_eq(_sky_param(arena, LookNoise.PARAM), LookNoise.texture(), "the sky fetches the look's noise")
	assert_eq(_sky_param(arena, &"horizon_color"), env.fog_light_color, "the depth fog fades into the sky's horizon")


## A sky that isn't a shader (bought art, say) comes through as it is.
func test_a_sky_that_isnt_a_shader_is_left_as_it_is() -> void:
	var def := arena.def.duplicate() as ArenaDef
	var panorama := PanoramaSkyMaterial.new()
	def.environment = Environment.new()
	def.environment.background_mode = Environment.BG_SKY
	def.environment.sky = Sky.new()
	def.environment.sky.sky_material = panorama
	var shrine: MoonlitShrine = (load(SCENE) as PackedScene).instantiate()
	shrine.def = def
	add_child_autofree(shrine)
	assert_true(_environment(shrine).sky.sky_material is PanoramaSkyMaterial)


## The shrine's own fog, before a preset turns any of it off.
func test_fog_and_height_fog_are_set() -> void:
	var env: Environment = arena.def.environment
	assert_true(env.fog_enabled, "depth fog")
	assert_gt(env.fog_depth_begin, arena.def.camera_max_radius + arena.def.floor_radius, "which starts past the courtyard")
	assert_gt(env.fog_height_density, 0.0, "height fog")
	assert_lt(env.fog_height, ShrinePlatform.LEDGE_Y, "which gathers under the ledge, leaving the courtyard clear")


## Player one starts at -Z facing +Z, so the moon hangs in their first view.
func test_the_moon_rises_ahead_of_player_one() -> void:
	var toward_moon: Vector3 = arena.layout.moon_direction.normalized()
	assert_almost_eq(_sky_param(arena, &"moon_direction"), toward_moon, Vector3.ONE * 1e-5, "the sky's moon is where the layout puts it")
	assert_gt(toward_moon.y, 0.0, "above the horizon")
	var rig: CameraRig = autofree(CameraRig.new())
	var me: Vector3 = arena.def.spawn_point(0).origin
	var them: Vector3 = arena.def.spawn_point(1).origin
	var view: Dictionary = rig.follow_target(me, them, (them - me).normalized())
	var cam: Camera3D = _camera_at(view["pos"])
	cam.fov = rig.base_fov
	cam.far = arena.def.camera_far
	cam.look_at(view["look"])
	assert_true(cam.is_position_in_frustum(cam.global_position + toward_moon * 1000.0), "in player one's first view")


## The moon is data: a layout with the moon elsewhere moves the sky's moon
## and the rim light with it, and leaves other shrines' skies alone.
func test_the_sky_and_the_rim_light_take_the_moon_from_the_layout() -> void:
	var layout := arena.layout.duplicate() as ShrineLayout
	layout.moon_direction = Vector3(-2.0, 1.0, 0.5)
	var shrine: MoonlitShrine = (load(SCENE) as PackedScene).instantiate()
	shrine.layout = layout
	add_child_autofree(shrine)
	var toward_moon: Vector3 = layout.moon_direction.normalized()
	assert_almost_eq(_sky_param(shrine, &"moon_direction"), toward_moon, Vector3.ONE * 1e-5, "the sky's moon")
	var rim := shrine.get_node("Lights/MoonRim") as DirectionalLight3D
	assert_almost_eq(rim.global_basis.z, toward_moon, Vector3.ONE * 1e-4, "the rim light")
	assert_almost_eq(_sky_param(arena, &"moon_direction"), arena.layout.moon_direction.normalized(), Vector3.ONE * 1e-5, "the first shrine's moon stays")


func test_the_moon_casts_the_shadows_and_the_rim_light_touches_fighters_only() -> void:
	var key := arena.get_node("Lights/MoonKey") as DirectionalLight3D
	assert_true(key.is_in_group(GraphicsApplier.GROUP_SHADOW_LIGHT), "the preset sets its shadows")
	var rim := arena.get_node("Lights/MoonRim") as DirectionalLight3D
	assert_eq(rim.light_cull_mask, LookPalette.FIGHTER_LAYER)
	assert_false(rim.shadow_enabled)
	var toward_moon: Vector3 = arena.layout.moon_direction.normalized()
	assert_almost_eq(rim.global_basis.z, toward_moon, Vector3.ONE * 1e-4, "the rim light shines from the moon")


func test_it_brings_exactly_one_ink_wash_pass() -> void:
	assert_true(arena.get_node("InkWash") is InkWashPass)
	assert_eq(arena.find_children("*", "InkWashPass", true, false).size(), 1)


# ------------------------------------------------------------------ the platform

func test_the_floor_lies_at_zero_under_both_spawns_on_the_ground_layer() -> void:
	var floor_mi := arena.get_node("Platform/Floor") as MeshInstance3D
	var aabb: AABB = floor_mi.get_aabb()
	assert_almost_eq(aabb.end.y, 0.0, 0.001, "floor at y = 0")
	assert_almost_eq(aabb.position.y, 0.0, 0.001, "and flat")
	assert_almost_eq(aabb.end.x, arena.def.floor_radius, 0.01, "out to the floor's edge")
	for side: int in 2:
		var p: Vector3 = arena.def.spawn_point(side).origin
		assert_eq(p.y, 0.0, "spawn %d at floor height" % side)
		assert_lt(Vector2(p.x, p.z).length(), arena.def.floor_radius, "spawn %d on the paving" % side)
	assert_eq(floor_mi.layers, LookPalette.GROUND_LAYER, "lantern lights skip it")
	assert_not_null(arena.get_node_or_null("Platform/Plinth"), "the courtyard's stone edge")


func test_parapet_posts_stand_outside_the_walkable_circle() -> void:
	var posts: PackedVector3Array = ShrinePlatform.post_positions(arena.layout, arena.def)
	assert_gt(posts.size(), 40)
	assert_lt(posts.size(), arena.layout.post_count, "the gates open the parapet")
	for p: Vector3 in posts:
		var inner: float = Vector2(p.x, p.z).length() - ShrinePlatform.POST_HALF * ShrinePlatform.END_POST_WIDEN
		assert_gte(inner, arena.def.walkable_radius, "post at %s" % p)


## Every vertex of mi, in world space.
func _world_vertices(mi: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for s: int in mi.mesh.get_surface_count():
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v: Vector3 in verts:
			out.append(mi.global_transform * v)
	return out


func _min_radius(mi: MeshInstance3D) -> float:
	var best: float = INF
	for w: Vector3 in _world_vertices(mi):
		best = minf(best, Vector2(w.x, w.z).length())
	return best


func test_nothing_but_flat_pebbles_is_built_inside_the_walkable_circle() -> void:
	var platform: Node = arena.get_node("Platform")
	var meshes: Array[Node] = platform.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 10, "the floor, the plinth, the props and the ropes")
	for node: Node in meshes:
		if node.name in [&"Floor", &"Pebbles"]:
			continue
		assert_gte(_min_radius(node as MeshInstance3D), arena.def.walkable_radius - 0.001, "%s stays outside the walkable circle" % node.name)
	var pebbles := platform.get_node("Props/Pebbles") as MeshInstance3D
	assert_lt(pebbles.get_aabb().end.y, 0.12, "pebbles are flat enough to walk over")
	assert_gte(_min_radius(pebbles), arena.def.walkable_radius - 0.6, "along the foot of the parapet")


func test_each_gate_stands_on_a_landing_level_with_the_floor() -> void:
	var landings := arena.get_node("Platform/Props/Landing") as MeshInstance3D
	var aabb: AABB = landings.get_aabb()
	assert_almost_eq(aabb.end.y, 0.0, 0.02, "landings come up to the floor")
	for side: int in 2:
		var gate: Vector3 = arena.def.gate_anchor(side).origin
		assert_true(aabb.grow(0.01).has_point(gate + Vector3(0.0, -0.05, 0.0)), "a landing under gate %d" % side)


func test_gate_ropes_close_the_gate_openings_outside_the_walkable_circle() -> void:
	for side: int in 2:
		var rope: Node = arena.get_node("Platform/GateRope%d" % side)
		var gate: Vector3 = arena.def.gate_anchor(side).origin
		var meshes: Array[Node] = rope.find_children("*", "MeshInstance3D", true, false)
		assert_gt(meshes.size(), 0, "rope %d has meshes" % side)
		for node: Node in meshes:
			var mi := node as MeshInstance3D
			assert_gte(_min_radius(mi), arena.def.walkable_radius, "rope %d outside the walkable circle" % side)
			var centre: Vector3 = mi.global_transform * mi.get_aabb().get_center()
			assert_gt(centre.z * gate.z, 0.0, "rope %d at its own gate's end" % side)
			assert_lt(absf(centre.x), 1.0, "rope %d across the opening" % side)


# ------------------------------------------------------------------ the props

## Every vertex of mi (world space) within radius of point, across the floor.
func _vertices_near(mi: MeshInstance3D, point: Vector3, radius: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for w: Vector3 in _world_vertices(mi):
		if Vector2(w.x - point.x, w.z - point.z).length() < radius:
			out.append(w)
	return out


func test_a_torii_stands_on_each_gate_landing() -> void:
	var lacquer := arena.get_node("Platform/Props/Lacquer") as MeshInstance3D
	for side: int in 2:
		var gate: Transform3D = arena.def.gate_anchor(side)
		for s: float in [-1.0, 1.0]:
			var foot: Vector3 = gate * Vector3(s * arena.layout.torii_span * 0.5, 0.0, 0.0)
			var verts: PackedVector3Array = _vertices_near(lacquer, foot, 0.5)
			assert_gt(verts.size(), 0, "gate %d has a post at %+d" % [side, s])
			var low: float = INF
			var high: float = -INF
			for v: Vector3 in verts:
				low = minf(low, v.y)
				high = maxf(high, v.y)
			assert_almost_eq(low, 0.0, 0.01, "gate %d post %+d stands on the landing" % [side, s])
			assert_gt(high, arena.layout.torii_height, "gate %d post %+d at the torii's height" % [side, s])


func _lantern_lights(shrine: MoonlitShrine) -> Array[Node]:
	return shrine.get_node("Platform/LanternLights").get_children()


func test_every_lantern_has_a_light_that_lights_fighters_and_skips_the_ground() -> void:
	var lights: Array[Node] = _lantern_lights(arena)
	assert_eq(lights.size(), arena.layout.lantern_angles.size(), "one light per lantern")
	for i: int in lights.size():
		var light := lights[i] as OmniLight3D
		var spot: Vector3 = ShrineLayout.polar(arena.layout.lantern_angles[i], arena.layout.lantern_radius)
		assert_lt(Vector2(light.position.x - spot.x, light.position.z - spot.z).length(), 0.25, "light %d in its lantern" % i)
		assert_between(light.position.y, 1.5, 2.5, "light %d at the lantern's fire" % i)
		assert_eq(light.light_cull_mask & LookPalette.GROUND_LAYER, 0, "light %d skips the ground" % i)
		assert_ne(light.light_cull_mask & LookPalette.FIGHTER_LAYER, 0, "light %d lights fighters" % i)
		assert_true(light.is_in_group(GraphicsApplier.GROUP_MINOR_LIGHT), "the preset turns light %d on or off" % i)
		assert_false(light.shadow_enabled, "light %d casts no shadow" % i)


## Where the halos sit is for the shots: the headless renderer keeps no
## MultiMesh transforms to read back.
func test_every_lantern_has_a_halo() -> void:
	var halos := arena.get_node("Platform/LanternHalos") as MultiMeshInstance3D
	assert_eq(halos.multimesh.instance_count, arena.layout.lantern_angles.size())
	assert_eq(halos.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_lantern_lights_flicker_round_their_brightness() -> void:
	var light := _lantern_lights(arena)[0] as OmniLight3D
	var energies: Dictionary[float, bool] = {}
	for frame: int in 12:
		simulate(arena, 1, 0.05)
		energies[snappedf(light.light_energy, 0.001)] = true
		assert_between(light.light_energy, ShrinePlatform.LANTERN_ENERGY * 0.8, ShrinePlatform.LANTERN_ENERGY * 1.2)
	assert_gt(energies.size(), 6, "it flickers")


## A stand-in for a bought model: an empty Node3D scene.
func _bought_art() -> PackedScene:
	var scene := PackedScene.new()
	var model := Node3D.new()
	model.name = "BoughtArt"
	scene.pack(model)
	model.free()
	return scene


## A shrine built with the shared layout, but with bought art for kinds.
func _shrine_with_art(kinds: Array[StringName]) -> MoonlitShrine:
	var layout := arena.layout.duplicate() as ShrineLayout
	var art := _bought_art()
	# A dictionary of its own: a shallow duplicate shares the cached layout's.
	var art_by_kind: Dictionary[StringName, PackedScene] = {}
	for kind: StringName in kinds:
		art_by_kind[kind] = art
	layout.prop_scenes = art_by_kind
	var shrine: MoonlitShrine = (load(SCENE) as PackedScene).instantiate()
	shrine.layout = layout
	add_child_autofree(shrine)
	return shrine


func _props_aabb(shrine: MoonlitShrine, kit_name: String) -> AABB:
	return (shrine.get_node("Platform/Props/" + kit_name) as MeshInstance3D).get_aabb()


func test_a_scene_in_prop_scenes_replaces_the_procedural_lantern_at_the_same_spots() -> void:
	var shrine: MoonlitShrine = _shrine_with_art([&"lantern"])
	var layout: ShrineLayout = shrine.layout
	var placed: Array[Node] = shrine.get_node("Platform/Props").find_children("Lantern*", "Node3D", false, false)
	assert_eq(placed.size(), layout.lantern_angles.size(), "one bought lantern per spot")
	for i: int in placed.size():
		var spot: Vector3 = ShrineLayout.polar(layout.lantern_angles[i], layout.lantern_radius)
		var at: Vector3 = (placed[i] as Node3D).position
		assert_almost_eq(Vector2(at.x, at.z), Vector2(spot.x, spot.z), Vector2.ONE * 0.01, "bought lantern %d on its spot" % i)
	assert_null(shrine.get_node_or_null("Platform/Props/Glow"), "no procedural lantern's lit paper")
	assert_eq(_lantern_lights(shrine).size(), layout.lantern_angles.size(), "the bought lanterns still light")
	for kit_name: String in ["Bark", "Pine", "StoneDark"]:
		assert_eq(_props_aabb(shrine, kit_name), _props_aabb(arena, kit_name), "%s as it was without the bought lanterns" % kit_name)


func test_every_prop_kind_can_be_swapped_for_bought_art() -> void:
	var shrine: MoonlitShrine = _shrine_with_art(ShrineLayout.PROP_KINDS)
	var layout: ShrineLayout = shrine.layout
	var pines: int = 0
	for t: Vector4 in layout.trees:
		pines += 1 if t.w < 0.5 else 0
	var expected: Dictionary[String, int] = {
		"Lantern": layout.lantern_angles.size(), "Torii": 2, "Pillar": layout.pillars.size(),
		"Pine": pines, "DeadTree": layout.trees.size() - pines,
	}
	var props: Node = shrine.get_node("Platform/Props")
	for kind: String in expected:
		var placed: int = 0
		for child: Node in props.get_children():
			if child.name.begins_with(kind) and child.name.trim_prefix(kind).is_valid_int():
				placed += 1
		assert_eq(placed, expected[kind], "bought %s in every spot" % kind)
	for kit_name: String in ["Stone", "Lacquer", "BlackLacquer", "Bark", "Pine", "Glow"]:
		assert_null(props.get_node_or_null(kit_name), "no procedural %s left" % kit_name)
	var rocks: Array[Node] = shrine.get_node("Underside/FloatingRocks").get_children()
	assert_eq(rocks.size(), layout.floating_rocks.size(), "a bought floating rock in every spot")
	for rock: Node in rocks:
		assert_null(rock.get_node_or_null("Rock"), "%s is the bought one" % rock.name)


func test_bought_art_under_an_unknown_kind_is_reported() -> void:
	var shrine: MoonlitShrine = _shrine_with_art([&"lanturn"])
	assert_push_error("lanturn")
	assert_not_null(shrine.get_node_or_null("Platform/Props/Glow"), "the lanterns are built as usual")


# ------------------------------------------------------------------ the underside

## How far the ledge reaches at angle_deg: its farthest vertex within 4
## degrees of it.
func _ledge_reach(ledge: MeshInstance3D, angle_deg: float) -> float:
	var best: float = 0.0
	for w: Vector3 in _world_vertices(ledge):
		if absf(wrapf(rad_to_deg(atan2(w.x, w.z)) - angle_deg, -180.0, 180.0)) < 4.0:
			best = maxf(best, Vector2(w.x, w.z).length())
	return best


func test_the_ledge_on_the_ground_layer_reaches_past_every_prop_on_it() -> void:
	var ledge := arena.get_node("Underside/Ledge") as MeshInstance3D
	assert_eq(ledge.layers, LookPalette.GROUND_LAYER, "lantern lights skip it")
	var spots: Array[Vector2] = []
	for angle: float in arena.layout.lantern_angles:
		spots.append(Vector2(angle, arena.layout.lantern_radius))
	for p: Vector4 in arena.layout.pillars:
		spots.append(Vector2(p.x, p.y))
	for t: Vector4 in arena.layout.trees:
		spots.append(Vector2(t.x, t.y))
	for spot: Vector2 in spots:
		assert_gt(_ledge_reach(ledge, spot.x), spot.y + 0.6, "the ledge holds the prop at %.0f degrees, %.1f m" % [spot.x, spot.y])
	var aabb: AABB = ledge.get_aabb()
	assert_lt(aabb.position.y, ShrinePlatform.LEDGE_Y, "it droops toward its rim")
	assert_lt(aabb.end.y, 0.0, "under the floor's height")


func test_the_rock_under_the_rim_hangs_on_its_own_layer() -> void:
	var below: Array[Node] = arena.get_node("Underside/BelowDeck").find_children("*", "GeometryInstance3D", true, false)
	var names: Array[StringName] = []
	for node: Node in below:
		names.append(node.name)
		assert_eq((node as GeometryInstance3D).layers, LookPalette.BELOW_DECK_LAYER, "%s on the below-deck layer only" % node.name)
	for part: StringName in [&"Crag", &"Roots", &"Chains"]:
		assert_has(names, part)
	var crag: AABB = (arena.get_node("Underside/BelowDeck/Crag") as MeshInstance3D).get_aabb()
	assert_lt(crag.end.y, ShrinePlatform.LEDGE_Y, "the crag hangs under the ledge")
	assert_gt(crag.size.y, arena.layout.crag_depth * 0.9, "down to its tip")


## The ledge hides the crag from every camera above it and inside its rim:
## the crag never reaches out past the rim, and the cameras' limit stays
## inside the ledge's least reach.
## (Keys in quarter degrees: the lattice's columns sit every 3.75 degrees.)
func test_the_crag_stays_inside_the_ledges_rim() -> void:
	assert_lt(arena.def.camera_max_radius, arena.layout.crag_radius, "cameras stay over the ledge")
	var ledge := arena.get_node("Underside/Ledge") as MeshInstance3D
	var rim: Dictionary[int, float] = {}
	for w: Vector3 in _world_vertices(ledge):
		var key: int = roundi(rad_to_deg(atan2(w.x, w.z)) * 4.0)
		rim[key] = maxf(rim.get(key, 0.0), Vector2(w.x, w.z).length())
	var outside: int = 0
	var worst: float = 0.0
	for w: Vector3 in _world_vertices(arena.get_node("Underside/BelowDeck/Crag") as MeshInstance3D):
		var key: int = roundi(rad_to_deg(atan2(w.x, w.z)) * 4.0)
		var past: float = Vector2(w.x, w.z).length() - rim.get(key, INF)
		if past > 0.001:
			outside += 1
			worst = maxf(worst, past)
	assert_eq(outside, 0, "crag points past the rim at their angle (worst %.2f m)" % worst)


func _camera_at(pos: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	add_child_autofree(cam)
	cam.global_position = pos
	return cam


func _draws_below_deck(cam: Camera3D) -> bool:
	return cam.cull_mask & LookPalette.BELOW_DECK_LAYER != 0


func test_the_fight_and_menu_cameras_leave_out_the_rock_under_the_rim() -> void:
	var rig: CameraRig = autofree(CameraRig.new())
	rig.apply_arena(arena.def.camera_max_radius, arena.def.camera_far)
	# The rig clamps the fight cameras to its limit, but not the menu's orbit.
	var spots: Array[Vector3] = [rig.menu_target(0.0)["pos"], rig.menu_target(10.0)["pos"]]
	for side: int in 2:
		var me: Vector3 = arena.def.spawn_point(side).origin
		var them: Vector3 = arena.def.spawn_point(1 - side).origin
		# At the spawns, and backed against opposite walls, where the cameras
		# go furthest out and highest.
		var at_wall: Vector3 = me.normalized() * (arena.def.walkable_radius - 0.5)
		for pair: Array in [[me, them], [at_wall, -at_wall]]:
			var a: Vector3 = pair[0]
			var b: Vector3 = pair[1]
			var dir: Vector3 = (b - a).normalized()
			spots.append(rig.clamp_to_arena(rig.follow_target(a, b, dir)["pos"]))
			spots.append(rig.clamp_to_arena(rig.watch_target(a, b, dir, 0.0)["pos"]))
	for pos: Vector3 in spots:
		var cam: Camera3D = _camera_at(pos)
		arena.cull_below_deck(cam)
		assert_false(_draws_below_deck(cam), "a camera at %s leaves it out" % cam.global_position)


func test_cameras_beyond_or_below_the_courtyard_draw_the_rock_under_the_rim() -> void:
	var a: float = deg_to_rad(228.0)
	var establishing := Vector3(sin(a) * 58.0, -5.0, cos(a) * 58.0)
	for pos: Vector3 in [establishing, Vector3(-12.0, 90.0, 0.0), Vector3(0.0, -2.0, 10.0), Vector3(30.0, 3.0, 0.0)]:
		var cam: Camera3D = _camera_at(pos)
		cam.cull_mask &= ~LookPalette.BELOW_DECK_LAYER
		arena.cull_below_deck(cam)
		assert_true(_draws_below_deck(cam), "a camera at %s draws it" % pos)


func test_each_camera_is_decided_on_its_own() -> void:
	var fight: Camera3D = _camera_at(Vector3(0.0, 2.0, -8.0))
	var far: Camera3D = _camera_at(Vector3(0.0, -5.0, 58.0))
	far.cull_mask &= ~LookPalette.BELOW_DECK_LAYER
	arena.cull_below_deck(fight)
	arena.cull_below_deck(far)
	assert_false(_draws_below_deck(fight))
	assert_true(_draws_below_deck(far))
	assert_eq(fight.cull_mask | LookPalette.BELOW_DECK_LAYER, far.cull_mask, "no other layer changes")


func test_each_frame_the_arena_decides_for_its_viewports_camera() -> void:
	var cam: Camera3D = _camera_at(Vector3(0.0, -5.0, 58.0))
	cam.make_current()
	cam.cull_mask &= ~LookPalette.BELOW_DECK_LAYER
	simulate(arena, 1, 0.016)
	assert_true(_draws_below_deck(cam), "from out beyond the edge")
	cam.global_position = Vector3(0.0, 2.0, -8.0)
	simulate(arena, 1, 0.016)
	assert_false(_draws_below_deck(cam), "from the courtyard")


func test_floating_rocks_bob_over_their_spots() -> void:
	var rocks: Array[Node] = arena.get_node("Underside/FloatingRocks").get_children()
	assert_eq(rocks.size(), arena.layout.floating_rocks.size())
	var start: Array[float] = []
	for rock: Node in rocks:
		start.append((rock as Node3D).position.y)
	simulate(arena, 30, 0.1)
	var moved: bool = false
	for i: int in rocks.size():
		var f: Vector4 = arena.layout.floating_rocks[i]
		var home: Vector3 = ShrineLayout.polar(f.x, f.y, f.z)
		var at: Vector3 = (rocks[i] as Node3D).position
		assert_almost_eq(Vector2(at.x, at.z), Vector2(home.x, home.z), Vector2.ONE * 0.001, "rock %d stays over its spot" % i)
		assert_between(at.y, home.y - ShrineUnderside.BOB_HEIGHT - 0.001, home.y + ShrineUnderside.BOB_HEIGHT + 0.001, "rock %d bobs gently" % i)
		moved = moved or not is_equal_approx(at.y, start[i])
	assert_true(moved, "they bob")


# ------------------------------------------------------------------ presets

func test_the_saved_preset_is_applied_when_it_loads() -> void:
	_settings().graphics_preset_id = &"low"
	var low_shrine: MoonlitShrine = (load(SCENE) as PackedScene).instantiate()
	add_child_autofree(low_shrine)
	var ink := low_shrine.get_node("InkWash") as InkWashPass
	assert_eq(ink.quality, InkWashPass.Quality.OFF, "no ink-wash pass on Low")
	var parapet := low_shrine.get_node("Platform/Props/Parapet") as MeshInstance3D
	assert_false(ToonMaterials.is_outlined(parapet.material_override), "no prop outlines on Low")


func test_every_preset_applies_to_the_courtyard_and_its_props() -> void:
	var outlined: Array[String] = ["Parapet", "Landing", "StoneDark", "Rope", "Stone", "Lacquer", "BlackLacquer", "Bark", "Pine"]
	for id: StringName in GraphicsPreset.IDS:
		var preset: GraphicsPreset = GraphicsPreset.load_id(id)
		GraphicsApplier.apply_to_tree(preset, arena)
		for kit_name: String in outlined:
			var mi := arena.get_node("Platform/Props/" + kit_name) as MeshInstance3D
			assert_eq(ToonMaterials.is_outlined(mi.material_override), preset.outline_props, "%s: %s outline" % [id, kit_name])
		for kit_name: String in ["Pebbles", "Paper"]:
			var mi := arena.get_node("Platform/Props/" + kit_name) as MeshInstance3D
			assert_false(ToonMaterials.is_outlined(mi.material_override), "%s: %s never outlined" % [id, kit_name])
		for light: Node in _lantern_lights(arena):
			assert_eq((light as Light3D).visible, preset.minor_lights, "%s: lantern lights" % id)
		for part: String in ["Roots", "Chains"]:
			var geo := arena.get_node("Underside/BelowDeck/" + part) as GeometryInstance3D
			assert_eq(ToonMaterials.is_outlined(geo.material_override), preset.outline_props, "%s: %s outline" % [id, part])
		for rock: String in ["Ledge", "BelowDeck/Crag"]:
			var geo := arena.get_node("Underside/" + rock) as GeometryInstance3D
			assert_false(ToonMaterials.is_outlined(geo.material_override), "%s: %s never outlined" % [id, rock])
		var key := arena.get_node("Lights/MoonKey") as DirectionalLight3D
		assert_eq(key.directional_shadow_max_distance, preset.shadow_max_distance, "%s: moon shadows" % id)
		assert_eq((arena.get_node("InkWash") as InkWashPass).quality, preset.post_quality, "%s: ink wash" % id)
		var env: Environment = _environment(arena)
		assert_eq(env.fog_enabled, preset.fog_enabled, "%s: fog" % id)
		assert_eq(env.fog_height_density > 0.0, preset.height_fog, "%s: height fog" % id)
