class_name ClipTiming
extends RefCounted
## A clip (or a chain of clips) retimed onto rules frames by its markers
## (ClipManifest.MARKERS, in source frames) at a speed between 1.0 and 2.0
## times its 30 fps: the wind-up start on frame 0, the contact start on the
## last startup frame (the first active frame sweeps from it), the contact
## end on the last active frame and the settle on the move's last frame, the
## clip running at an even speed between them. The bake (SwingBake) samples
## the clip on these frames, and its startup, active and recovery are the
## move's frame data; the clip director plays the clip on the same frames.

const RULES_FPS: float = 60.0
const MIN_SPEED: float = 1.0
const MAX_SPEED: float = 2.0

var speed: float = 1.0
var startup: int = 0
var active: int = 0
var recovery: int = 0
## The rules frames of the four markers: 0, startup, startup + active and
## the last frame.
var frames: PackedInt32Array = PackedInt32Array()
## The four markers, in source frames (ClipManifest.MARKERS' order).
var marks: PackedFloat64Array = PackedFloat64Array()


## The timing of a clip with `markers` (source frames by name) at `speed`:
## null, with an error per mistake, when a marker is missing or out of order
## or the speed is outside 1.0-2.0. Each stretch between markers takes at
## least one rules frame.
static func make(markers: Dictionary, p_speed: float, errors: Array[String]) -> ClipTiming:
	var before: int = errors.size()
	if is_nan(p_speed) or p_speed < MIN_SPEED or p_speed > MAX_SPEED:
		errors.append("speed %s is outside %.1f-%.1f" % [p_speed, MIN_SPEED, MAX_SPEED])
	var m: PackedFloat64Array = PackedFloat64Array()
	for name: String in ClipManifest.MARKERS:
		var v: Variant = markers.get(name)
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			errors.append("no %s marker" % name)
			continue
		if not m.is_empty() and float(v) <= m[-1]:
			errors.append("the %s marker (%s) must come after the %s marker (%s)"
					% [name, frame_text(float(v)), ClipManifest.MARKERS[m.size() - 1], frame_text(m[-1])])
		m.append(float(v))
	if errors.size() != before:
		return null
	var t: ClipTiming = ClipTiming.new()
	t.speed = p_speed
	t.marks = m
	var per: float = RULES_FPS / float(ClipManifest.SOURCE_FPS) / p_speed
	var f: PackedInt32Array = PackedInt32Array([0])
	for i: int in range(1, 4):
		f.append(maxi(f[-1] + 1, roundi((m[i] - m[0]) * per)))
	t.frames = f
	t.startup = f[1]
	t.active = f[2] - f[1]
	t.recovery = f[3] - f[2]
	return t


## A source frame as it reads: whole frames without a decimal point.
static func frame_text(x: float) -> String:
	return str(int(x)) if x == floorf(x) else str(x)


func total() -> int:
	return startup + active + recovery


## The clip's time (seconds from its start) at rules frame `f`, which may
## fall between frames: even between the markers' frames, the wind-up start
## before frame 0 and the settle after the last.
func clip_time(f: float) -> float:
	var source: float = marks[0]
	if f >= float(frames[3]):
		source = marks[3]
	elif f > 0.0:
		var j: int = 0
		while f > float(frames[j + 1]):
			j += 1
		var s: float = (f - float(frames[j])) / float(frames[j + 1] - frames[j])
		source = lerpf(marks[j], marks[j + 1], s)
	return source / float(ClipManifest.SOURCE_FPS)
