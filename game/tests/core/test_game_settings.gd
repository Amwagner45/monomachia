extends GutTest
## GameSettings: the player's settings, saved to a ConfigFile. For now it
## holds the graphics preset: High by default, saved and loaded, and anything
## unknown falls back to High. Test and shot runs ask for the defaults.

const PATH: String = "user://test_settings.cfg"


func after_each() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func _saved_low() -> void:
	var settings := GameSettings.new()
	settings.set_graphics_preset(&"low")
	settings.save(PATH)


func test_the_graphics_preset_is_high_by_default() -> void:
	var settings := GameSettings.new()
	assert_eq(settings.graphics_preset_id, &"high")
	assert_eq(settings.graphics_preset().id, &"high")
	assert_eq(GameSettings.PATH, "user://settings.cfg")


func test_a_missing_file_gives_the_defaults() -> void:
	assert_eq(GameSettings.load_from(PATH).graphics_preset_id, &"high")


func test_the_preset_saves_and_loads() -> void:
	var settings := GameSettings.new()
	assert_true(settings.set_graphics_preset(&"low"))
	assert_eq(settings.graphics_preset().id, &"low")
	assert_eq(settings.save(PATH), OK)
	assert_eq(GameSettings.load_from(PATH).graphics_preset_id, &"low")


func test_an_unknown_preset_is_refused_however_it_is_set() -> void:
	var settings := GameSettings.new()
	settings.set_graphics_preset(&"medium")
	assert_false(settings.set_graphics_preset(&"ultra"))
	assert_eq(settings.graphics_preset_id, &"medium", "unchanged")
	settings.graphics_preset_id = &"ultra"
	assert_eq(settings.graphics_preset_id, &"medium", "assigning it directly changes nothing either")
	assert_eq(settings.graphics_preset().id, &"medium")


func test_an_unknown_saved_preset_falls_back_to_high() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(GameSettings.SECTION_GRAPHICS, "preset", "ultra")
	cfg.save(PATH)
	assert_eq(GameSettings.load_from(PATH).graphics_preset_id, &"high")
	cfg.set_value(GameSettings.SECTION_GRAPHICS, "preset", 3)
	cfg.save(PATH)
	assert_eq(GameSettings.load_from(PATH).graphics_preset_id, &"high", "not even a string")


func test_an_unreadable_file_gives_the_defaults() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("[graphics\npreset = = \n")
	f.close()
	assert_eq(GameSettings.load_from(PATH).graphics_preset_id, &"high")
	assert_engine_error("ConfigFile parse error")


func test_a_run_asking_for_the_defaults_ignores_the_saved_file() -> void:
	_saved_low()
	assert_eq(GameSettings.load_for_run(true, PATH).graphics_preset_id, &"high")
	assert_eq(GameSettings.load_for_run(false, PATH).graphics_preset_id, &"low")
	assert_true(OS.has_environment(GameSettings.DEFAULTS_ENV), "godot.mjs runs the tests with the defaults")
