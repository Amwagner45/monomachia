class_name V3
extends RefCounted
## Port of the Vec3 interface in src/sim/math.ts: a position or velocity in
## metres, y up.
##
## Port note: 64-bit floats instead of Godot's Vector3, which is float32 and
## would drift from the TypeScript rules. Like the TS object literals it has
## reference semantics: assigning a V3 shares it, V3.make() makes a new one.

var x: float = 0.0
var y: float = 0.0
var z: float = 0.0


## v3(x = 0, y = 0, z = 0)
static func make(px: float = 0.0, py: float = 0.0, pz: float = 0.0) -> V3:
	var v: V3 = V3.new()
	v.x = px
	v.y = py
	v.z = pz
	return v


func _to_string() -> String:
	return "(%s, %s, %s)" % [x, y, z]
