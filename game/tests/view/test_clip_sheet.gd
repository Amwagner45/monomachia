extends GutTest
## The Iglesias clip sheet (tools/shot_scenes/clip_sheet.gd): its options and
## where it saves each weapon's sheet. Rendering needs a window and the clip
## libraries, so it is checked by running the shot, not here.

const ClipSheet := preload("res://tools/shot_scenes/clip_sheet.gd")


func _sheet() -> Node3D:
	var s: Node3D = ClipSheet.new()
	s.auto_run = false
	add_child_autofree(s)
	return s


func test_it_defaults_to_every_weapon_and_every_manifest_clip() -> void:
	var s: Node3D = _sheet()
	assert_eq(s.weapons, [&"katana", &"greatsword", &"daggers"] as Array[StringName])
	assert_eq(s.clips, ClipManifest.read().ids())
	assert_false(s.reverse)


func test_it_reads_its_options() -> void:
	var s: Node3D = _sheet()
	var first: StringName = ClipManifest.read().ids()[0]
	s.apply_args(PackedStringArray(["--weapon=daggers", "--clips=%s" % first, "--reverse", "--out=C:/x/sheet.png"]))
	assert_eq(s.weapons, [&"daggers"] as Array[StringName])
	assert_eq(s.clips, [first] as Array[StringName])
	assert_true(s.reverse)
	assert_eq(s.out_path, "C:/x/sheet.png")


func test_each_weapons_sheet_goes_beside_the_out_file() -> void:
	assert_eq(ClipSheet.sheet_path("C:/x/sheet.png", &"greatsword"), "C:/x/sheet_greatsword.png")
