class_name ControlsScreen
extends MenuScreen
## The Controls screen's binding table (port of showControls() in
## src/ui/menus.ts): Keyboard-and-mouse and Controller tabs, opening on the
## tab of the last device used; on the controller tab a status line naming the
## connected controller and its button style; the 13 actions with two slots
## each, named in that style (ControlsTable); and Reset to defaults and, on the
## controller tab, the fight-stick layout, each saved at once. Back returns to
## the page that opened it.
##
## Choosing a slot emits slot_chosen; rebinding capture (22.11) listens to it.
## The profile row (pick, rename, new, delete) comes with 22.12: until then
## the table shows the active profile, named over it.
##
## The screen acts on a ControlProfiles saved to a path and an InputDevices:
## GameServices' by default, saved to the player's file
## (GameSettings.save_path_for_run, so a test run never writes it); tests hand
## it their own.

## A slot was chosen (keys, a controller or a click).
signal slot_chosen(tab: String, action: String, slot: int)
## A profile's bindings changed (and were saved).
signal profiles_changed

const TABS: Array[String] = [ControlProfile.KB, ControlProfile.PAD]
const TAB_NAMES: Array[String] = ["Keyboard & mouse", "Controller"]
## A slot button's least height (px); the theme's padding makes it about 50.
const SLOT_HEIGHT: float = 34.0

var profiles: ControlProfiles
var save_path: String
var input: InputDevices
## ControlProfile.KB or PAD.
var tab: String = ControlProfile.KB
var profile_label: Label
var tabs: OptionRow
var status: Label
var table: GridContainer
var scroll: ScrollContainer
## action -> [slot 0 button, slot 1 button]
var slot_buttons: Dictionary = {}
var reset_button: Button
var fight_stick_button: Button


func _init(p_profiles: ControlProfiles = null, p_save_path: String = "", p_input: InputDevices = null) -> void:
	super()
	profiles = p_profiles if p_profiles != null else GameServices.profiles
	save_path = p_save_path if p_save_path != "" else GameSettings.save_path_for_run(ControlProfiles.PATH)
	input = p_input if p_input != null else GameServices.input
	add_label("Saved on this computer", UiTheme.EYEBROW, 15)
	add_heading("Controls")
	profile_label = add_label("", UiTheme.MUTED, 20)
	tabs = add_options("Device", TAB_NAMES, 0, _on_tab)
	status = add_label("", UiTheme.MUTED, 17)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(760.0, 0.0)
	_build_table()
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	reset_button = _action_button(row, "Reset to defaults", _on_reset)
	fight_stick_button = _action_button(row, "Fight stick layout", _on_fight_stick)
	input.state.joy_connection_changed.connect(_on_joy_connection_changed)
	refresh()


func _build_table() -> void:
	scroll = ScrollContainer.new()
	scroll.name = "Table"
	scroll.custom_minimum_size = Vector2(760.0, 400.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)
	table = GridContainer.new()
	table.columns = 3
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 12)
	table.add_theme_constant_override("v_separation", 4)
	scroll.add_child(table)
	for action: String in Bindings.ACTIONS:
		var names: VBoxContainer = VBoxContainer.new()
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_theme_constant_override("separation", 0)
		names.alignment = BoxContainer.ALIGNMENT_CENTER
		var label: Label = UiTheme.label(Bindings.ACTION_LABELS[action], &"", 18)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		names.add_child(label)
		if Bindings.ACTION_HINTS.has(action):
			var hint: Label = UiTheme.label(Bindings.ACTION_HINTS[action], UiTheme.MUTED, 13)
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			names.add_child(hint)
		table.add_child(names)
		var pair: Array[Button] = []
		for slot: int in Bindings.SLOTS:
			var b: Button = Button.new()
			b.name = "%s_%d" % [action, slot]
			b.custom_minimum_size = Vector2(200.0, SLOT_HEIGHT)
			b.add_theme_font_size_override(&"font_size", 18)
			b.clip_text = true
			b.tooltip_text = "%s binding %d" % [Bindings.ACTION_LABELS[action], slot + 1]
			b.pressed.connect(func() -> void: slot_chosen.emit(tab, action, slot))
			table.add_child(b)
			add_item(b)
			pair.append(b)
		slot_buttons[action] = pair


func _action_button(row: HBoxContainer, text: String, on_pressed: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0.0, 48.0)
	b.pressed.connect(on_pressed)
	row.add_child(b)
	add_item(b)
	return b


## Opens on the tab of the last device used.
func open() -> void:
	tab = ControlsTable.opening_tab(input)
	refresh()
	super()


## Shows the active profile's bindings on the current tab, named in the
## button style of the connected controller, and the line over the table.
func refresh() -> void:
	tabs.set_index(TABS.find(tab))
	var profile: ControlProfile = profiles.active_profile()
	profile_label.text = "Profile · %s" % profile.name
	var on_pad: bool = tab == ControlProfile.PAD
	status.text = ControlsTable.status_line(input) if on_pad else ControlsTable.KB_NOTE
	var style: int = ControlsTable.style(input) if on_pad else PadStyle.GENERIC
	for r: ControlsTable.Row in ControlsTable.rows(profile, tab, style):
		var pair: Array[Button] = []
		pair.assign(slot_buttons[r.action])
		for slot: int in pair.size():
			pair[slot].text = r.slots[slot]
	fight_stick_button.visible = on_pad


## Up and down on the table keep to the slot's column, a row at a time (left
## and right step between the two slots); past the first row up goes to the
## tabs, past the last down to Reset.
func act(cmd: MenuNav.Cmd) -> void:
	var at: Vector2i = _slot_of(focused_item())
	if at.x < 0 or (cmd != MenuNav.Cmd.UP and cmd != MenuNav.Cmd.DOWN):
		super(cmd)
		return
	var row: int = at.x + (-1 if cmd == MenuNav.Cmd.UP else 1)
	if row < 0:
		tabs.grab_focus()
	elif row >= Bindings.ACTIONS.size():
		reset_button.grab_focus()
	else:
		(slot_buttons[Bindings.ACTIONS[row]][at.y] as Button).grab_focus()


## (row, slot) of a slot button, or (-1, -1).
func _slot_of(c: Control) -> Vector2i:
	if not (c is Button):
		return Vector2i(-1, -1)
	for row: int in Bindings.ACTIONS.size():
		var slot: int = (slot_buttons[Bindings.ACTIONS[row]] as Array).find(c)
		if slot >= 0:
			return Vector2i(row, slot)
	return Vector2i(-1, -1)


## A slot's button text, for tests and the capture (22.11).
func slot_text(action: String, slot: int) -> String:
	return (slot_buttons[action][slot] as Button).text


func _on_tab(index: int) -> void:
	tab = TABS[index]
	refresh()


func _on_reset() -> void:
	profiles.active_profile().reset_tab(tab)
	_save()


func _on_fight_stick() -> void:
	profiles.active_profile().use_fight_stick_layout()
	_save()


func _save() -> void:
	profiles.save(save_path)
	refresh()
	profiles_changed.emit()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and input != null and input.state != null:
		if input.state.joy_connection_changed.is_connected(_on_joy_connection_changed):
			input.state.joy_connection_changed.disconnect(_on_joy_connection_changed)
