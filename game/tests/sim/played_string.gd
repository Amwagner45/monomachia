class_name PlayedString
extends SimHelpers.Rec
## A string played by fighter 0, for each weapon's strings test (plan tasks
## 9-11): its events, each with "step", the step it came on, and after each
## step fighter 0's state, the attack it was in (&"" outside one), that
## attack's frame (-1), whether it was holding a charge (for the Iai,
## sheathed), how far it moved over the ground in the step and how far apart
## the two fighters' centres stood. play() and run() drive the strings.

var state: Array[StringName] = []
var attack: Array[StringName] = []
var frame: PackedInt32Array = []
var charging: Array[bool] = []
var moved: PackedFloat64Array = []
var apart: PackedFloat64Array = []


## Fighter 0, holding weapon, plays a string of presses (Btn.LIGHT or
## Btn.HEAVY) for 240 steps against an idle Katana gap m away: the first on
## step 0, each next one on the step after the attack before it swings, the
## first step that attack takes a follow-up. mx is the stick's sideways push
## throughout (1.0 draws the Katana's horizontal Iai). With dodge_in set, it
## also presses dodge so that the press first counts on that attack's frame
## dodge_on, holding the stick to the side from then on (a buffered dodge
## with the stick let go is a backstep).
static func play(
	weapon: WeaponDef, presses: Array[int], gap: float = 2.2, mx: float = 0.0, dodge_in: StringName = &"", dodge_on: int = -1
) -> PlayedString:
	var W: World = SimHelpers.make_world(weapon, Moves.KATANA, gap)
	var a: Fighter = W.fighters[0]
	var r := PlayedString.new()
	var next: int = 0
	var due: bool = true
	var dodged: bool = false
	for i: int in 240:
		var p0: RawInput = SimHelpers.move(mx, 0.0)
		if due and next < presses.size():
			p0 = SimHelpers.move(mx, 0.0, presses[next])
			next += 1
			due = false
		elif dodged:
			p0 = SimHelpers.move(1.0, 0.0)
		elif a.state == &"attack" and a.atk.def.id == dodge_in and a.atk.frame == dodge_on - 1:
			p0 = SimHelpers.move(1.0, 0.0, Btn.DODGE)
			dodged = true
		for e: Dictionary in r.step(W, p0):
			if e["t"] == &"swing" and e["f"] == 0:
				due = true
	return r


## Fighter 0, holding weapon, plays the input p0 gives each step (step index
## -> RawInput) for n steps against an idle Katana gap m away.
static func run(weapon: WeaponDef, p0: Callable, gap: float = 2.2, n: int = 240) -> PlayedString:
	var W: World = SimHelpers.make_world(weapon, Moves.KATANA, gap)
	var r := PlayedString.new()
	for i: int in n:
		r.step(W, p0.call(i))
	return r


## Steps W with fighter 0's input p0 and fighter 1's p1 (null for idle),
## records the step, and returns its events.
func step(W: World, p0: RawInput, p1: RawInput = null) -> Array[Dictionary]:
	var i: int = state.size()
	var a: Fighter = W.fighters[0]
	var x: float = a.pos.x
	var z: float = a.pos.z
	W.step([p0, SimHelpers.idle() if p1 == null else p1])
	var new_events: Array[Dictionary] = W.drain_events()
	for e: Dictionary in new_events:
		e["step"] = i
	events.append_array(new_events)
	var attacking: bool = a.state == &"attack" and a.atk != null
	state.append(a.state)
	attack.append(a.atk.def.id if attacking else &"")
	frame.append(a.atk.frame if attacking else -1)
	charging.append(attacking and a.atk.charging)
	moved.append(JsMath.hypot(a.pos.x - x, a.pos.z - z))
	apart.append(SimMath.dist2(a.pos, W.fighters[1].pos))
	return new_events


## How far fighter 0 moved from step from to step to (not included), adding
## up each step, so an orbit counts in full.
func walked(from: int, to: int) -> float:
	var total: float = 0.0
	for d: float in moved.slice(from, to):
		total += d
	return total


## The step of fighter 0's first event of type t (-1 if none).
func step_of(t: StringName) -> int:
	for e: Dictionary in all(t):
		if _by_fighter_0(e):
			return e["step"]
	return -1


## Whether fighter 0 made event e (a swing or whiff names its fighter as "f",
## a hit or block as "attacker").
static func _by_fighter_0(e: Dictionary) -> bool:
	return e.get("f", e.get("attacker")) == 0


## The frame fighter 0's last attack id ended on, one past the last frame a
## step left it in (-1 if it never started): an attack is over on the step
## its frame reaches startup + active + recovery.
func ended_on(id: StringName) -> int:
	var i: int = attack.rfind(id)
	return -1 if i < 0 else frame[i] + 1


## Fighter 0's state on the step its last attack id ended (&"?" if it never
## started or the run ended first): &"attack" when a follow-up took over.
func state_after(id: StringName) -> StringName:
	var i: int = attack.rfind(id)
	return &"?" if i < 0 or i + 1 >= state.size() else state[i + 1]


## The ids of fighter 0's attacks that made events of type t, in order.
func ids(t: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for e: Dictionary in all(t):
		if _by_fighter_0(e):
			out.append(e["attack"])
	return out
