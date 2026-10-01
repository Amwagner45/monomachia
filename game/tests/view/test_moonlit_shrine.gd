extends GutTest
## The Moonlit Shrine's courtyard, built headless: the arena's own lights,
## environment and ink-wash pass, the markers the match reads, a floor at
## y = 0 under the spawns, a parapet and gate ropes outside the walkable
## circle with only flat pebbles inside it, and the chosen preset applied.

const SCENE := "res://arenas/moonlit_shrine/moonlit_shrine.tscn"

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


func test_its_environment_is_its_own_copy() -> void:
	var env: Environment = (arena.get_node("WorldEnvironment") as WorldEnvironment).environment
	var source: Environment = load("res://view/look/ink_night_environment.tres")
	assert_ne(env, source, "a copy, so presets don't edit the resource")
	assert_eq(env.background_color, source.background_color, "the night environment until the sky (17.6)")


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


func _min_radius(mi: MeshInstance3D) -> float:
	var best: float = INF
	for s: int in mi.mesh.get_surface_count():
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v: Vector3 in verts:
			var w: Vector3 = mi.global_transform * v
			best = minf(best, Vector2(w.x, w.z).length())
	return best


func test_nothing_but_flat_pebbles_is_built_inside_the_walkable_circle() -> void:
	var platform: Node = arena.get_node("Platform")
	var meshes: Array[Node] = platform.find_children("*", "MeshInstance3D", true, false)
	assert_gt(meshes.size(), 5, "the floor, the plinth, the props and the ropes")
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


# ------------------------------------------------------------------ presets

func test_the_saved_preset_is_applied_when_it_loads() -> void:
	_settings().graphics_preset_id = &"low"
	var low_shrine: MoonlitShrine = (load(SCENE) as PackedScene).instantiate()
	add_child_autofree(low_shrine)
	var ink := low_shrine.get_node("InkWash") as InkWashPass
	assert_eq(ink.quality, InkWashPass.Quality.OFF, "no ink-wash pass on Low")
	var parapet := low_shrine.get_node("Platform/Props/Parapet") as MeshInstance3D
	assert_false(ToonMaterials.is_outlined(parapet.material_override), "no prop outlines on Low")


func test_every_preset_applies_to_the_courtyard() -> void:
	for id: StringName in GraphicsPreset.IDS:
		var preset: GraphicsPreset = GraphicsPreset.load_id(id)
		GraphicsApplier.apply_to_tree(preset, arena)
		var parapet := arena.get_node("Platform/Props/Parapet") as MeshInstance3D
		assert_eq(ToonMaterials.is_outlined(parapet.material_override), preset.outline_props, "%s: parapet outline" % id)
		var key := arena.get_node("Lights/MoonKey") as DirectionalLight3D
		assert_eq(key.directional_shadow_max_distance, preset.shadow_max_distance, "%s: moon shadows" % id)
		assert_eq((arena.get_node("InkWash") as InkWashPass).quality, preset.post_quality, "%s: ink wash" % id)
		var env: Environment = (arena.get_node("WorldEnvironment") as WorldEnvironment).environment
		assert_eq(env.fog_enabled, preset.fog_enabled, "%s: fog" % id)
