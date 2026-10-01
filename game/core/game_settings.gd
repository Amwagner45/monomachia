class_name GameSettings
extends RefCounted
## The player's settings, saved to user://settings.cfg (a ConfigFile). For now
## it holds the graphics preset; the volumes, reduce flashes and button hints
## join it with their tasks. GameServices owns the one the game uses.
##
## Nothing here saves by itself: call save() after each change, as
## ControlProfiles does.
##
## File layout:
##   [graphics]  preset="high"

const PATH: String = "user://settings.cfg"
const SECTION_GRAPHICS: String = "graphics"
## When this environment variable is set, the run ignores the saved file and
## uses the defaults. godot.mjs sets it for test and shot runs, so what a
## player saved on this machine can't change them.
const DEFAULTS_ENV: String = "MONOMACHIA_DEFAULT_SETTINGS"

## The id of the chosen GraphicsPreset, always one of GraphicsPreset.IDS: an
## unknown id is ignored.
var graphics_preset_id: StringName = GraphicsPreset.DEFAULT_ID:
	set(id):
		if GraphicsPreset.IDS.has(id):
			graphics_preset_id = id


## The chosen graphics preset.
func graphics_preset() -> GraphicsPreset:
	return GraphicsPreset.load_id(graphics_preset_id)


## Chooses a graphics preset by id. Returns false, and changes nothing, for an
## unknown id.
func set_graphics_preset(id: StringName) -> bool:
	graphics_preset_id = id
	return graphics_preset_id == id


func save(path: String = PATH) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION_GRAPHICS, "preset", String(graphics_preset_id))
	return cfg.save(path)


## Loads the saved settings. A missing or unreadable file gives the defaults,
## and so does any saved value that isn't one the game knows.
static func load_from(path: String = PATH) -> GameSettings:
	var settings := GameSettings.new()
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(path) or cfg.load(path) != OK:
		return settings
	var preset: Variant = cfg.get_value(SECTION_GRAPHICS, "preset", "")
	if preset is String or preset is StringName:
		settings.set_graphics_preset(StringName(preset))
	return settings


## The settings a run starts with: the defaults when the run asks for them
## (DEFAULTS_ENV is set), the saved ones otherwise.
static func load_for_run(use_defaults: bool = OS.has_environment(DEFAULTS_ENV), path: String = PATH) -> GameSettings:
	return GameSettings.new() if use_defaults else load_from(path)
