class_name TitleScreen
extends Control
## The title over the live duel behind it: the name, a line, and "press any
## key or button". Any key, mouse button or controller button goes on.
## Keys and buttons are taken in _unhandled_input() (never in _input(), so the
## InputFeed sees them too); a click lands on the screen itself.

signal proceed

var _prompt: Label
var _time: float = 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.offset_bottom = -110.0
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	column.add_child(MenuScreen.make_label("MONOMACHIA", 104, MenuScreen.TEXT_COLOR, 14))
	column.add_child(MenuScreen.make_label("Single combat", 30, MenuScreen.ACCENT.lightened(0.25), 6))
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0.0, 40.0)
	column.add_child(gap)
	_prompt = MenuScreen.make_label("Press any key or button", 26, MenuScreen.MUTED, 6)
	column.add_child(_prompt)


func open() -> void:
	visible = true
	_time = 0.0


func close() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_prompt.modulate.a = 0.55 + 0.45 * cos(_time * 3.0)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree():
		return
	if _goes_on(event):
		get_viewport().set_input_as_handled()
		proceed.emit()


## A click on the title (it stops the mouse, so clicks end here).
func _gui_input(event: InputEvent) -> void:
	if visible and event is InputEventMouseButton and _goes_on(event):
		accept_event()
		proceed.emit()


static func _goes_on(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).pressed and not (event as InputEventKey).echo
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	return false
