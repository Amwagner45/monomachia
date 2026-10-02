class_name SwingSampler
extends RefCounted
## Samples a swing's track at any moment (task 7.3), between its keys.
##
## - The grip travels on an arc around a pivot (PIVOTS): the grip's offset
##   from the pivot is splined as a direction, and its distance from the pivot
##   on its own, so the hands sweep round the body rather than cutting
##   straight across between keys.
## - The blade turns with the hand. Each key's blade and edge are carried
##   along the arc by the shortest turn from that key's direction from the
##   pivot to the sample's, and the two carried keys are blended. A blade
##   held at the same angle to the arm at both keys therefore turns exactly as
##   the arm swings, and is never splined on its own (the spike critique's
##   first fix: no propeller recoveries or wrist flips between keys).
## - Splines are Hermite, with Catmull-Rom tangents scaled by each key's ease,
##   so an ease-0 key holds still. Distances, coils, pole tweaks and pelvis
##   shifts never overshoot their keys: their tangents are capped at three
##   times the slopes either side (De Boor and Swartz), and are zero where a
##   key is a peak.
## - Before the first key the track holds it, and after the last key too.
## Everything is 64-bit with trig through JsMath, so the same keys give the
## same samples, bit for bit, on every machine.

## What each part's grip arcs around, (right, up, forward) metres from the
## feet: the middle of the shoulder line for hands (the rest skeletons'
## shoulders are at 1.418 m on the Rogue and 1.455 m on the Hunter, 5-7 cm
## behind the feet) and of the hips for feet (0.944 m and 0.971 m). Both sit
## on the spine's axis, so the torso and pelvis coil don't move them.
const PIVOTS: Dictionary[StringName, Array] = {
	&"right_hand": [0.0, 1.44, -0.06],
	&"left_hand": [0.0, 1.44, -0.06],
	&"right_foot": [0.0, 0.96, -0.045],
	&"left_foot": [0.0, 0.96, -0.045],
}
## The steepest an ease can make a capped spline: three times the slopes.
const MAX_SLOPE: float = 3.0


## Where the grips of `part` arc around.
static func pivot(part: StringName) -> V3:
	var p: Array = PIVOTS[part]
	return V3.make(p[0], p[1], p[2])


## The pose of the track `keys` (for `part`) at frame `t`, which may fall
## between frames.
static func sample(keys: Array[Swing.KeyPose], part: StringName, t: float) -> Swing.Sample:
	if keys.is_empty():
		return Swing.Sample.new()
	var last: int = keys.size() - 1
	if t <= float(keys[0].frame):
		return _held(keys[0])
	if t >= float(keys[last].frame):
		return _held(keys[last])
	var i: int = 0
	while float(keys[i + 1].frame) <= t:
		i += 1
	if t == float(keys[i].frame):
		return _held(keys[i])
	var h: float = float(keys[i + 1].frame - keys[i].frame)
	var s: float = (t - float(keys[i].frame)) / h
	if part == &"body":
		return _body(keys, i, s, h)
	return _limb(keys, part, i, s, h)


## A key's own pose.
static func _held(k: Swing.KeyPose) -> Swing.Sample:
	var out: Swing.Sample = Swing.Sample.new()
	out.grip = k.grip
	out.blade = k.blade
	out.edge = k.edge
	out.pole = k.pole
	out.torso = k.torso
	out.pelvis = k.pelvis
	out.pelvis_shift = k.pelvis_shift
	return out


static func _limb(keys: Array[Swing.KeyPose], part: StringName, i: int, s: float, h: float) -> Swing.Sample:
	var out: Swing.Sample = Swing.Sample.new()
	var a: Swing.KeyPose = keys[i]
	var b: Swing.KeyPose = keys[i + 1]
	var piv: V3 = pivot(part)
	var offsets: Array[V3] = []
	var radii: PackedFloat64Array = PackedFloat64Array()
	for k: Swing.KeyPose in keys:
		var v: V3 = V3.sub(k.grip, piv)
		offsets.append(v)
		radii.append(V3.length(v))
	# The grip: direction and distance from the pivot, splined apart.
	var along: V3 = _hermite_v3(offsets[i], offsets[i + 1], _tangent_v3(keys, offsets, i), _tangent_v3(keys, offsets, i + 1), s, h)
	var dir: V3 = V3.normalized(along)
	if V3.length(dir) == 0.0:
		dir = V3.normalized(offsets[i])
	var r: float = _hermite(radii[i], radii[i + 1], _capped(keys, radii, i), _capped(keys, radii, i + 1), s, h)
	out.grip = V3.add(piv, V3.scale(dir, r))
	# The blade: each key's frame carried along the arc to here, then blended.
	var qa: Quat64 = Quat64.mul(Quat64.from_to(offsets[i], dir), Quat64.from_axes(a.blade, a.edge))
	var qb: Quat64 = Quat64.mul(Quat64.from_to(offsets[i + 1], dir), Quat64.from_axes(b.blade, b.edge))
	var blend: float = _hermite(0.0, 1.0, minf(a.ease, MAX_SLOPE), minf(b.ease, MAX_SLOPE), s, 1.0)
	var q: Quat64 = Quat64.slerp(qa, qb, blend)
	out.blade = Quat64.rotate(q, V3.make(0.0, 1.0, 0.0))
	out.edge = Quat64.rotate(q, V3.make(1.0, 0.0, 0.0))
	out.pole = _capped_v3(keys, i, s, h, func(k: Swing.KeyPose) -> V3: return k.pole)
	return out


static func _body(keys: Array[Swing.KeyPose], i: int, s: float, h: float) -> Swing.Sample:
	var out: Swing.Sample = Swing.Sample.new()
	var torso: PackedFloat64Array = PackedFloat64Array()
	var pelvis: PackedFloat64Array = PackedFloat64Array()
	for k: Swing.KeyPose in keys:
		torso.append(k.torso)
		pelvis.append(k.pelvis)
	out.torso = _hermite(torso[i], torso[i + 1], _capped(keys, torso, i), _capped(keys, torso, i + 1), s, h)
	out.pelvis = _hermite(pelvis[i], pelvis[i + 1], _capped(keys, pelvis, i), _capped(keys, pelvis, i + 1), s, h)
	out.pelvis_shift = _capped_v3(keys, i, s, h, func(k: Swing.KeyPose) -> V3: return k.pelvis_shift)
	return out


## A vector field of the keys (picked by `field`), splined per component with
## capped tangents.
static func _capped_v3(keys: Array[Swing.KeyPose], i: int, s: float, h: float, field: Callable) -> V3:
	var xs: PackedFloat64Array = PackedFloat64Array()
	var ys: PackedFloat64Array = PackedFloat64Array()
	var zs: PackedFloat64Array = PackedFloat64Array()
	for k: Swing.KeyPose in keys:
		var v: V3 = field.call(k)
		xs.append(v.x)
		ys.append(v.y)
		zs.append(v.z)
	return V3.make(
			_hermite(xs[i], xs[i + 1], _capped(keys, xs, i), _capped(keys, xs, i + 1), s, h),
			_hermite(ys[i], ys[i + 1], _capped(keys, ys, i), _capped(keys, ys, i + 1), s, h),
			_hermite(zs[i], zs[i + 1], _capped(keys, zs, i), _capped(keys, zs, i + 1), s, h))


## The Catmull-Rom tangent (per frame) of `values` at key j, scaled by its ease.
static func _tangent_v3(keys: Array[Swing.KeyPose], values: Array[V3], j: int) -> V3:
	var j0: int = maxi(j - 1, 0)
	var j1: int = mini(j + 1, keys.size() - 1)
	var slope: V3 = V3.scale(V3.sub(values[j1], values[j0]), 1.0 / float(keys[j1].frame - keys[j0].frame))
	return V3.scale(slope, keys[j].ease)


## The tangent (per frame) of `values` at key j: Catmull-Rom scaled by the
## key's ease, zero at a peak or a dip, and at most MAX_SLOPE times the slope
## to either neighbour, so no stretch between two keys leaves their range.
static func _capped(keys: Array[Swing.KeyPose], values: PackedFloat64Array, j: int) -> float:
	var last: int = keys.size() - 1
	var left: float = (values[j] - values[j - 1]) / float(keys[j].frame - keys[j - 1].frame) if j > 0 else NAN
	var right: float = (values[j + 1] - values[j]) / float(keys[j + 1].frame - keys[j].frame) if j < last else NAN
	var m: float
	if j == 0:
		m = right
	elif j == last:
		m = left
	elif left * right <= 0.0:
		return 0.0
	else:
		m = (values[j + 1] - values[j - 1]) / float(keys[j + 1].frame - keys[j - 1].frame)
	m *= keys[j].ease
	var cap: float = INF
	if j > 0:
		cap = minf(cap, MAX_SLOPE * absf(left))
	if j < last:
		cap = minf(cap, MAX_SLOPE * absf(right))
	return clampf(m, -cap, cap)


## The cubic Hermite from y0 to y1 over a stretch of h frames, at s in [0, 1],
## with tangents m0 and m1 per frame.
static func _hermite(y0: float, y1: float, m0: float, m1: float, s: float, h: float) -> float:
	var s2: float = s * s
	var s3: float = s2 * s
	return (2.0 * s3 - 3.0 * s2 + 1.0) * y0 + (s3 - 2.0 * s2 + s) * h * m0 + (3.0 * s2 - 2.0 * s3) * y1 + (s3 - s2) * h * m1


static func _hermite_v3(p0: V3, p1: V3, m0: V3, m1: V3, s: float, h: float) -> V3:
	return V3.make(
			_hermite(p0.x, p1.x, m0.x, m1.x, s, h),
			_hermite(p0.y, p1.y, m0.y, m1.y, s, h),
			_hermite(p0.z, p1.z, m0.z, m1.z, s, h))
