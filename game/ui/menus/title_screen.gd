class_name TitleScreen
extends Control
## The title over the live duel behind it: the name, a line, and "press any
## key or button". Any key, mouse button or controller button goes on.

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


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var go: bool = false
	if event is InputEventKey:
		go = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	elif event is InputEventMouseButton:
		go = (event as InputEventMouseButton).pressed
	elif event is InputEventJoypadButton:
		go = (event as InputEventJoypadButton).pressed
	if go:
		get_viewport().set_input_as_handled()
		proceed.emit()
