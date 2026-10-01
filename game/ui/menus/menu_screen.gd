class_name MenuScreen
extends Control
## A plain full-screen menu panel for the playable skeleton (task 22 brings
## the real menus): a title, some text and a column of buttons, centred over
## the live duel behind it.
##
## Navigable with the keyboard (arrows or W/S, Enter or Space, Esc or
## Backspace for back), the mouse, and a controller (D-pad or left stick, A to
## choose, B for back). Godot's ui_* actions cover the arrows, Enter and the
## stick; this adds W/S and the controller's A and B buttons, which the
## default ui_accept and ui_cancel lack.
##
## The menus act in _unhandled_input(), after the GUI, and never take an
## event in _input(): the InputFeed (GameServices) sees every event in
## _input(), and a node that takes one there hides it from the feed.

## Back (Esc, Backspace, controller B) was pressed while the screen is open.
signal back_requested

const PANEL_COLOR: Color = Color(0.04, 0.03, 0.05, 0.82)
const ACCENT: Color = Color(0.85, 0.24, 0.18)
const TEXT_COLOR: Color = Color(0.95, 0.92, 0.86)
const MUTED: Color = Color(0.75, 0.72, 0.68)

var panel: PanelContainer
var box: VBoxContainer
var buttons: Array[Button] = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	panel = PanelContainer.new()
	panel.name = "Panel"
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = ACCENT
	style.border_width_top = 3
	style.content_margin_left = 48.0
	style.content_margin_right = 48.0
	style.content_margin_top = 36.0
	style.content_margin_bottom = 36.0
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)


static func make_label(text: String, font_size: int, color: Color = TEXT_COLOR, outline: int = 0) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", outline)
	return l


func add_label(text: String, font_size: int = 22, color: Color = TEXT_COLOR) -> Label:
	var l: Label = make_label(text, font_size, color)
	box.add_child(l)
	return l


## A button with an optional smaller line under its label.
func add_button(text: String, sub: String, on_pressed: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text if sub == "" else "%s\n%s" % [text, sub]
	b.custom_minimum_size = Vector2(380.0, 64.0 if sub != "" else 48.0)
	b.add_theme_font_size_override("font_size", 24)
	b.focus_mode = Control.FOCUS_ALL
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.06)
	var focus: StyleBoxFlat = StyleBoxFlat.new()
	focus.bg_color = Color(ACCENT, 0.55)
	focus.border_color = Color(1.0, 0.85, 0.6)
	focus.border_width_left = 4
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", focus)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("pressed", focus)
	b.pressed.connect(on_pressed)
	b.mouse_entered.connect(b.grab_focus)
	box.add_child(b)
	buttons.append(b)
	_link_focus()
	return b


## Shows the screen and focuses its first button.
func open() -> void:
	visible = true
	if not buttons.is_empty() and is_inside_tree():
		buttons[0].grab_focus.call_deferred()


func close() -> void:
	visible = false


func focused_button() -> Button:
	if not is_inside_tree():
		return null
	var f: Control = get_viewport().gui_get_focus_owner()
	return f as Button if f is Button and buttons.has(f) else null


func _link_focus() -> void:
	for i: int in buttons.size():
		var b: Button = buttons[i]
		b.focus_neighbor_top = b.get_path_to(buttons[(i - 1 + buttons.size()) % buttons.size()])
		b.focus_neighbor_bottom = b.get_path_to(buttons[(i + 1) % buttons.size()])


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	if _is_back(event):
		get_viewport().set_input_as_handled()
		back_requested.emit()
		return
	if event is InputEventJoypadButton:
		var jb: InputEventJoypadButton = event
		if jb.pressed and jb.button_index == JOY_BUTTON_A:
			var b: Button = focused_button()
			if b != null:
				get_viewport().set_input_as_handled()
				b.pressed.emit()
			return
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and (k.physical_keycode == KEY_W or k.physical_keycode == KEY_S):
			var b: Button = focused_button()
			if b == null and not buttons.is_empty():
				buttons[0].grab_focus()
			elif b != null:
				var i: int = buttons.find(b)
				var step: int = -1 if k.physical_keycode == KEY_W else 1
				buttons[(i + step + buttons.size()) % buttons.size()].grab_focus()
			get_viewport().set_input_as_handled()
	# a focus lost to a click outside comes back on the next move
	if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		if focused_button() == null and not buttons.is_empty():
			buttons[0].grab_focus()
			get_viewport().set_input_as_handled()


static func _is_back(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		return true
	if event is InputEventKey:
		var k: InputEventKey = event
		return k.pressed and not k.echo and k.physical_keycode == KEY_BACKSPACE
	if event is InputEventJoypadButton:
		var jb: InputEventJoypadButton = event
		return jb.pressed and jb.button_index == JOY_BUTTON_B
	return false
