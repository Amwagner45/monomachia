extends Node
## A shot scene for the Animation Studio's gallery: opens the Studio on a tab and
## a body, lets the tiles in view start playing, and saves the window. Run
## through `node scripts/godot.mjs shots` (tools/shot.gd), which fills the
## window at 1600x900; the PNGs go to shots/studio/ (gitignored):
##
##   node scripts/godot.mjs shots res://tools/anim_studio/studio_shot.tscn shots/studio/katana_hunter.png 60 --tab=katana --body=hunter
##
## Options:
## - --tab=katana|daggers|greatsword|fists|states|ults|source (default katana)
## - --body=hunter|rogue (default hunter)
## - --search=<text>: type this in the search box
## - --badges=<badge>,<badge>...: choose these badge chips
##
## It also prints how the frames went (how long the frame that built the tiles
## in view took, then the average and the slowest frame, and how many of the
## tab's tiles were built and playing), so it doubles as the gallery's
## performance check. `--fixed-fps` switches off the wait for the next frame,
## so a frame takes what its work costs (an empty gallery, `--search=zzz`, is
## the baseline: the Studio's own cost).

## Frames after the tiles in view are built before the shot is taken, so the
## animations are part way through and the viewports have drawn.
const SETTLE_FRAMES: int = 30

var studio: AnimStudio = null
var _tab: StringName = &"katana"
var _frames_since_ready: int = 0
var _last_usec: int = 0
var _frame_msec: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	var body: StringName = &"hunter"
	var search: String = ""
	var badges: Array[StringName] = []
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--tab="):
			_tab = StringName(a.substr(6))
		elif a.begins_with("--body="):
			body = StringName(a.substr(7))
		elif a.begins_with("--search="):
			search = a.substr(9)
		elif a.begins_with("--badges="):
			for b: String in a.substr(9).split(",", false):
				badges.append(StringName(b))
	studio = (load("res://tools/anim_studio/studio.tscn") as PackedScene).instantiate() as AnimStudio
	add_child(studio)
	studio.set_fighter(body)
	var gallery: Gallery = studio.get_node("%Gallery") as Gallery
	gallery.show_group(_tab)
	if not search.is_empty() or not badges.is_empty():
		gallery.set_filter(search, badges)
	_last_usec = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if _all_in_view_built():
		_frames_since_ready += 1
		_frame_msec.append(float(now - _last_usec) / 1000.0)
	_last_usec = now


func shot_frames() -> int:
	return SETTLE_FRAMES


## True once the tiles in view are built and have had SETTLE_FRAMES to draw;
## then reports the frame times.
func shot_ready() -> bool:
	if _frames_since_ready < SETTLE_FRAMES:
		return false
	var gallery: Gallery = studio.get_node("%Gallery") as Gallery
	var tiles: Array[AnimTile] = gallery.tiles_in(_tab)
	var built: int = 0
	var playing: int = 0
	for t: AnimTile in tiles:
		built += 1 if t.model != null else 0
		playing += 1 if t.is_playing() else 0
	# The first frame is the one that built the tiles: report it apart.
	var total: float = 0.0
	var slowest: float = 0.0
	for i: int in range(1, _frame_msec.size()):
		total += _frame_msec[i]
		slowest = maxf(slowest, _frame_msec[i])
	print("studio_shot: %s: %d tiles, %d built, %d playing; building them took %.0f ms; then %d frames, average %.1f ms, slowest %.1f ms" % [
		_tab, tiles.size(), built, playing, _frame_msec[0], _frame_msec.size() - 1, total / maxf(1.0, float(_frame_msec.size() - 1)), slowest])
	return true


func _all_in_view_built() -> bool:
	var gallery: Gallery = studio.get_node("%Gallery") as Gallery
	for t: AnimTile in gallery.tiles_in(_tab):
		if t.visible and t.is_on_screen() and t.model == null:
			return false
	return true
