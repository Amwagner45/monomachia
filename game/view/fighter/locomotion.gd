class_name Locomotion
extends RefCounted
## The legs under a fighter in the match: an AnimationTree on its model
## blending idle (the held weapon's hold clip), walk, jog and sprint by the
## rules' speed, advanced by the rules' clock. FighterView updates it every
## frame; it never changes the rules.
##
## - The blend is anchored on the rules' speeds: idle at rest, the walk at
##   WALK_SPEED (the walk clip's own pace), the jog at the fighter's running
##   speed and the sprint at its sprinting speed (both scaled by its weapon,
##   and when disarmed), each blending linearly into the next (weights()).
##   Walking while blocking (60% of the run) shows between the walk and the
##   jog until the guard shuffle (plan 14.9) takes it over.
## - Every clip plays from one shared step phase, so the feet stay in step
##   whatever the blend: at phase 0 the left foot is at mid-stance in every
##   clip, and at about 0.5 the right. The phase moves the blended stride per
##   cycle (stride()), so the planted foot keeps pace with the ground.
## - Each fighter's strides and mid-stances are measured from its own clips by
##   FootPhase, once per fighter.
## - The phase moves once per rules frame, by the speed after that frame
##   (ground_speed(): walking and running on the ground only, so a dodge, an
##   attack's lunge or a jump keeps the legs on the hold clip). In between, the
##   shown phase blends from the frame before by the host's alpha, as the
##   position does. The world's frame stands still in hit-stop and while
##   paused, and so do the legs.
## - The hold clip runs on the rules' clock, as before (the time is passed in).
##
## A KO's fall plays on the model's AnimationPlayer instead: the view stops
## updating the tree, and the player's pose stands.

## The moving clips, in blend order after idle.
const CLIPS: Array[StringName] = [&"Walk", &"Jog_Fwd", &"Sprint"]
## The tree's node for each, after the idle's (see _build()).
const NODES: Array[StringName] = [&"idle", &"walk", &"jog", &"sprint"]
## The speed (m/s) the walk is anchored at: the walk clip's own pace (FootPhase
## measures 0.93-0.97 m/s on the fighters; the spike's 0.98).
const WALK_SPEED: float = 0.98
## The fighter states in which the legs walk and run with the speed.
const MOVING_STATES: Array[StringName] = [&"free", &"step"]

## Each fighter's gaits (FighterLook id -> Array of FootPhase.Gait, in CLIPS
## order), measured once.
static var _measured: Dictionary[StringName, Array] = {}

var model: FighterModel
var tree: AnimationTree
## The fighter's gaits for CLIPS.
var gaits: Array[FootPhase.Gait] = []
## The shared step phase (0..1) after the last rules frame, and after the
## one before.
var phase: float = 0.0
var prev_phase: float = 0.0
## The ground speed (m/s) after the last rules frame, and after the one before.
var speed: float = 0.0
var prev_speed: float = 0.0
## The fighter's running and sprinting speeds, the jog's and sprint's anchors.
var run_speed: float = SimConst.MOVE_RUN_FORWARD
var sprint_speed: float = SimConst.MOVE_SPRINT
## What was shown last: the phase, and the weights of idle, walk, jog and
## sprint.
var shown_phase: float = 0.0
var shown: PackedFloat32Array = PackedFloat32Array([1.0, 0.0, 0.0, 0.0])

var _root: AnimationNodeBlendTree
## The rules frame the phase is at; -1 before the first update.
var _frame: int = -1
var _idle_clip: StringName = &""


func _init(p_model: FighterModel, fighter_id: StringName) -> void:
	model = p_model
	gaits = gaits_of(model, fighter_id)
	_build()


## The gaits of fighter `fighter_id` (measured on `p_model` the first time).
static func gaits_of(p_model: FighterModel, fighter_id: StringName) -> Array[FootPhase.Gait]:
	if not _measured.has(fighter_id):
		var measured: Array[FootPhase.Gait] = []
		for clip: StringName in CLIPS:
			measured.append(FootPhase.measure(p_model, clip))
		_measured[fighter_id] = measured
	var out: Array[FootPhase.Gait] = []
	out.assign(_measured[fighter_id])
	return out


## The weights of idle, walk, jog and sprint at `p_speed`: idle at rest, the
## walk at WALK_SPEED, the jog at `run` and the sprint at `sprint` (and past
## it), each blending linearly into the next.
static func weights(p_speed: float, run: float, sprint: float) -> PackedFloat32Array:
	var w: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var anchors: Array[float] = [0.0, WALK_SPEED, run, sprint]
	if p_speed <= 0.0:
		w[0] = 1.0
		return w
	for i: int in 3:
		if p_speed < anchors[i + 1]:
			var t: float = (p_speed - anchors[i]) / (anchors[i + 1] - anchors[i])
			w[i] = 1.0 - t
			w[i + 1] = t
			return w
	w[3] = 1.0
	return w


## How far the body travels per cycle at `p_speed`: the moving clips'
## strides blended by their weights (a walk's below the walk).
func stride(p_speed: float) -> float:
	var w: PackedFloat32Array = weights(maxf(p_speed, WALK_SPEED), run_speed, sprint_speed)
	var s: float = 0.0
	for i: int in 3:
		s += w[i + 1] * gaits[i].stride
	return s


## The speed the legs walk and run at: the rules' ground speed while the
## fighter walks or runs on the ground (MOVING_STATES), else 0.
static func ground_speed(f: Fighter) -> float:
	if not MOVING_STATES.has(f.state) or f.airborne():
		return 0.0
	return Vector2(f.vel.x, f.vel.z).length()


## Seconds into moving clip `index` (in CLIPS) at shared phase `p`.
func clip_time(index: int, p: float) -> float:
	var g: FootPhase.Gait = gaits[index]
	return fposmod(p + g.left_stance, 1.0) * g.length


## Moves the phase on for each rules frame `f` has stepped since the last
## call, then shows the blend at `alpha` between the last two frames, with the
## hold clip `idle_clip` at `idle_seconds`.
func update(f: Fighter, idle_clip: StringName, idle_seconds: float, alpha: float) -> void:
	var mult: float = f.speed_mult()
	run_speed = SimConst.MOVE_RUN_FORWARD * mult
	sprint_speed = SimConst.MOVE_SPRINT * mult
	var frame: int = f.world.frame if f.world != null else _frame
	if _frame < 0 or frame < _frame:
		# the first update, or a new world: start from where the legs are
		_frame = frame
		speed = ground_speed(f)
		prev_speed = speed
		prev_phase = phase
	elif frame > _frame:
		var s: float = ground_speed(f)
		var length: float = stride(s)
		var step: float = s / length / float(SimConst.FPS) if length > 0.0 else 0.0
		for i: int in frame - _frame:
			prev_phase = phase
			phase = fposmod(phase + step, 1.0)
		prev_speed = speed if frame - _frame == 1 else s
		speed = s
		_frame = frame
	shown_phase = fposmod(prev_phase + fposmod(phase - prev_phase, 1.0) * alpha, 1.0)
	shown = weights(lerpf(prev_speed, speed, alpha), run_speed, sprint_speed)
	_show(idle_clip, idle_seconds)


# ------------------------------------------------------------------ the tree

## idle, walk, jog and sprint, each through a seek, then
## walk_jog = Blend2(walk, jog), to_sprint = Blend2(walk_jog, sprint) and
## move = Blend2(idle, to_sprint).
func _build() -> void:
	tree = AnimationTree.new()
	tree.name = &"Locomotion"
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.add_animation_library(FighterModel.LIBRARY, FighterModel.ANIMATION_LIBRARY)
	_root = AnimationNodeBlendTree.new()
	var clips: Array[StringName] = [model.idle_clip()]
	clips.append_array(CLIPS)
	for i: int in NODES.size():
		var anim: AnimationNodeAnimation = AnimationNodeAnimation.new()
		anim.animation = _anim_name(clips[i])
		_root.add_node(NODES[i], anim)
		_root.add_node(_seek(NODES[i]), AnimationNodeTimeSeek.new())
		_root.connect_node(_seek(NODES[i]), 0, NODES[i])
	_idle_clip = clips[0]
	_root.add_node(&"walk_jog", AnimationNodeBlend2.new())
	_root.connect_node(&"walk_jog", 0, _seek(&"walk"))
	_root.connect_node(&"walk_jog", 1, _seek(&"jog"))
	_root.add_node(&"to_sprint", AnimationNodeBlend2.new())
	_root.connect_node(&"to_sprint", 0, &"walk_jog")
	_root.connect_node(&"to_sprint", 1, _seek(&"sprint"))
	_root.add_node(&"move", AnimationNodeBlend2.new())
	_root.connect_node(&"move", 0, _seek(&"idle"))
	_root.connect_node(&"move", 1, &"to_sprint")
	_root.connect_node(&"output", 0, &"move")
	tree.tree_root = _root
	model.add_child(tree)
	tree.active = true


func _show(idle_clip: StringName, idle_seconds: float) -> void:
	if idle_clip != _idle_clip:
		_idle_clip = idle_clip
		(_root.get_node(&"idle") as AnimationNodeAnimation).animation = _anim_name(idle_clip)
	var idle: Animation = tree.get_animation(_anim_name(idle_clip))
	var idle_at: float = fposmod(idle_seconds, idle.length) if idle.loop_mode != Animation.LOOP_NONE else minf(idle_seconds, idle.length)
	tree.set("parameters/%s/seek_request" % _seek(&"idle"), idle_at)
	for i: int in CLIPS.size():
		tree.set("parameters/%s/seek_request" % _seek(NODES[i + 1]), clip_time(i, shown_phase))
	var w: PackedFloat32Array = shown
	var moving: float = 1.0 - w[0]
	tree.set("parameters/move/blend_amount", moving)
	tree.set("parameters/to_sprint/blend_amount", w[3] / moving if moving > 0.0 else 0.0)
	tree.set("parameters/walk_jog/blend_amount", w[2] / (w[1] + w[2]) if w[1] + w[2] > 0.0 else 1.0)
	tree.advance(0.0)


static func _seek(node: StringName) -> StringName:
	return StringName(String(node) + "_seek")


static func _anim_name(clip: StringName) -> String:
	return String(FighterModel.LIBRARY) + "/" + String(clip)
