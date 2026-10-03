class_name MatchHud
extends CanvasLayer
## The minimal match HUD (task 24 brings the full one): both fighters' HP bars
## with posture under them, round pips and an ultimate badge, the round label,
## centre announcements (Round N, Fight, K.O., the round's winner,
## Disarmed) and a hint line (ultimate ready, pick up your weapon), shown only
## while the round is being fought. It hides when the results open.
##
## Announcements are timed on the host's rules steps, not the wall clock, so
## they slow down with slow motion and freeze with pause. Port of the
## announcement and bar logic of src/ui/hud.ts (its milliseconds become
## frames at 60 per second). Its text takes the UI theme's fonts
## (ui/theme/ink_wash.tres) and its colours are UiPalette's.

## The host to follow. The default is the parent (match_host.tscn).
@export var host_path: NodePath = ^".."

## Announcement lengths in rules steps (the demo's ms / 1000 * 60).
const ROUND_FRAMES: int = 78
const FIGHT_FRAMES: int = 54
const KO_FRAMES: int = 120
const DOUBLE_KO_FRAMES: int = 132
const ROUND_RESULT_DELAY: int = 78
const ROUND_RESULT_FRAMES: int = 96
const DISARM_FRAMES: int = 90
## The white lag band under HP holds this long (s), then drains at LAG_DRAIN/s.
const LAG_HOLD: float = 0.45
const LAG_DRAIN: float = 0.6

const HP_COLOR: Color = UiPalette.HP_HI
const HP_LOW_COLOR: Color = UiPalette.DANGER
const POSTURE_COLOR: Color = UiPalette.POSTURE
const POSTURE_HOT_COLOR: Color = UiPalette.POSTURE_HOT
const POSTURE_FULL_COLOR: Color = UiPalette.DANGER
const GOLD: Color = UiPalette.GOLD
const DIM: Color = Color(1.0, 1.0, 1.0, 0.25)

var host: MatchHost

## The announcement on screen: { "text", "sub", "until" } (until is a step).
var announcement: Dictionary = {}
## Announcements waiting for their step: [{ "at", "text", "sub", "frames" }].
var _queued: Array[Dictionary] = []
var _root: Control
var _plates: Array[Label] = []
var _tags: Array[Label] = []
var _hp: Array[HudBar] = []
var _posture: Array[HudBar] = []
var _pips: Array[Array] = [[], []]
var _ults: Array[Label] = []
var _round_label: Label
var _announce_label: Label
var _announce_sub: Label
var _hint: Label
var _lag: Array[float] = [1.0, 1.0]
var _lag_hold: Array[float] = [0.0, 0.0]
var _blink: float = 0.0


func _ready() -> void:
	_build()
	if host == null and has_node(host_path):
		var h: Node = get_node(host_path)
		if h is MatchHost:
			bind(h as MatchHost)


func bind(p_host: MatchHost) -> void:
	if _root == null:
		_build()
	if host != null:
		host.match_started.disconnect(_on_match_started)
		host.sim_event.disconnect(_on_sim_event)
		host.stepped.disconnect(_on_stepped)
		host.match_finished.disconnect(_on_match_finished)
	host = p_host
	host.match_started.connect(_on_match_started)
	host.sim_event.connect(_on_sim_event)
	host.stepped.connect(_on_stepped)
	host.match_finished.connect(_on_match_finished)
	if host.is_started():
		_on_match_started(host.config)


## The centre text now ("" when none), for tests and screenshots.
func announcement_text() -> String:
	return String(announcement.get("text", ""))


func hint_text() -> String:
	return _hint.text if _hint != null else ""


## Drops the HP lag bands onto the current HP at once (after stepping without
## the clock, as screenshot scenes do).
func snap_bars() -> void:
	if host == null or not host.is_started():
		return
	for i: int in 2:
		_lag[i] = maxf(0.0, host.fighter(i).hp / SimConst.HP_MAX)
		_lag_hold[i] = 0.0
	_process(0.0)


# ------------------------------------------------------------------ host signals

func _on_match_started(cfg: MatchConfig) -> void:
	visible = not host.attract
	announcement = {}
	_queued.clear()
	_lag = [1.0, 1.0]
	_lag_hold = [0.0, 0.0]
	var me: int = _me()
	for i: int in 2:
		var s: MatchSide = cfg.sides[i]
		var who: String = s.display_name()
		if i == me:
			who += " (You)"
		_plates[i].text = "%s  ·  %s" % [who, Moves.WEAPONS[s.weapon_id].name] if i == 0 else "%s  ·  %s" % [Moves.WEAPONS[s.weapon_id].name, who]
	_refresh_announcement()


## The results take the screen: the HUD clears its centre text and hint and
## hides until the next match starts.
func _on_match_finished(_results: MatchResults) -> void:
	announcement = {}
	_queued.clear()
	_refresh_announcement()
	_hint.text = ""
	visible = false


func _on_sim_event(e: Dictionary) -> void:
	var training: bool = host.config.mode == MatchConfig.TRAINING
	var watch: bool = _me() < 0
	var now: int = host.step_count
	match e["t"]:
		&"roundStart":
			var n: int = int(e["round"])
			_round_label.text = "Round %d" % n
			if not training:
				var wins: Array[int] = host.sim_match.wins
				var final: bool = wins[0] == SimConst.ROUNDS_TO_WIN - 1 and wins[1] == SimConst.ROUNDS_TO_WIN - 1
				announce("Round %d" % n, "Final round" if final else "", ROUND_FRAMES)
		&"fight":
			if not training:
				announce("Fight", "", FIGHT_FRAMES)
		&"ko":
			if not training:
				if int(e["winner"]) < 0:
					announce("Double K.O.", "", DOUBLE_KO_FRAMES)
				else:
					announce("K.O.", "", KO_FRAMES)
		&"roundOver":
			if not training:
				var winner: int = int(e["winner"])
				var text: String = "Draw"
				var sub: String = "The round will be replayed" if winner < 0 else ("Perfect" if e["perfect"] else "")
				if winner >= 0:
					if watch:
						text = "%s wins the round" % host.fighter(winner).name
					else:
						text = "You win the round" if winner == _me() else "You lose the round"
				_queued.append({"at": now + ROUND_RESULT_DELAY, "text": text, "sub": sub, "frames": ROUND_RESULT_FRAMES})
		&"disarm":
			var victim: int = int(e["victim"])
			var sub: String = ""
			if not watch:
				sub = "Retrieve your weapon or fight bare-handed" if victim == _me() else "Stand between them and their blade"
			announce("Disarmed", sub, DISARM_FRAMES)


func _on_stepped(_step: int) -> void:
	var now: int = host.step_count
	var keep: Array[Dictionary] = []
	for q: Dictionary in _queued:
		if now >= int(q["at"]):
			announce(q["text"], q["sub"], int(q["frames"]))
		else:
			keep.append(q)
	_queued = keep
	_refresh_announcement()


## Shows a centre announcement for this many rules steps.
func announce(text: String, sub: String, frames: int) -> void:
	announcement = {"text": text, "sub": sub, "until": host.step_count + frames}
	_refresh_announcement()


func _refresh_announcement() -> void:
	if not announcement.is_empty() and host != null and host.step_count >= int(announcement["until"]):
		announcement = {}
	_announce_label.text = String(announcement.get("text", ""))
	_announce_sub.text = String(announcement.get("sub", ""))


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if host == null or not host.is_started() or not visible:
		return
	_blink += delta
	for i: int in 2:
		var f: Fighter = host.fighter(i)
		var hp: float = maxf(0.0, f.hp / SimConst.HP_MAX)
		if hp < _lag[i]:
			_lag_hold[i] += delta
			if _lag_hold[i] > LAG_HOLD:
				_lag[i] = maxf(hp, _lag[i] - delta * LAG_DRAIN)
		else:
			_lag[i] = hp
			_lag_hold[i] = 0.0
		_hp[i].value = hp
		_hp[i].lag = _lag[i]
		_hp[i].fill_color = HP_LOW_COLOR if hp <= 0.25 and hp > 0.0 and fmod(_blink, 0.8) < 0.4 else HP_COLOR
		var p: float = f.posture / SimConst.POSTURE_MAX
		_posture[i].value = p
		if p >= 0.999:
			_posture[i].fill_color = POSTURE_FULL_COLOR if fmod(_blink, 0.3) < 0.15 else POSTURE_HOT_COLOR
		elif p >= 0.7:
			_posture[i].fill_color = POSTURE_HOT_COLOR
		else:
			_posture[i].fill_color = POSTURE_COLOR
		_posture[i].queue_redraw()
		_hp[i].queue_redraw()
		var pips: Array = _pips[i]
		for k: int in pips.size():
			(pips[k] as ColorRect).color = GOLD if host.sim_match.wins[i] > k else DIM
		_ults[i].modulate = GOLD if f.can_ult() else (Color(1, 1, 1, 0.12) if f.ult_used and f.hp <= SimConst.ULT_HP_THRESHOLD else DIM)
		_tags[i].visible = not f.armed
	_hint.text = _hints()


func _hints() -> String:
	var me: int = _me()
	if me < 0 or not host.sim_match.fighting():
		return ""
	var f: Fighter = host.fighter(me)
	var lines: PackedStringArray = []
	if not f.armed:
		var w: DroppedWeapon = host.world.weapon_of(me)
		if w != null and w.grounded and Vector2(w.pos.x - f.pos.x, w.pos.z - f.pos.z).length() < 2.2:
			lines.append("Pick up your weapon: %s" % host.label("interact", me))
	if f.can_ult() and f.state != &"ult" and f.state != &"ultChoice":
		var ult_key: String = host.label("ultimate", me)
		lines.append(
			"Ultimate ready: %s + %s%s" % [host.label("light", me), host.label("heavy", me), (" or %s" % ult_key) if ult_key != "" else ""]
		)
	return "\n".join(lines)


## The side a human plays (the HUD's "you"), or -1 in Watch.
func _me() -> int:
	if host == null or host.config == null:
		return -1
	if host.config.mode == MatchConfig.VERSUS:
		return -1
	return host.config.first_human_side()


# ------------------------------------------------------------------ building

## A label in one of the theme's variations, ink-outlined to read over the
## arena.
func _label(node_name: String, text: String, variation: StringName, font_size: int, outline: int = 6) -> Label:
	var l: Label = UiTheme.label(text, variation, font_size)
	l.name = node_name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.add_theme_color_override("font_outline_color", Color(UiPalette.INK, 0.85))
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build() -> void:
	if _root != null:
		return
	layer = 5
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	for i: int in 2:
		var right: bool = i == 1
		var box: VBoxContainer = VBoxContainer.new()
		box.name = "Side%d" % i
		box.add_theme_constant_override("separation", 4)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if right:
			box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			box.offset_left = -600.0
			box.offset_right = -32.0
		else:
			box.set_anchors_preset(Control.PRESET_TOP_LEFT)
			box.offset_left = 32.0
			box.offset_right = 600.0
		box.offset_top = 24.0
		_root.add_child(box)

		var plate_row: HBoxContainer = HBoxContainer.new()
		plate_row.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
		plate_row.add_theme_constant_override("separation", 12)
		box.add_child(plate_row)
		var plate: Label = _label("Plate%d" % i, "Fighter", UiTheme.DISPLAY, 24)
		var tag: Label = _label("Tag%d" % i, "Disarmed", UiTheme.EYEBROW, 16)
		tag.add_theme_color_override("font_color", UiPalette.DANGER)
		tag.visible = false
		if right:
			plate_row.add_child(tag)
			plate_row.add_child(plate)
		else:
			plate_row.add_child(plate)
			plate_row.add_child(tag)
		_plates.append(plate)
		_tags.append(tag)

		var hp: HudBar = HudBar.new()
		hp.custom_minimum_size = Vector2(568.0, 22.0)
		hp.reversed = right
		hp.fill_color = HP_COLOR
		box.add_child(hp)
		_hp.append(hp)
		var posture: HudBar = HudBar.new()
		posture.custom_minimum_size = Vector2(568.0, 8.0)
		posture.reversed = right
		posture.value = 0.0
		posture.fill_color = POSTURE_COLOR
		posture.lag_color = Color(0, 0, 0, 0)
		box.add_child(posture)
		_posture.append(posture)

		var meta: HBoxContainer = HBoxContainer.new()
		meta.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
		meta.add_theme_constant_override("separation", 8)
		box.add_child(meta)
		var pips: Array = []
		var ult: Label = _label("Ult%d" % i, "ULT", UiTheme.DISPLAY, 18, 4)
		ult.modulate = DIM
		if right:
			meta.add_child(ult)
		for k: int in SimConst.ROUNDS_TO_WIN:
			var pip: ColorRect = ColorRect.new()
			pip.custom_minimum_size = Vector2(18.0, 18.0)
			pip.color = DIM
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			meta.add_child(pip)
			pips.append(pip)
		if not right:
			meta.add_child(ult)
		_pips[i] = pips
		_ults.append(ult)

	_round_label = _label("RoundLabel", "Round 1", UiTheme.DISPLAY, 24)
	_round_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_label.offset_left = -120.0
	_round_label.offset_right = 120.0
	_round_label.offset_top = 26.0
	_root.add_child(_round_label)

	_announce_label = _label("Announce", "", UiTheme.DISPLAY, 84, 12)
	_announce_label.set_anchors_preset(Control.PRESET_CENTER)
	_announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_announce_label.offset_left = -700.0
	_announce_label.offset_right = 700.0
	_announce_label.offset_top = -170.0
	_announce_label.offset_bottom = -50.0
	_root.add_child(_announce_label)
	_announce_sub = _label("AnnounceSub", "", UiTheme.EYEBROW, 24)
	_announce_sub.set_anchors_preset(Control.PRESET_CENTER)
	_announce_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_sub.offset_left = -700.0
	_announce_sub.offset_right = 700.0
	_announce_sub.offset_top = -50.0
	_announce_sub.offset_bottom = 0.0
	_root.add_child(_announce_sub)

	_hint = _label("Hint", "", &"", 22)
	_hint.add_theme_color_override("font_color", GOLD)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_hint.offset_left = -600.0
	_hint.offset_right = 600.0
	_hint.offset_top = -110.0
	_hint.offset_bottom = -40.0
	_root.add_child(_hint)
