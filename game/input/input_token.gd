class_name InputToken
extends RefCounted
## One physical input written as a short string, the unit of a binding.
## Port of the token strings in src/input/bindings.ts, with Godot's codes:
##
##   "k:<physical keycode>"   a key by its position on a US QWERTY keyboard (k:87 = W)
##   "m:<mouse button>"       MouseButton: 1 left, 2 right, 3 middle, 8 and 9 the side buttons
##   "b:<joypad button>"      JoyButton in the SDL layout (b:0 = bottom face button, b:10 = right shoulder)
##   "a:<joypad axis><+|->"   JoyAxis and direction (a:1- = left stick up, a:5+ = right trigger)
##
## Web to Godot: web buttons b4/b5 (L1/R1) are b:9/b:10, b8/b9 (Back/Start) are
## b:4/b:6, b10/b11 (stick clicks) are b:7/b:8, the D-pad b12-b15 is b:11-b:14,
## and the triggers b6/b7 are the axes a:4+ and a:5+. Mouse 0/1/2 (left, middle,
## right) are m:1/m:3/m:2.

const KEY: String = "k"
const MOUSE: String = "m"
const JOY_BUTTON: String = "b"
const JOY_AXIS: String = "a"


static func key(physical_keycode: int) -> String:
	return "k:%d" % physical_keycode


static func mouse(button: int) -> String:
	return "m:%d" % button


static func joy_button(button: int) -> String:
	return "b:%d" % button


## positive: true for the + direction (right, down, trigger pulled).
static func joy_axis(axis: int, positive: bool) -> String:
	return "a:%d%s" % [axis, "+" if positive else "-"]


## "k", "m", "b", "a", or "" when the token is malformed.
static func kind(token: String) -> String:
	if token.length() < 3 or token[1] != ":":
		return ""
	var k: String = token[0]
	if k == KEY or k == MOUSE or k == JOY_BUTTON or k == JOY_AXIS:
		return k
	return ""


## The keycode, mouse button, joypad button or joypad axis.
static func code(token: String) -> int:
	if kind(token) == JOY_AXIS:
		return token.substr(2, token.length() - 3).to_int()
	return token.substr(2).to_int()


## +1.0 or -1.0 for an axis token.
static func axis_sign(token: String) -> float:
	return -1.0 if token.ends_with("-") else 1.0


static func is_valid(token: String) -> bool:
	var k: String = kind(token)
	if k == "":
		return false
	if k == JOY_AXIS:
		var body: String = token.substr(2, token.length() - 3)
		var dir: String = token[token.length() - 1]
		return body.is_valid_int() and body.to_int() >= 0 and (dir == "+" or dir == "-")
	var rest: String = token.substr(2)
	return rest.is_valid_int() and rest.to_int() >= 0


## Keyboard and mouse tokens belong on the keyboard-and-mouse tab.
static func is_keyboard_or_mouse(token: String) -> bool:
	var k: String = kind(token)
	return k == KEY or k == MOUSE


## Joypad button and axis tokens belong on the controller tab.
static func is_joypad(token: String) -> bool:
	var k: String = kind(token)
	return k == JOY_BUTTON or k == JOY_AXIS


static func is_axis(token: String) -> bool:
	return kind(token) == JOY_AXIS


## L2/R2 (LT/RT): an axis that works as a button past a threshold.
static func is_trigger(token: String) -> bool:
	if not is_axis(token):
		return false
	var a: int = code(token)
	return a == JOY_AXIS_TRIGGER_LEFT or a == JOY_AXIS_TRIGGER_RIGHT


## A stick direction (any axis that is not a trigger).
static func is_stick(token: String) -> bool:
	return is_axis(token) and not is_trigger(token)
