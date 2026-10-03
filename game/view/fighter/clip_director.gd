class_name ClipDirector
extends RefCounted
## The clip director (authored-animation task 8): which authored clips a
## fighter plays, at what times and with what weights, worked out from its
## rules state with no nodes, like HudState, so tests drive it directly.
## FighterView applies the answer (a Shot) to its model's AnimationTree
## (Locomotion's, which blends the shot's clips over the legs' blend), once
## per rules frame.
##
## step() takes the last shot, the fighter and a Context (its clip set,
## whether the Iglesias libraries are there, the clips' lengths) and gives the
## next shot. It is a pure function of them: the shot carries all it needs
## from one rules frame to the next (what drives, the crossfade's progress,
## the clip faded out). A frame the world didn't step (hit-stop, pause) gives
## the same shot, so everything holds still.
##
## What it covers so far:
## - the free state's idle, by weapon class (IDLE; FALLBACK_IDLE without the
##   packs): under the legs' blend (Shot.idle);
## - an attack whose move has a baked swing (Swing.clips): its clip, timed
##   from the attack frame on the frames the bake used (ClipTiming: the
##   wind-up across the startup, the strike across the active frames, the
##   follow-through across the recovery), entered from the attack's first
##   frame; a charge holds it where the rules hold the frame. Without the
##   packs it plays the swing's fallback stretched over the move, or nothing.
##   The Rogue plays the Hunter's set for a move whose HumanF clip strays
##   (ClipLibraries.set_for()). Moves without a baked swing keep the
##   stand-in poses: nothing drives;
## - the crossfades, in rules frames (FADES): into an attack 3, a follow-up 4
##   from the last clip's pose, a dodge-cancel 2, a cut for hitstun, 6 back to
##   the legs, 8 for a stance (task 18 on).

## The crossfades' lengths, in rules frames.
const FADES: Dictionary[StringName, int] = {
	&"attack": 3, &"follow_up": 4, &"dodge_cancel": 2, &"hitstun": 0, &"locomotion": 6, &"stance": 8,
}
## The free state's idle per weapon (a WeaponDef id; bare hands and a
## disarmed fighter are fists): clip-manifest ids.
const IDLE: Dictionary[StringName, StringName] = {
	&"katana": &"CombatIdle1H01", &"daggers": &"CombatIdle1H01",
	&"greatsword": &"CombatIdle2H01", &"fists": &"CombatIdle01",
}
## The idle without the packs: clips of the committed CC0 library.
const FALLBACK_IDLE: Dictionary[StringName, StringName] = {
	&"katana": &"Sword_Idle", &"daggers": &"Sword_Idle", &"greatsword": &"Sword_Idle", &"fists": &"Idle",
}
## What drives the body: the legs' blend, or an authored clip.
const LEGS: StringName = &"legs"
const ATTACK: StringName = &"attack"


## What a fighter is playing and from what it plays.
class Context:
	## The fighter (a FighterLook id), whose own clip set it plays.
	var fighter_id: StringName = &"hunter"
	## Whether the Iglesias clip libraries are there.
	var libraries: bool = false
	## Each animation's length (s), by its name in the tree ("HumanM/x").
	var lengths: Dictionary[String, float] = {}

	static func make(p_fighter: StringName, p_libraries: bool, p_lengths: Dictionary[String, float]) -> Context:
		var c: Context = Context.new()
		c.fighter_id = p_fighter
		c.libraries = p_libraries
		c.lengths = p_lengths
		return c


## One animation at one moment: its name in the tree and its time (s).
class Clip:
	var name: String = ""
	var time: float = 0.0
	## Inside a chain, while a part fades in (ClipChain): the part before,
	## held at its end, and how much of it still shows; else null.
	var under: Clip = null
	var under_weight: float = 0.0

	static func make(p_name: String, p_time: float) -> Clip:
		var c: Clip = Clip.new()
		c.name = p_name
		c.time = p_time
		return c


## The director's answer for one rules frame.
class Shot:
	## The world frame it is for; -1 before the first.
	var frame: int = -1
	## LEGS or ATTACK.
	var drive: StringName = LEGS
	## The authored clip driving, at this frame and at the frame before (for
	## showing between frames); null when the legs drive.
	var clip: Clip = null
	var clip_before: Clip = null
	## What it fades in from: an authored clip held at its last pose, or null
	## for the legs' blend.
	var from: Clip = null
	## The crossfade's length and how many rules frames in it is.
	var fade: int = 0
	var since: int = 0
	## The idle under the legs' blend (a name in the tree).
	var idle: String = ""
	## The attack it plays (to tell a new attack, a follow-up, from the same).
	var attack: AttackState = null
	## The move the attack's clip came from, and the state the fighter was in.
	var move: StringName = &""
	var state: StringName = &""

	## How far the crossfade is in (0 to 1, smoothed): the share of the new
	## drive over what it fades in from.
	func blend() -> float:
		if fade <= 0 or since >= fade:
			return 1.0
		return smoothstep(0.0, 1.0, float(since) / float(fade))

	## How much the authored clips (clip and from) show over the legs' blend.
	func authored() -> float:
		if drive == ATTACK:
			return 1.0 if from != null else blend()
		return 0.0 if from == null else 1.0 - blend()

	## How much of the authored clips is `clip` rather than `from`.
	func clip_share() -> float:
		if clip == null:
			return 0.0
		if from == null:
			return 1.0
		return blend()

	func copy() -> Shot:
		var s: Shot = Shot.new()
		for p: Dictionary in get_property_list():
			if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				s.set(p["name"], get(p["name"]))
		return s


## The next shot for fighter `f`, after `prev` (null at first).
static func step(prev: Shot, f: Fighter, ctx: Context) -> Shot:
	var frame: int = f.world.frame if f.world != null else 0
	if prev != null and prev.frame == frame:
		return prev
	var out: Shot = prev.copy() if prev != null else Shot.new()
	out.frame = frame
	out.idle = idle_clip(f, ctx)
	var playing: Clip = attack_clip(f, ctx, float(f.atk.frame) if f.atk != null else 0.0)
	var drive: StringName = ATTACK if playing != null else LEGS
	if prev == null:
		out.drive = drive
		out.clip = playing
		out.clip_before = playing
		out.attack = f.atk if playing != null else null
		out.move = f.atk.def.id if playing != null else &""
		out.state = f.state
		out.fade = 0
		out.since = 0
		out.from = null
		return out
	var changed: bool = drive != prev.drive or (drive == ATTACK and f.atk != prev.attack)
	if changed:
		# what it fades in from: the authored clip shown last, held where it was
		out.from = _shown(prev)
		out.fade = _fade(prev, f, drive)
		out.since = 0
		out.clip_before = playing
	else:
		out.since = prev.since + 1
		out.clip_before = prev.clip
		if out.from != null and out.since >= out.fade:
			out.from = null
	if out.fade <= 0:
		out.from = null
	out.drive = drive
	out.clip = playing
	out.attack = f.atk if playing != null else null
	out.move = f.atk.def.id if playing != null else &""
	out.state = f.state
	return out


## The idle under the legs' blend for `f`'s weapon class (bare hands when
## disarmed), as a name in the tree.
static func idle_clip(f: Fighter, ctx: Context) -> String:
	var wid: StringName = f.weapon.id if f.armed and f.weapon != null else &"fists"
	if ctx.libraries:
		return "%s/%s" % [ClipLibraries.FIGHTER_SETS.get(ctx.fighter_id, &"HumanM"), IDLE.get(wid, IDLE[&"fists"])]
	return "%s/%s" % [FighterModel.LIBRARY, FALLBACK_IDLE.get(wid, FALLBACK_IDLE[&"fists"])]


## The authored clip `f`'s attack plays at attack frame `t` (which may fall
## between frames), or null when nothing authored drives: not attacking, a
## move without a baked swing (or of another moveset than its own), or
## without the packs a swing with no fallback.
static func attack_clip(f: Fighter, ctx: Context, t: float) -> Clip:
	if f.state != &"attack" or f.atk == null:
		return null
	var def: AttackDef = f.atk.def
	var swing: Swing = def.swing
	if swing == null or swing.clips.is_empty() or f.moveset().moves.get(def.id) != def:
		return null
	if not ctx.libraries:
		if swing.fallback == &"":
			return null
		var anim_name: String = "%s/%s" % [FighterModel.LIBRARY, swing.fallback]
		var share: float = clampf(t / float(maxi(1, def.total_frames())), 0.0, 1.0)
		return Clip.make(anim_name, share * ctx.lengths.get(anim_name, 0.0))
	var timing: ClipTiming = timing_of(swing)
	if timing == null:
		return null
	var set_name: StringName = ClipLibraries.set_for(ctx.fighter_id, swing)
	return chain_clip(swing.clips, set_name, timing.clip_time(t), ctx)


## The timing a baked swing was baked on (its markers and speed), or null.
static func timing_of(swing: Swing) -> ClipTiming:
	var markers: Dictionary = {}
	for i: int in mini(swing.marks.size(), ClipManifest.MARKERS.size()):
		markers[ClipManifest.MARKERS[i]] = swing.marks[i]
	if swing.marks.size() > ClipManifest.MARKERS.size():
		markers["hold"] = swing.marks[ClipManifest.MARKERS.size()]
	return ClipTiming.make(markers, swing.speed, [] as Array[String])


## The clip of chain `clips` (ClipChain entries, in set `set_name`) at
## `time` (s from the chain's start) and the time into it, with the part
## before under it while a part fades in; null when a clip is missing.
static func chain_clip(clips: Array[StringName], set_name: StringName, time: float, ctx: Context) -> Clip:
	var lengths: Dictionary = {}
	for entry: StringName in clips:
		var id: StringName = ClipChain.parse(String(entry), [] as Array[String]).id
		lengths[id] = ctx.lengths.get(ClipChain.anim_name(set_name, id), 0.0) * float(ClipManifest.SOURCE_FPS)
	var parts: Array[ClipChain.Part] = ClipChain.lay_out(clips, lengths, [] as Array[String])
	if parts.is_empty():
		return null
	var at: ClipChain.Place = ClipChain.place(parts, time * float(ClipManifest.SOURCE_FPS))
	var fps: float = float(ClipManifest.SOURCE_FPS)
	var out: Clip = Clip.make(ClipChain.anim_name(set_name, parts[at.part].id), at.frame / fps)
	if at.under >= 0:
		out.under = Clip.make(ClipChain.anim_name(set_name, parts[at.under].id), at.under_frame / fps)
		out.under_weight = at.under_weight
	return out


## What showed last as an authored clip, held at its pose: the clip when one
## drove, else the one still fading out, else null (the legs).
static func _shown(prev: Shot) -> Clip:
	if prev.clip != null and prev.clip_share() >= 0.5:
		return prev.clip
	if prev.from != null:
		return prev.from
	return prev.clip


## How long the change from `prev` to `drive` fades: into an attack 3, a
## follow-up 4, back to the legs 6; an attack cancelled into a dodge 2;
## hitstun cuts.
static func _fade(prev: Shot, f: Fighter, drive: StringName) -> int:
	if f.state == &"hitstun":
		return FADES[&"hitstun"]
	if drive == ATTACK:
		if prev.drive == ATTACK and f.atk.chained_from != null:
			return FADES[&"follow_up"]
		return FADES[&"attack"]
	if prev.drive == ATTACK and (f.state == &"dodge" or f.state == &"backstep"):
		return FADES[&"dodge_cancel"]
	return FADES[&"locomotion"]
