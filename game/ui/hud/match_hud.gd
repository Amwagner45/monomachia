class_name MatchHud
extends CanvasLayer
## The match HUD (task 24 builds it out from the minimal one). The top bar
## (24.1): each side's plate (the 赤 or 青 seal, name, weapon and the disarmed
## tag), HP with its lag band and low-HP pulse, posture with its hot and full
## states, the round pips and the 奥義 badge, as HudState works them out, and
## the round's kanji between them. Also the round label,
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
## The low-HP pulse: one brightening (by LOW_PULSE_GAIN) every LOW_PULSE
## seconds; and full posture's blink, half of each POSTURE_BLINK seconds at
## POSTURE_BLINK_ALPHA (the demo's pulse-hp and blink).
const LOW_PULSE: float = 0.9
const LOW_PULSE_GAIN: float = 0.45
const POSTURE_BLINK: float = 0.35
const POSTURE_BLINK_ALPHA: float = 0.45
const POSTURE_COLORS: Dictionary = {
	HudState.Posture.CALM: UiPalette.POSTURE,
	HudState.Posture.HOT: UiPalette.POSTURE_HOT,
	HudState.Posture.FULL: UiPalette.DANGER,
}
const SEAL_COLORS: Array[Color] = [UiPalette.LACQUER, UiPalette.INDIGO]
const SEALS: Array[String] = ["赤", "青"]
const BAR_WIDTH: float = 560.0
const GOLD: Color = UiPalette.GOLD

var host: MatchHost

## The announcement on screen: { "text", "sub", "until" } (until is a step).
var announcement: Dictionary = {}
## Announcements waiting for their step: [{ "at", "text", "sub", "frames" }].
var _queued: Array[Dictionary] = []
var _root: Control
var _plates: Array[Label] = []
var _weapons: Array[Label] = []
var _tags: Array[Label] = []
var _hp: Array[HudBar] = []
var _posture: Array[HudBar] = []
var _pips: Array[HudPips] = []
var _badges: Array[HudBadge] = []
var _round_kanji: Label
var _round_label: Label
var _announce_label: Label
var _announce_sub: Label
var _hint: Label
var _lags: Array[HudLag] = [HudLag.new(), HudLag.new()]
var _states: Array[HudState] = [HudState.new(), HudState.new()]
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
		_lags[i].reset(HudState.of_fighter(host.fighter(i), 0).hp)
	_process(0.0)


## What side i's top bar shows now (for tests).
func side_state(i: int) -> HudState:
	return _states[i]


# ------------------------------------------------------------------ host signals

func _on_match_started(cfg: MatchConfig) -> void:
	visible = not host.attract
	announcement = {}
	_queued.clear()
	var me: int = _me()
	for i: int in 2:
		_lags[i].reset(1.0)
		var s: MatchSide = cfg.sides[i]
		_plates[i].text = s.display_name() + (" (You)" if i == me else "")
		_weapons[i].text = Moves.WEAPONS[s.weapon_id].name
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
			_round_kanji.text = HudState.round_kanji(n)
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
	var pulse: float = 0.5 - 0.5 * cos(_blink * TAU / LOW_PULSE)
	var blink_off: bool = fmod(_blink, POSTURE_BLINK) >= POSTURE_BLINK * 0.5
	for i: int in 2:
		var s: HudState = HudState.of_fighter(host.fighter(i), host.sim_match.wins[i])
		_states[i] = s
		_lags[i].step(s.hp, delta)
		_hp[i].value = s.hp
		_hp[i].lag = _lags[i].value
		_hp[i].brightness = 1.0 + LOW_PULSE_GAIN * pulse if s.low else 1.0
		_posture[i].value = s.posture
		var color: Color = POSTURE_COLORS[s.posture_level]
		if s.posture_level == HudState.Posture.FULL and blink_off:
			color.a = POSTURE_BLINK_ALPHA
		_posture[i].set_flat(color)
		_pips[i].lit = s.pips
		_badges[i].state = s.badge
		_tags[i].visible = s.disarmed
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

## Adds a bar to a side's column or row, kept to its width against the
## screen's edge.
func _add_bar(parent: Container, bar: HudBar, right: bool) -> void:
	bar.size_flags_horizontal = Control.SIZE_SHRINK_END if right else Control.SIZE_SHRINK_BEGIN
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)


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
		plate_row.add_theme_constant_override("separation", 10)
		box.add_child(plate_row)
		var seal: ColorRect = ColorRect.new()
		seal.name = "SealBox%d" % i
		seal.color = SEAL_COLORS[i]
		seal.custom_minimum_size = Vector2(26.0, 26.0)
		seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var seal_text: Label = UiTheme.label(SEALS[i], UiTheme.DISPLAY, 16)
		seal_text.name = "Seal%d" % i
		seal_text.set_anchors_preset(Control.PRESET_FULL_RECT)
		seal_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		seal.add_child(seal_text)
		var plate: Label = _label("Plate%d" % i, "Fighter", UiTheme.DISPLAY, 26)
		var weapon: Label = _label("Weapon%d" % i, "", UiTheme.EYEBROW, 15, 4)
		var tag: Label = _label("Tag%d" % i, "Disarmed", UiTheme.TAG, 0, 3)
		tag.visible = false
		var parts: Array[Control] = [seal, plate, weapon, tag]
		if right:
			parts.reverse()
		for part: Control in parts:
			plate_row.add_child(part)
		_plates.append(plate)
		_weapons.append(weapon)
		_tags.append(tag)

		var hp: HudBar = HudBar.new()
		hp.name = "Hp%d" % i
		hp.custom_minimum_size = Vector2(BAR_WIDTH, 18.0)
		hp.reversed = right
		hp.slant = 10.0
		hp.fill_bottom = UiPalette.HP_LO
		_add_bar(box, hp, right)
		_hp.append(hp)
		var posture: HudBar = HudBar.new()
		posture.name = "Posture%d" % i
		posture.custom_minimum_size = Vector2(BAR_WIDTH * 0.68, 8.0)
		posture.reversed = right
		posture.value = 0.0
		posture.lag_color = Color(0, 0, 0, 0)
		posture.edge_color = Color(UiPalette.GOLD, 0.4)
		var posture_row: HBoxContainer = HBoxContainer.new()
		posture_row.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
		posture_row.add_theme_constant_override("separation", 8)
		posture_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(posture_row)
		# the caption beside the bar, on its inner side
		var caption: Label = _label("PostureCaption%d" % i, "Posture", UiTheme.EYEBROW, 12, 3)
		if right:
			posture_row.add_child(caption)
			_add_bar(posture_row, posture, right)
		else:
			_add_bar(posture_row, posture, right)
			posture_row.add_child(caption)
		_posture.append(posture)

		var meta: HBoxContainer = HBoxContainer.new()
		meta.alignment = BoxContainer.ALIGNMENT_END if right else BoxContainer.ALIGNMENT_BEGIN
		meta.add_theme_constant_override("separation", 10)
		box.add_child(meta)
		var pips: HudPips = HudPips.new()
		pips.name = "Pips%d" % i
		var badge: HudBadge = HudBadge.new()
		badge.name_for_side(i)
		if right:
			meta.add_child(badge)
			meta.add_child(pips)
		else:
			meta.add_child(pips)
			meta.add_child(badge)
		_pips.append(pips)
		_badges.append(badge)

	var round_box: VBoxContainer = VBoxContainer.new()
	round_box.name = "Round"
	round_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	round_box.offset_left = -120.0
	round_box.offset_right = 120.0
	round_box.offset_top = 14.0
	round_box.add_theme_constant_override("separation", 0)
	round_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(round_box)
	_round_kanji = _label("RoundKanji", HudState.round_kanji(1), UiTheme.KANJI, 32, 6)
	_round_kanji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_round_kanji.add_theme_color_override("font_color", GOLD)
	round_box.add_child(_round_kanji)
	_round_label = _label("RoundLabel", "Round 1", UiTheme.EYEBROW, 14, 4)
	_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_box.add_child(_round_label)

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
