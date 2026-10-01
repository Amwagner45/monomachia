extends GutTest
## Size budgets and import hygiene for the imported art in game/assets:
## the folder stays under 60 MB with no file over 10 MB, textures are scaled
## down, every texture a model references exists, and every skinned model is
## retargeted through the humanoid bone map.

const ASSETS: String = "res://assets"
const MAX_TOTAL_BYTES: int = 60 * 1024 * 1024
const MAX_FILE_BYTES: int = 10 * 1024 * 1024
const MAX_BASE_COLOR: int = 2048
const MAX_DATA_MAP: int = 1024
const BONE_MAP: String = "res://assets/quaternius/ual_bone_map.tres"


static func _files(dir_path: String, out: Array[String]) -> Array[String]:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub: String in dir.get_directories():
		_files(dir_path.path_join(sub), out)
	for file: String in dir.get_files():
		out.append(dir_path.path_join(file))
	return out


## A PNG's width and height, from its header.
static func _png_size(path: String) -> Vector2i:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	f.big_endian = true
	f.seek(16)
	var size: Vector2i = Vector2i(f.get_32(), f.get_32())
	f.close()
	return size


func test_the_assets_folder_stays_under_60_mb() -> void:
	var total: int = 0
	for path: String in _files(ASSETS, []):
		total += FileAccess.get_size(path)
	gut.p("game/assets holds %.1f MB" % (total / 1048576.0))
	assert_lt(total, MAX_TOTAL_BYTES)


func test_no_asset_file_is_over_10_mb() -> void:
	for path: String in _files(ASSETS, []):
		assert_lt(FileAccess.get_size(path), MAX_FILE_BYTES, path)


func test_textures_are_scaled_down() -> void:
	var pngs: Array[String] = []
	for root: String in [ASSETS, "res://fighters"]:
		for path: String in _files(root, []):
			if path.ends_with(".png"):
				pngs.append(path)
	assert_gt(pngs.size(), 20)
	for path: String in pngs:
		var size: Vector2i = _png_size(path)
		var file: String = path.get_file()
		var data_map: bool = file.contains("_Normal") or file.contains("_ORM") or file.contains("_Roughness")
		var limit: int = MAX_DATA_MAP if data_map else MAX_BASE_COLOR
		assert_true(size.x <= limit and size.y <= limit, "%s is %dx%d (limit %d)" % [file, size.x, size.y, limit])


func test_textures_import_vram_compressed() -> void:
	for root: String in [ASSETS, "res://fighters"]:
		for path: String in _files(root, []):
			if not path.ends_with(".png.import"):
				continue
			var cfg: ConfigFile = ConfigFile.new()
			assert_eq(cfg.load(path), OK)
			assert_eq(cfg.get_value("params", "compress/mode", -1), 2, "%s is VRAM compressed" % path.get_file())
			if path.contains("_Normal"):
				assert_eq(cfg.get_value("params", "compress/normal_map", -1), 1, "%s is a normal map" % path.get_file())


func test_every_texture_a_model_references_exists() -> void:
	var models: int = 0
	for path: String in _files(ASSETS, []):
		if not path.ends_with(".gltf"):
			continue
		models += 1
		var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for image: Dictionary in doc.get("images", []):
			var uri: String = String(image["uri"]).uri_decode()
			var target: String = path.get_base_dir().path_join(uri).simplify_path()
			assert_true(FileAccess.file_exists(target), "%s -> %s" % [path.get_file(), uri])
	assert_eq(models, 15, "2 bodies, 10 outfit parts and 3 hairstyles")


func test_every_skinned_model_is_retargeted_through_the_bone_map() -> void:
	for path: String in _files(ASSETS, []):
		if not (path.ends_with(".gltf.import") or path.ends_with(".glb.import")):
			continue
		var text: String = FileAccess.get_file_as_string(path)
		assert_true(text.contains("\"retarget/bone_map\": Resource(") and text.contains(BONE_MAP), "%s uses the bone map" % path.get_file())


func test_assets_are_credited() -> void:
	var credits: String = FileAccess.get_file_as_string("res://assets/CREDITS.md")
	assert_true(credits.contains("Quaternius"))
	assert_true(credits.contains("CC0"))
