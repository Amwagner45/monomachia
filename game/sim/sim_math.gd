class_name SimMath
extends RefCounted
## Port of src/sim/math.ts.
##
## Small math helpers for the simulation (no three.js dependency so it runs in tests).
##
## Port notes:
## - Vec2 and Vec3 live in v2.gd and v3.gd; v2() and v3() are V2.make() and V3.make().
## - TS dist2 and yawTo accept Vec2 | Vec3; every caller passes a Vec3, so here
##   they take V3.
## - Math.sin, Math.cos and Math.atan2 are JsMath.sin, JsMath.cos and
##   JsMath.atan2: V8's exact results (see js_math.gd). Math.sqrt is sqrt.
## - js_round() is the JS Math.round, which GDScript's round() is not (it rounds
##   halves away from zero; JS rounds them toward +infinity).


static func clamp(v: float, lo: float, hi: float) -> float:
	return lo if v < lo else (hi if v > hi else v)


static func lerp(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


static func sign(v: float) -> float:
	return -1.0 if v < 0.0 else 1.0


static func len2(x: float, z: float) -> float:
	return sqrt(x * x + z * z)


static func dist2(a: V3, b: V3) -> float:
	return len2(b.x - a.x, b.z - a.z)


static func norm2(x: float, z: float) -> V2:
	var l: float = sqrt(x * x + z * z)
	return V2.make(x / l, z / l) if l > 1e-9 else V2.make(0.0, 1.0)


## Forward unit vector for a yaw angle. yaw=0 faces +Z; positive yaw turns toward +X.
static func fwd(yaw: float) -> V2:
	return V2.make(JsMath.sin(yaw), JsMath.cos(yaw))


## Right-hand unit vector for a yaw angle (fighter's own right side).
static func right(yaw: float) -> V2:
	# right = forward x up = (-fz, fx)
	return V2.make(-JsMath.cos(yaw), JsMath.sin(yaw))


static func yaw_to(from: V3, to: V3) -> float:
	return JsMath.atan2(to.x - from.x, to.z - from.z)


static func wrap_angle(a: float) -> float:
	while a > PI:
		a -= PI * 2.0
	while a < -PI:
		a += PI * 2.0
	return a


## Rotate `current` toward `target` by at most `max_step` radians.
static func turn_toward(current: float, target: float, max_step: float) -> float:
	var d: float = wrap_angle(target - current)
	if absf(d) <= max_step:
		return target
	return wrap_angle(current + signf(d) * max_step)


static func angle_between(yaw: float, dir_yaw: float) -> float:
	return absf(wrap_angle(dir_yaw - yaw))


const DEG: float = PI / 180.0


static func ease_out_cubic(t: float) -> float:
	var u: float = 1.0 - t
	return 1.0 - u * u * u


static func ease_in_out(t: float) -> float:
	return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0


## JS Math.round: the nearest integer, halves toward +infinity
## (js_round(-0.5) == 0, js_round(2.5) == 3). Not in math.ts; the port uses it
## wherever the TS calls Math.round. Computed as floor plus a fraction test
## rather than floor(x + 0.5), which is wrong for 0.49999999999999994 and for
## odd integers above 2^52.
static func js_round(x: float) -> int:
	var r: float = floorf(x)
	return int(r + 1.0) if x - r >= 0.5 else int(r)
