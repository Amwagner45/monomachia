class_name AnimTile
extends PanelContainer
## One live tile of the Studio's gallery (docs/specs/animation-studio.md,
## Gallery): a small viewport with its own world, a fighter holding the
## entry's weapon, and the entry's animation looping on it; under it the
## animation's name, its id and a chip for each badge it has. Click it to open
## the entry (`opened`).
##
## What it plays is what the game plays. The entry's chain (`clips`) when
## every clip is there; without the packs the entry's fallbacks, the CC0
## clips the game plays instead: one per part of a state or ultimate, and a
## move's one fallback stretched over the whole move (so one loop of the tile
## takes the move's frames at 60 per second, as the game's attack_clip()
## spreads it). An entry with nothing to play (the rebound, or an Iglesias clip
## without the packs and a fallback) shows the fighter's idle, held still.
##
## Only a tile on screen plays: the tile checks its rect against its nearest
## ScrollContainer's every frame (`is_on_screen()`), and when that changes
## calls `set_playing()`, which also switches the viewport's rendering off, so
## a gallery of a hundred tiles costs what it shows. A tile out of any scroll
## container counts as on screen while it's visible in the tree.
##
## The fighter is built lazily: `setup()` only stores the entry and sets the
## caption and chips, and the fighter (its libraries, weapon and poser) is built
## when the tile first plays, which is when it first scrolls into view (or
## `ensure_built()` is called), so opening a gallery of 100+ tiles builds only
## the ones on screen.

## The tile was clicked: open `entry` in the editor.
signal opened(entry: StudioCatalogue.Entry)

## The tile's viewport is this many pixels square.
const VIEW_SIZE: int = 256
## The weapon of the ultimates (the weapon whose moveset has them).
const ULT_WEAPONS: Dictionary[StringName, StringName] = {
	&"moonsplitter_vertical": &"katana",
	&"moonsplitter_horizontal": &"katana",
	&"impaler": &"greatsword",
	&"tempest": &"daggers",
}
## The badge chips' colours, by badge.
const CHIP_COLORS: Dictionary[StringName, Color] = {
	&"fallback": Color(0.78, 0.55, 0.2),
	&"provisional": Color(0.7, 0.62, 0.25),
	&"corrective": Color(0.3, 0.6, 0.75),
	&"unsaved": Color(0.75, 0.35, 0.35),
	&"balance": Color(0.55, 0.45, 0.78),
}

## The fighter on the tile, or null before it is built.
var model: FighterModel = null
## The entry the tile shows.
var entry: StudioCatalogue.Entry = null
## &"hunter" or &"rogue".
var fighter_id: StringName = &"hunter"
## Where the loop is, in seconds into the clip (or the chain).
var time: float = 0.0
## How long one loop is (s); 0 for a still.
var duration: float = 0.0
## How much of the clip passes per second of real time: the entry's speed, or
## what stretches a move's fallback over the move.
var playback_rate: float = 1.0

@onready var viewport: SubViewport = %Viewport
@onready var name_label: Label = %NameLabel
@onready var id_label: Label = %IdLabel
@onready var _badges: HFlowContainer = %Badges

var _poser: ClipPoser = null
## Whether the tile plays: false until it is first on screen.
var _playing: bool = false
var _on_screen: bool = false
var _scroll: ScrollContainer = null
var _stage_built: bool = false
## Set by _chain() when it chose a move's fallback, which plays stretched over
## the move.
var _stretched: bool = false


func _ready() -> void:
	viewport.size = Vector2i(VIEW_SIZE, VIEW_SIZE)
	_build_stage()
	_show_caption()
	_sync()


func _exit_tree() -> void:
	_scroll = null


## Shows `p_entry` on fighter `p_fighter_id` (&"hunter" or &"rogue"). Cheap: the
## fighter is built when the tile first plays (see the class comment). Calling
## it again drops the fighter, and a tile that is playing builds the new one
## at once (the gallery's body switch).
func setup(p_entry: StudioCatalogue.Entry, p_fighter_id: StringName) -> void:
	entry = p_entry
	fighter_id = p_fighter_id
	_drop_fighter()
	if is_node_ready():
		_show_caption()
		_sync()


## Builds the fighter now if it isn't built (the tile has an entry and is
## ready), whether or not the tile is on screen.
func ensure_built() -> void:
	if entry != null and model == null and is_node_ready():
		_build()


## The weapon the tile's fighter holds for `e`: a move's own; a state's when its
## id ends in a weapon (idle_katana, guard_daggers); an ultimate's; none (&"")
## for bare hands, which is the fists' and every other state's.
static func weapon_for(e: StudioCatalogue.Entry) -> StringName:
	var wid: StringName = &""
	match e.kind:
		StudioCatalogue.KIND_MOVE:
			wid = e.group
		StudioCatalogue.KIND_ULT:
			wid = ULT_WEAPONS.get(e.id, &"")
		StudioCatalogue.KIND_STATE:
			var s: String = String(e.id)
			wid = StringName(s.substr(s.find("_") + 1)) if s.begins_with("idle_") or s.begins_with("guard_") else &""
	return wid if WeaponLook.IDS.has(wid) else &""


## Whether the tile plays (it doesn't while scrolled out of view).
func is_playing() -> bool:
	return _playing


## Plays or pauses the loop; paused, the viewport stops rendering and keeps the
## last frame. Playing builds the fighter if it isn't yet. Before the tile is
## ready it only stores the wish, which _ready() applies.
func set_playing(on: bool) -> void:
	_playing = on
	if is_node_ready():
		_sync()


## True for a tile showing the fighter held still: nothing for the entry to
## play.
func is_still() -> bool:
	return duration <= 0.0


## Whether the tile's rect is within its nearest ScrollContainer's visible
## rect (the whole rect if it has none), and the tile itself is shown. The
## gallery can read it; the tile acts on it itself.
func is_on_screen() -> bool:
	if not is_visible_in_tree():
		return false
	if _scroll == null:
		_scroll = _find_scroll()
	if _scroll == null:
		return true
	return _scroll.get_global_rect().intersects(get_global_rect())


## Poses the fighter `t` seconds into the loop (wrapped round it).
func seek(t: float) -> void:
	time = fposmod(t, duration) if duration > 0.0 else 0.0
	if _poser != null:
		_poser.pose(time)


## The chips' texts, in the badges' order.
func badge_texts() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for c: Node in _badges.get_children():
		out.append((c.get_child(0) as Label).text)
	return out


## The viewport follows `_playing`, and a playing tile has its fighter.
func _sync() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if _playing else SubViewport.UPDATE_DISABLED
	if _playing:
		ensure_built()


func _process(delta: float) -> void:
	var now: bool = is_on_screen()
	if now != _on_screen:
		_on_screen = now
		set_playing(now)
	if _playing and duration > 0.0 and _poser != null:
		seek(time + delta * playback_rate)


func _gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT and entry != null:
		accept_event()
		opened.emit(entry)


func _find_scroll() -> ScrollContainer:
	var n: Node = get_parent()
	while n != null:
		if n is ScrollContainer:
			return n as ScrollContainer
		n = n.get_parent()
	return null


## The viewport's world: a key light, a fill from ambient, a floor, and a
## three-quarter camera on the fighter.
func _build_stage() -> void:
	if _stage_built:
		return
	_stage_built = true
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.215, 0.25)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.7)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40.0, -30.0, 0.0)
	key.light_energy = 1.5
	viewport.add_child(key)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = 1.1
	disc.bottom_radius = 1.1
	disc.height = 0.02
	floor_mesh.mesh = disc
	floor_mesh.position.y = -0.01
	var floor_mat: StandardMaterial3D = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.32, 0.33, 0.35)
	floor_mat.roughness = 0.95
	floor_mesh.material_override = floor_mat
	viewport.add_child(floor_mesh)
	var camera: Camera3D = Camera3D.new()
	camera.fov = 38.0
	camera.position = Vector3(2.0, 1.5, 3.4)
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
	camera.current = true


## Frees the fighter and the poser and rewinds the loop.
func _drop_fighter() -> void:
	if model != null:
		viewport.remove_child(model)
		model.queue_free()
		model = null
	_poser = null
	time = 0.0
	duration = 0.0
	playback_rate = 1.0


func _show_caption() -> void:
	if entry == null:
		return
	name_label.text = entry.name
	name_label.tooltip_text = entry.name
	id_label.text = String(entry.id)
	_set_chips()


## Builds the fighter, its libraries, weapon and poser for `entry`.
func _build() -> void:
	_drop_fighter()
	model = FighterLook.instantiate_fighter(fighter_id)
	model.autoplay_idle = false
	viewport.add_child(model)
	_add_libraries()
	var weapon: StringName = weapon_for(entry)
	if weapon != &"":
		model.attach_weapon(WeaponLook.load_id(weapon))
	var chain: Array[String] = _chain()
	if chain.is_empty():
		# nothing to play: the idle, held
		_poser = ClipPoser.new(model, [_still_clip()] as Array[String])
		duration = 0.0
	else:
		_poser = ClipPoser.new(model, chain)
		duration = _poser.length
		playback_rate = _rate()
	_poser.pose(0.0)


## The shared libraries on the fighter's player: the Iglesias sets (with the
## packs; checked once here) and the hand-keyed clips; the CC0 library is the
## fighter's own.
func _add_libraries() -> void:
	var player: AnimationPlayer = model.animation_player
	var sets: Dictionary[StringName, AnimationLibrary] = StudioLibraries.sets()
	for set_name: StringName in sets:
		player.add_animation_library(set_name, sets[set_name])
	var keyed: AnimationLibrary = StudioLibraries.keyed()
	if keyed != null:
		player.add_animation_library(KeyedClips.LIBRARY, keyed)


## The chain to play, qualified for the fighter's player: the entry's clips if
## they are all there, else its fallbacks, else empty.
func _chain() -> Array[String]:
	var chain: Array[String] = _qualify(entry.clips)
	if not chain.is_empty() and _plays(chain):
		_stretched = false
		return chain
	var fallback: Array[String] = _qualify(entry.fallbacks)
	if not fallback.is_empty() and _plays(fallback):
		_stretched = entry.kind == StudioCatalogue.KIND_MOVE
		return fallback
	return [] as Array[String]


func _rate() -> float:
	if _stretched:
		var seconds: float = _move_seconds()
		if seconds > 0.0:
			return duration / seconds
	return 1.0 if is_nan(entry.speed) or entry.speed <= 0.0 else entry.speed


## How long the game plays the entry's move (s), or 0 when it isn't one.
func _move_seconds() -> float:
	var def: WeaponDef = Moves.WEAPONS.get(entry.group)
	if def == null or not def.moves.has(entry.id):
		return 0.0
	return float(def.moves[entry.id].total_frames()) / float(SimConst.FPS)


## `ids` (ClipChain entries) as the fighter's animation names.
func _qualify(ids: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var set_name: StringName = ClipLibraries.set_for(fighter_id, _swing())
	for id: String in ids:
		out.append(ClipChain.qualified(set_name, id))
	return out


## The move's baked swing, for the clip set it asks for, or null.
func _swing() -> Swing:
	var def: WeaponDef = Moves.WEAPONS.get(entry.group)
	if entry.kind == StudioCatalogue.KIND_MOVE and def != null and def.moves.has(entry.id):
		return def.moves[entry.id].swing
	return null


## Whether every clip of `chain` is on the fighter's player and the parts fit
## their clips (what ClipPoser needs).
func _plays(chain: Array[String]) -> bool:
	var player: AnimationPlayer = model.animation_player
	var entries: Array[String] = []
	var lengths: Dictionary = {}
	for part: String in chain:
		var slash: int = part.find("/")
		var rest: String = part.substr(slash + 1)
		var parsed: ClipChain.Part = ClipChain.parse(rest, [] as Array[String])
		if parsed == null:
			return false
		var id: StringName = parsed.id
		var anim: String = part.substr(0, slash + 1) + String(id)
		if not player.has_animation(anim):
			return false
		lengths[id] = player.get_animation(anim).length * float(ClipManifest.SOURCE_FPS)
		entries.append(rest)
	return not ClipChain.lay_out(entries, lengths, [] as Array[String]).is_empty()


## The idle for the held weapon, from the CC0 library.
func _still_clip() -> String:
	return "%s/%s" % [FighterModel.LIBRARY, model.idle_clip()]


func _set_chips() -> void:
	for c: Node in _badges.get_children():
		_badges.remove_child(c)
		c.queue_free()
	for b: StringName in StudioCatalogue.BADGES:
		if entry.badges.get(b, false):
			_badges.add_child(_chip(b))


func _chip(badge: StringName) -> PanelContainer:
	var chip: PanelContainer = PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = CHIP_COLORS.get(badge, Color(0.4, 0.4, 0.45))
	style.set_corner_radius_all(3)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 1.0
	chip.add_theme_stylebox_override(&"panel", style)
	var label: Label = Label.new()
	label.text = String(badge)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"font_size", 11)
	label.add_theme_constant_override(&"outline_size", 0)
	label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
	label.add_theme_color_override(&"font_color", Color(0.08, 0.08, 0.1))
	chip.add_child(label)
	return chip
