class_name RebindCapture
extends RefCounted
## Waits for the input to put in one binding slot on the Controls screen.
## Port of startCapture() and its capture rules in src/input/devices.ts.
##
## Keyboard-and-mouse tab: the next key or mouse button press is bound.
## Controller tab: waits until every controller button (and trigger) is
## released, records where the axes rest, then binds the first button pressed
## or the first axis that moves more than 0.6 from its rest position (so a
## drifting stick or a trigger that rests at -1 is not bound by accident).
## On both tabs Esc cancels, and Backspace or Delete clears the slot.
##
## Usage from the Controls screen:
##   capture = RebindCapture.new(ControlProfile.KB, input.state)
##   # in _input(event), while capture.is_listening():
##   capture.feed(event); get_viewport().set_input_as_handled()
##   # each frame (controller tab): capture.poll()
##   # when it is no longer listening:
##   if capture.apply_to(profile, action, slot): profiles.save()

enum Result { LISTENING, BOUND, CLEARED, CANCELLED }

## An axis must move this far from rest to be bound.
const AXIS_MOVE: float = 0.6
## A trigger past this counts as held while waiting for the release.
const TRIGGER_HELD: float = 0.5

## ControlProfile.KB or ControlProfile.PAD.
var tab: String
var result: Result = Result.LISTENING
## The captured token when result is BOUND.
var token: String = ""

var _state: DeviceState
var _armed: bool = false
## device id -> PackedFloat64Array of axis rest values
var _rest: Dictionary = {}


func _init(p_tab: String, p_state: DeviceState) -> void:
	tab = p_tab
	_state = p_state
	if tab == ControlProfile.PAD:
		_try_arm()


func is_listening() -> bool:
	return result == Result.LISTENING


## Controller tab: true once every button was released and the rest positions
## are recorded (the screen can show "Press a button…" from then on).
func is_armed() -> bool:
	return _armed


func cancel() -> void:
	if is_listening():
		_finish(Result.CANCELLED, "")


## Call each frame on the controller tab: arms the capture once everything is
## released, even when no event arrives.
func poll() -> Result:
	if is_listening() and tab == ControlProfile.PAD and not _armed:
		_try_arm()
	return result


## Hands one input event to the capture; returns the result so far.
func feed(event: InputEvent) -> Result:
	if not is_listening():
		return result
	if event is InputEventKey:
		_feed_key(event as InputEventKey)
		return result
	if tab == ControlProfile.KB:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event
			if mb.pressed and not _is_wheel(mb.button_index):
				_finish(Result.BOUND, InputToken.mouse(mb.button_index))
		return result
	if not _armed:
		_try_arm()
		return result
	if event is InputEventJoypadButton:
		var jb: InputEventJoypadButton = event
		if jb.pressed:
			_finish(Result.BOUND, InputToken.joy_button(jb.button_index))
	elif event is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = event
		var d: float = jm.axis_value - _rest_of(jm.device, jm.axis)
		if absf(d) > AXIS_MOVE:
			_finish(Result.BOUND, InputToken.joy_axis(jm.axis, d > 0.0))
	return result


## Writes the result into a profile: BOUND binds the token to the slot (and
## removes it from any other action on the tab), CLEARED empties the slot.
## Returns whether the profile changed.
func apply_to(profile: ControlProfile, action: String, slot: int) -> bool:
	match result:
		Result.BOUND:
			profile.bind(tab, action, slot, token)
			return true
		Result.CLEARED:
			profile.clear_slot(tab, action, slot)
			return true
	return false


func _feed_key(key: InputEventKey) -> void:
	if not key.pressed or key.echo:
		return
	var code: int = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
	if code == KEY_NONE:
		return
	if code == KEY_ESCAPE:
		_finish(Result.CANCELLED, "")
	elif code == KEY_BACKSPACE or code == KEY_DELETE:
		_finish(Result.CLEARED, "")
	elif tab == ControlProfile.KB:
		_finish(Result.BOUND, InputToken.key(code))


func _try_arm() -> void:
	var pads: Array[int] = _state.connected_joypads()
	for device: int in pads:
		for button: int in JOY_BUTTON_SDL_MAX:
			if _state.joy_button_pressed(device, button):
				return
		if _state.joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > TRIGGER_HELD:
			return
		if _state.joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > TRIGGER_HELD:
			return
	_armed = true
	_rest.clear()
	for device: int in pads:
		var axes: PackedFloat64Array = []
		for axis: int in JOY_AXIS_SDL_MAX:
			axes.append(_state.joy_axis(device, axis))
		_rest[device] = axes


func _rest_of(device: int, axis: int) -> float:
	if not _rest.has(device):
		return 0.0
	var axes: PackedFloat64Array = _rest[device]
	return axes[axis] if axis >= 0 and axis < axes.size() else 0.0


func _finish(p_result: Result, p_token: String) -> void:
	result = p_result
	token = p_token


static func _is_wheel(button: int) -> bool:
	return button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN \
		or button == MOUSE_BUTTON_WHEEL_LEFT or button == MOUSE_BUTTON_WHEEL_RIGHT
