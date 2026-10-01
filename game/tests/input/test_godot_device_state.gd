extends GutTest
## The real device state, driven through Godot's Input singleton: keys by
## physical position, mouse buttons, controller buttons and axes, and the
## connection signal (no hardware needed).

const PAD: int = 7

var input: InputDevices
var profile: ControlProfile


func before_each() -> void:
	input = InputDevices.new()
	profile = ControlProfile.create()


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _send_axis(axis: int, value: float) -> void:
	var e: InputEventJoypadMotion = InputEventJoypadMotion.new()
	e.device = PAD
	e.axis = axis as JoyAxis
	e.axis_value = value
	_send(e)


func _send_key(code: int, pressed: bool) -> void:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code as Key
	e.pressed = pressed
	_send(e)


func _send_button(button: int, pressed: bool) -> void:
	var e: InputEventJoypadButton = InputEventJoypadButton.new()
	e.device = PAD
	e.button_index = button as JoyButton
	e.pressed = pressed
	_send(e)


func test_reads_godot_input_by_default() -> void:
	assert_true(input.state is GodotDeviceState)
	input.set_single_player(profile)
	_send_key(KEY_J, true)
	_send_key(KEY_W, true)
	var raw: RawInput = input.sample(0)
	_send_key(KEY_J, false)
	_send_key(KEY_W, false)
	assert_eq(raw.buttons, Btn.bit(Btn.LIGHT))
	assert_eq(raw.my, 1.0)
	assert_eq(input.sample(0).buttons, 0, "released")


func test_reads_the_mouse() -> void:
	input.set_single_player(profile)
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	_send(e)
	var buttons: int = input.sample(0).buttons
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.pressed = false
	_send(up)
	assert_eq(buttons, Btn.bit(Btn.HEAVY))


func test_reads_controller_buttons_and_axes() -> void:
	var state: DeviceState = input.state
	_send_button(JOY_BUTTON_A, true)
	_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.8)
	var a: bool = state.joy_button_pressed(PAD, JOY_BUTTON_A)
	var rt: float = state.joy_axis(PAD, JOY_AXIS_TRIGGER_RIGHT)
	_send_button(JOY_BUTTON_A, false)
	_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	assert_true(a)
	assert_almost_eq(rt, 0.8, 1e-6)
	assert_false(state.joy_button_pressed(PAD, JOY_BUTTON_A))


func test_forwards_controller_connections() -> void:
	var heard: Array = []
	input.state.joy_connection_changed.connect(func(device: int, connected: bool) -> void: heard.append([device, connected]))
	Input.joy_connection_changed.emit(PAD, true)
	Input.joy_connection_changed.emit(PAD, false)
	assert_eq(heard, [[PAD, true], [PAD, false]])
