class_name TrainingBrain
extends RefCounted
## Port of src/sim/ai/training.ts.
##
## Training dummy: repeats one chosen behaviour so the player can practise
## parry timing and the three unblockable counters.
##
## Port notes:
## - TrainingBehaviour is a StringName equal to the TS literal (BEHAVIOURS).
## - abilityFor is the static ability_for(); its null is &"".
## - Fighter.abilities is always replaced with a new array, never changed in
##   place: by default it is the weapon's own default_abilities array.
## - dispose() is new: it disposes the sparring brain and drops the fighter.

## TrainingBehaviour
const BEHAVIOURS: Array[StringName] = [
	&"idle", &"block", &"lights", &"heavies", &"thrust", &"sweep", &"slam", &"random", &"fight",
]


## The id of f's weapon ability with the given counter kind, or &"" (TS null).
static func ability_for(f: Fighter, kind: StringName) -> StringName:
	for ab_id: StringName in f.weapon.abilities:
		if f.weapon.moves.has(ab_id) and f.weapon.moves[ab_id].counter == kind:
			return ab_id
	return &""


## { btn, from, to }
class Tap:
	var btn: int
	var from: int
	var to: int


var behaviour: StringName = &"idle"
var _spar: AIBrain
var _next: int = 0
var _taps: Array[Tap] = []
var _hold: int = 0
var _pattern: int = 0

var me: Fighter


func _init(p_me: Fighter) -> void:
	me = p_me
	_spar = AIBrain.new(me, AIBrain.DIFFICULTY[&"normal"], 5)


## Breaks the references to the fighter. The brain can't think afterwards.
func dispose() -> void:
	_spar.dispose()
	me = null


func set_behaviour(b: StringName) -> void:
	behaviour = b
	_next = 0
	_taps = []
	_hold = 0
	# put the practised unblockable on the light slot
	if b == &"thrust" or b == &"sweep" or b == &"slam":
		var ab_id: StringName = ability_for(me, b)
		if ab_id != &"":
			var other: StringName = _other_ability(ab_id)
			var arr: Array[StringName] = [ab_id, other]
			me.abilities = arr
	else:
		me.abilities = me.weapon.default_abilities.duplicate()


## this.me.weapon.abilities.find((x) => x !== id) ?? id
func _other_ability(ab_id: StringName) -> StringName:
	for x: StringName in me.weapon.abilities:
		if x != ab_id:
			return x
	return ab_id


func _tap(btn: int, at: int, length: int = 2) -> void:
	var t: Tap = Tap.new()
	t.btn = btn
	t.from = at
	t.to = at + length - 1
	_taps.append(t)


func think() -> RawInput:
	if behaviour == &"fight":
		return _spar.think()
	var frame: int = me.world.frame + 1
	var mx: float = 0.0
	var my: float = 0.0
	var buttons: int = _hold
	var d: float = SimMath.dist2(me.pos, me.opp.pos)
	var want: float = 2.6 if me.weapon.id == &"greatsword" else (1.8 if me.weapon.id == &"daggers" else 2.2)
	var free: bool = me.state == &"free" or me.state == &"step"

	if behaviour == &"block":
		buttons |= 1 << Btn.BLOCK
	elif behaviour != &"idle":
		# keep a practice distance
		if free:
			if d > want + 0.6:
				my = 1.0
			elif d < want - 0.7:
				my = -0.7
		if free and frame >= _next and absf(d - want) < 0.9:
			var b: StringName = behaviour
			if b == &"random":
				var opts: Array[StringName] = [&"lights", &"heavies"]
				for k: StringName in [&"thrust", &"sweep", &"slam"]:
					if ability_for(me, k) != &"":
						opts.append(k)
				b = opts[_pattern % opts.size()]
				_pattern += 1
				if b == &"thrust" or b == &"sweep" or b == &"slam":
					_set_behaviour_keep_random(b)
			match b:
				&"lights":
					_tap(Btn.LIGHT, frame)
					_tap(Btn.LIGHT, frame + 9)
					_tap(Btn.LIGHT, frame + 18)
					_next = frame + 110
				&"heavies":
					_tap(Btn.HEAVY, frame)
					var p: int = _pattern
					_pattern += 1
					if p % 2 == 0:
						_tap(Btn.HEAVY, frame + 34)
					_next = frame + 120
				&"thrust", &"sweep", &"slam":
					_tap(Btn.BLOCK, frame, 3)
					_tap(Btn.LIGHT, frame + 1, 2)
					_next = frame + 130
	for t: Tap in _taps:
		if frame >= t.from and frame <= t.to:
			buttons |= 1 << t.btn
	var kept: Array[Tap] = []
	for t: Tap in _taps:
		if t.to >= frame:
			kept.append(t)
	_taps = kept
	return RawInput.make(mx, my, buttons)


## kind: &"thrust" | &"sweep" | &"slam"
func _set_behaviour_keep_random(kind: StringName) -> void:
	var ab_id: StringName = ability_for(me, kind)
	if ab_id == &"":
		return
	var other: StringName = _other_ability(ab_id)
	var arr: Array[StringName] = [ab_id, other]
	me.abilities = arr
