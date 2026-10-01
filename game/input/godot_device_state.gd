class_name GodotDeviceState
extends DeviceState
## The real device state: reads Godot's Input singleton and forwards its
## joy_connection_changed signal.


func _init() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func is_key_pressed(physical_keycode: int) -> bool:
	return Input.is_physical_key_pressed(physical_keycode)


func is_mouse_pressed(button: int) -> bool:
	return Input.is_mouse_button_pressed(button)


func joy_button_pressed(device: int, button: int) -> bool:
	return Input.is_joy_button_pressed(device, button)


func joy_axis(device: int, axis: int) -> float:
	return Input.get_joy_axis(device, axis)


func connected_joypads() -> Array[int]:
	var pads: Array[int] = Input.get_connected_joypads()
	pads.sort()
	return pads


func joy_name(device: int) -> String:
	return Input.get_joy_name(device)


func joy_info(device: int) -> Dictionary:
	return Input.get_joy_info(device)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	joy_connection_changed.emit(device, connected)
