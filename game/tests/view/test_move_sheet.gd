extends GutTest
## The contact-sheet tool (tools/shot_scenes/move_sheet.gd), headless: which
## frames a sheet shows, its cameras (the match camera over each fighter's
## shoulder, and three-quarter, close and hand views that keep the attacker in
## their crops), each row's caption with its phase and PoseCheck numbers, the
## layout of header, rows and cells, and the batch's moves and files. Headless
## runs draw nothing, so the cells are blank; the pictures themselves are
## reviewed from `npm run shots`.

const MoveSheet := preload("res://tools/shot_scenes/move_sheet.gd")


func after_each() -> void:
	MoveBench.free_all()


func _sheet(args: PackedStringArray = PackedStringArray()) -> MoveSheet:
	var sheet: MoveSheet = MoveSheet.new()
	sheet.auto_run = false
	sheet.apply_args(args)
	add_child_autofree(sheet)
	return sheet


func _attack(startup: int, active: int, recovery: int) -> AttackDef:
	var def: AttackDef = AttackDef.new()
	def.startup = startup
	def.active = active
	def.recovery = recovery
	return def


static func _feet(f: Fighter) -> Vector3:
	return Vector3(f.pos.x, f.pos.y, f.pos.z)


func _world_grip(sheet: MoveSheet) -> Vector3:
	var model: FighterModel = sheet.bench.view.model
	return model.skeleton.global_transform * model.rig.grip_point("Right")


func _world_bone(sheet: MoveSheet, bone: String) -> Vector3:
	var sk: Skeleton3D = sheet.bench.view.model.skeleton
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin


func test_the_key_frames_are_a_moves_landmarks() -> void:
	# start, mid wind-up, the last wind-up frame, contact, the last active
	# frame, mid recovery and the last frame the move shows
	assert_eq(MoveSheet.key_frames(_attack(9, 3, 13)), [1, 5, 9, 10, 12, 19, 24])
	assert_eq(MoveSheet.key_frames(_attack(2, 1, 2)), [1, 2, 3, 4], "a short move's landmarks fall together")


func test_frames_are_chosen_by_number_landmark_or_all() -> void:
	var def: AttackDef = _attack(9, 3, 13)
	assert_eq(MoveSheet.frames_for("keys", def), MoveSheet.key_frames(def))
	assert_eq(MoveSheet.frames_for("contact,1,end", def), [1, 10, 24], "in order")
	assert_eq(MoveSheet.frames_for("windup,cocked,release,follow", def), [5, 9, 12, 19])
	assert_eq(MoveSheet.frames_for("7, 7 ,30,0", def), [7], "repeats and frames the move doesn't show are dropped")
	var all: Array[int] = []
	for f: int in range(1, 25):
		all.append(f)
	assert_eq(MoveSheet.frames_for("all", def), all)


func test_the_arguments_choose_the_fighters_weapon_move_frames_and_views() -> void:
	var sheet: MoveSheet = _sheet(PackedStringArray([
		"--fighter=hunter", "--weapon=greatsword", "--move=g_l1", "--at=contact,end", "--views=hands,defender",
		"--defender=rogue", "--spacing=3",
	]))
	assert_eq(sheet.fighter_id, &"hunter")
	assert_eq(sheet.weapon_id, &"greatsword")
	assert_eq(sheet.move, &"g_l1")
	assert_eq(sheet.at, "contact,end")
	assert_eq(sheet.views, [&"hands", &"defender"] as Array[StringName])
	assert_eq(sheet.defender_id, &"rogue")
	assert_almost_eq(sheet.spacing, 3.0, 1e-6)
	assert_eq(sheet.bench.view.fighter_id, &"hunter")
	assert_eq(sheet.bench.weapon, Moves.GREATSWORD)
	assert_almost_eq(_feet(sheet.bench.defender).distance_to(_feet(sheet.bench.attacker)), 3.0, 1e-4)
	assert_eq(sheet.defender_view.fighter_id, &"rogue")


func test_the_defender_is_the_same_fighter_in_the_other_palette_unless_chosen() -> void:
	var sheet: MoveSheet = _sheet()
	assert_eq(sheet.bench.view.fighter_id, &"rogue")
	assert_eq(sheet.bench.view.palette, 0)
	assert_eq(sheet.defender_view.fighter_id, &"rogue")
	assert_eq(sheet.defender_view.palette, 1)
	assert_almost_eq(sheet.defender_view.position, _feet(sheet.bench.defender), Vector3.ONE * 1e-4, "where the rules have it")


func test_the_gameplay_views_are_the_match_camera_over_each_fighters_shoulder() -> void:
	var sheet: MoveSheet = _sheet()
	var a: Vector3 = _feet(sheet.bench.attacker)
	var d: Vector3 = _feet(sheet.bench.defender)
	var rig: CameraRig = CameraRig.new()
	for spec: Array in [[&"defender", d, a], [&"attacker", a, d]]:
		sheet.aim(spec[0])
		var player: Vector3 = spec[1]
		var opponent: Vector3 = spec[2]
		var target: Dictionary = rig.follow_target(player, opponent, (opponent - player).normalized())
		assert_almost_eq(sheet.camera.global_position, target["pos"] as Vector3, Vector3.ONE * 1e-3, "%s: the match camera's place" % spec[0])
		assert_almost_eq(sheet.camera.fov, rig.base_fov, 1e-3, "%s: the match camera's lens" % spec[0])
		var ahead: Vector3 = -sheet.camera.global_basis.z
		assert_gt(ahead.dot((opponent - sheet.camera.global_position).normalized()), 0.9, "%s: looking at the other fighter" % spec[0])
	rig.free()


## The top of the fighter's head, hood or hat included: the top of
## PoseCheck's head capsule.
func _crown(sheet: MoveSheet, frame: PoseCheck.Frame) -> Vector3:
	var head: PoseCheck.Capsule = sheet.bench.check.capsule("head")
	var ends: PackedVector3Array = head.ends(frame.bones)
	var top: Vector3 = ends[0] if ends[0].y > ends[1].y else ends[1]
	return sheet.bench.view.model.skeleton.global_transform * top + Vector3.UP * head.radius


func test_the_gameplay_views_keep_the_whole_screen_and_the_others_a_centred_square() -> void:
	var screen: Vector2 = Vector2(1600.0, 900.0)
	for view: StringName in [&"defender", &"attacker"]:
		assert_eq(MoveSheet.crop_rect(view, screen), Rect2(0.0, 0.0, 1600.0, 900.0), "%s: the whole screen" % view)
		assert_eq(MoveSheet.cell_size(view), Vector2i(MoveSheet.CELL_HEIGHT * 16 / 9, MoveSheet.CELL_HEIGHT), "%s: 16:9" % view)
	for view: StringName in [&"three_quarter", &"close", &"hands"]:
		assert_eq(MoveSheet.crop_rect(view, screen), Rect2(350.0, 0.0, 900.0, 900.0), "%s: a centred square" % view)
		assert_eq(MoveSheet.cell_size(view), Vector2i(MoveSheet.CELL_HEIGHT, MoveSheet.CELL_HEIGHT), "%s: square" % view)
	assert_eq(MoveSheet.crop_rect(&"defender", Vector2(1200.0, 900.0)), Rect2(0.0, 0.0, 1200.0, 900.0), "never wider than the screen")


func test_the_close_views_keep_the_attacker_in_their_crops() -> void:
	for id: StringName in FighterLook.IDS:
		var sheet: MoveSheet = _sheet(PackedStringArray(["--fighter=" + id]))
		var frame: PoseCheck.Frame = await sheet.bench.frame()
		var size: Vector2 = sheet.get_viewport().get_visible_rect().size
		var crown: Vector3 = _crown(sheet, frame)
		var grip: Vector3 = _world_grip(sheet)
		var feet: Vector3 = _feet(sheet.bench.attacker)
		var points: Dictionary[StringName, Array] = {
			&"three_quarter": [crown, grip, feet],
			&"close": [crown, grip],
			&"hands": [grip],
		}
		for view: StringName in points:
			sheet.aim(view)
			var crop: Rect2 = MoveSheet.crop_rect(view, size)
			for p: Vector3 in points[view]:
				assert_false(sheet.camera.is_position_behind(p), "%s %s: %s in front" % [id, view, p])
				assert_true(crop.has_point(sheet.camera.unproject_position(p)), "%s %s: %s inside the crop" % [id, view, p])
		sheet.aim(&"hands")
		assert_lt(sheet.camera.global_position.distance_to(grip), 1.2, "%s: the hands close up" % id)
		sheet.aim(&"three_quarter")
		var to_camera: Vector3 = (sheet.camera.global_position - feet) * Vector3(1.0, 0.0, 1.0)
		var forward: Vector3 = (_feet(sheet.bench.defender) - feet).normalized()
		var angle: float = rad_to_deg(forward.angle_to(to_camera.normalized()))
		assert_between(angle, 30.0, 60.0, "%s: three-quarters from the front" % id)
		MoveBench.free_all()


func test_a_move_sheet_has_a_row_per_chosen_frame_and_a_cell_per_view() -> void:
	var sheet: MoveSheet = _sheet(PackedStringArray(["--at=windup,contact,end", "--views=defender,hands"]))
	var def: AttackDef = Moves.KATANA.moves[&"k_l1"]
	var last: int = def.startup + def.active + def.recovery - 1
	var image: Image = await sheet.render(&"k_l1")
	assert_eq(sheet.rows.size(), 3)
	var contact: MoveSheet.Row = sheet.rows[1]
	assert_string_contains(contact.lines[0], "frame %d of %d" % [def.startup + 1, last])
	assert_string_contains(contact.lines[0], "active, contact")
	assert_string_contains(contact.lines[0], contact.report.summary(), "the PoseCheck numbers")
	assert_eq(contact.lines[1], MoveSheet.verdict(contact.report))
	assert_string_contains(sheet.rows[0].lines[0], "startup")
	assert_string_contains(sheet.rows[2].lines[0], "frame %d of %d" % [last, last])
	assert_string_contains(sheet.rows[2].lines[0], "recovery")
	for row: MoveSheet.Row in sheet.rows:
		assert_eq(row.cells.size(), 2, "a cell per view")
		assert_eq(row.cells[0].get_size(), MoveSheet.cell_size(&"defender"))
		assert_eq(row.cells[1].get_size(), MoveSheet.cell_size(&"hands"))
	assert_string_contains(sheet.title[0], "Right Cut")
	assert_eq(image.get_width(), MoveSheet.cell_size(&"defender").x + MoveSheet.GAP + MoveSheet.cell_size(&"hands").x)
	var row_height: int = MoveSheet.CAPTION_HEIGHT + MoveSheet.cell_size(&"hands").y
	assert_eq(image.get_height(), MoveSheet.HEADER_HEIGHT + 3 * (MoveSheet.GAP + row_height))


func test_the_header_names_the_move_the_defender_the_views_and_the_whole_move() -> void:
	var sheet: MoveSheet = _sheet(PackedStringArray(["--at=contact", "--views=defender,close"]))
	await sheet.render(&"k_l1")
	assert_eq(sheet.title.size(), 5, "a line each")
	assert_string_contains(sheet.title[0], "k_l1 Right Cut")
	assert_string_contains(sheet.title[1], "palette B) at 2.5 m")
	assert_eq(sheet.title[2], "views: gameplay camera behind the defender, close")
	var whole: String = MoveBench.summary(&"k_l1", await sheet.bench.play(&"k_l1"))
	assert_true(sheet.title[3].begins_with("k_l1 29 fr wrist"), "MoveBench's summary of the whole move: " + sheet.title[3])
	assert_false(sheet.title[3].contains("fails"), "...on two lines")
	assert_true(sheet.title[4].begins_with("fails 29/29: "), sheet.title[4])
	assert_eq(" ".join((sheet.title[3] + " " + sheet.title[4]).split(" ", false)), " ".join(whole.split(" ", false)))
	assert_false(sheet.title[4].contains("{"), "counts written out: " + sheet.title[4])
	var lines: int = sheet.title.size()
	assert_gte(MoveSheet.HEADER_HEIGHT, 2 * MoveSheet.TEXT_MARGIN + lines * MoveSheet.HEADER_FONT * 5 / 4, "room for every line")


func test_a_sheet_lets_go_of_its_world_when_it_leaves() -> void:
	var sheet: MoveSheet = _sheet()
	var world: World = sheet.bench.world
	remove_child(sheet)
	assert_null(world.fighters[0].opp, "the world's fighters let go of each other")
	add_child(sheet)


func test_the_guard_sheet_is_one_row_measured_in_the_guard() -> void:
	var sheet: MoveSheet = _sheet(PackedStringArray(["--views=close"]))
	await sheet.render(&"guard")
	assert_eq(sheet.rows.size(), 1)
	var row: MoveSheet.Row = sheet.rows[0]
	assert_true(row.lines[0].begins_with("guard"), row.lines[0])
	var expected: PoseCheck.Report = sheet.bench.check.measure(await sheet.bench.frame())
	assert_eq(row.report.summary(), expected.summary())
	assert_string_contains(row.lines[0], expected.summary())
	assert_eq(row.lines[1], MoveSheet.verdict(expected))


func test_the_verdict_names_the_failures_or_passes() -> void:
	var report: PoseCheck.Report = PoseCheck.Report.new()
	assert_eq(MoveSheet.verdict(report), "passes PoseCheck")
	report.elbows["Left"] = 180.0
	assert_eq(MoveSheet.verdict(report), "fails: " + ", ".join(report.failures()))
	var lines: PackedStringArray = ["Rogue with the Katana", "passes PoseCheck", "fails 0/29", "fails 3/29: left wrist 3", "fails: left elbow locked at 180°"]
	assert_eq(MoveSheet.tones(lines), [MoveSheet.TEXT_COLOR, MoveSheet.PASS_COLOR, MoveSheet.PASS_COLOR, MoveSheet.FAIL_COLOR, MoveSheet.FAIL_COLOR] as Array[Color])


func test_the_batch_is_the_guard_then_every_move_of_the_weapon() -> void:
	var sheet: MoveSheet = _sheet(PackedStringArray(["--weapon=greatsword", "--move=all"]))
	var expected: Array[StringName] = [MoveSheet.GUARD]
	expected.append_array(Moves.GREATSWORD.moves.keys())
	assert_eq(sheet.batch_moves(), expected)
	assert_eq(MoveSheet.sheet_path("C:/x/shots/katana.png", &"k_l1"), "C:/x/shots/katana_k_l1.png")
	assert_eq(MoveSheet.sheet_path("shots/greatsword", &"guard"), "shots/greatsword_guard.png")


func test_the_batch_saves_a_sheet_per_move_and_makes_their_index() -> void:
	var dir: String = ProjectSettings.globalize_path("user://test_move_sheet")
	DirAccess.make_dir_recursive_absolute(dir)
	var out: String = dir.path_join("katana.png")
	var sheet: MoveSheet = _sheet(PackedStringArray(["--move=all", "--at=contact", "--views=hands", "--out=" + out]))
	var moves: Array[StringName] = sheet.batch_moves()
	for move_id: StringName in moves:
		DirAccess.remove_absolute(MoveSheet.sheet_path(out, move_id))
	var index: Image = await sheet.batch()
	for move_id: StringName in moves:
		var path: String = MoveSheet.sheet_path(out, move_id)
		assert_true(FileAccess.file_exists(path), "%s saved" % path)
		DirAccess.remove_absolute(path)
	var cell: Vector2i = MoveSheet.cell_size(&"hands")
	var index_rows: int = ceili(moves.size() / float(MoveSheet.INDEX_COLUMNS))
	assert_eq(index.get_size(), Vector2i(
		MoveSheet.INDEX_COLUMNS * (cell.x + MoveSheet.GAP) - MoveSheet.GAP,
		MoveSheet.HEADER_HEIGHT + index_rows * (MoveSheet.GAP + MoveSheet.CAPTION_HEIGHT + cell.y)), "a captioned cell per move")
	assert_eq(sheet.title[0], "Rogue (palette A) with the Katana against the Rogue (palette B) at 2.5 m: the guard and every move")


func test_the_sheet_lays_out_its_header_rows_and_cells() -> void:
	var header: Image = Image.create(100, MoveSheet.HEADER_HEIGHT, false, Image.FORMAT_RGBA8)
	header.fill(Color.RED)
	var row: MoveSheet.Row = MoveSheet.Row.new()
	row.caption = Image.create(50, MoveSheet.CAPTION_HEIGHT, false, Image.FORMAT_RGBA8)
	row.caption.fill(Color.BLUE)
	var a: Image = Image.create(30, 20, false, Image.FORMAT_RGBA8)
	a.fill(Color.GREEN)
	var b: Image = Image.create(40, 20, false, Image.FORMAT_RGBA8)
	b.fill(Color.YELLOW)
	row.cells = [a, b]
	var out: Image = MoveSheet.compose(header, [row, row])
	var top: int = MoveSheet.HEADER_HEIGHT + MoveSheet.GAP
	var row_height: int = MoveSheet.CAPTION_HEIGHT + 20
	assert_eq(out.get_size(), Vector2i(100, top + row_height + MoveSheet.GAP + row_height), "as wide as the widest part")
	assert_eq(out.get_pixel(0, 0), Color.RED, "the header on top")
	for i: int in 2:
		var y: int = top + i * (row_height + MoveSheet.GAP)
		assert_eq(out.get_pixel(0, y), Color.BLUE, "row %d's caption" % i)
		assert_eq(out.get_pixel(0, y + MoveSheet.CAPTION_HEIGHT), Color.GREEN, "row %d's first cell" % i)
		assert_eq(out.get_pixel(29, y + MoveSheet.CAPTION_HEIGHT + 19), Color.GREEN)
		assert_eq(out.get_pixel(30 + MoveSheet.GAP, y + MoveSheet.CAPTION_HEIGHT), Color.YELLOW, "row %d's second cell after a gap" % i)
		assert_eq(out.get_pixel(30, y + MoveSheet.CAPTION_HEIGHT), MoveSheet.BACKGROUND, "the gap")
