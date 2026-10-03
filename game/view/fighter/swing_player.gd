class_name SwingPlayer
extends RefCounted
## Plays a move's swing (task 7) on a fighter in the match (plan task 14.10):
## the weapon goes where the rules' swing has it, and the arms reach for it.
## FighterView asks it every frame; it never changes the rules.
##
## - The swing is sampled at the attack's frame as the match shows it: the
##   frame before the last step plus the host's alpha (AttackState.frame - 1
##   + alpha), so it moves between steps as the fighter's position does, and
##   holds still in hit-stop (alpha 1) and through a charge (the attack's
##   frame stands still: the frame itself, as the rules' blade holds it).
##   A follow-up enters from the hand-off of the move it follows, as the
##   rules' does (AttackState.chained_from).
## - Each hand track places a held weapon in skeleton space from its grip,
##   blade and edge: the right hand the weapon (the first of a pair), the
##   left hand the second of a pair. A two-handed weapon's off hand grips its
##   off-hand grip on the rig, as the rules' swing check seats it. A held
##   weapon with no track (one dagger of a swing that moves only the other)
##   stays on the stand-in pose.
## - The key's elbow-pole tweak goes on the rig (FighterRig.pole_tweak), as
##   the swing check bends the elbow.
## - The root stays where the rules put the fighter: the view never adds its
##   own lunge or turn, so the weapon shown is the weapon that hits.
## Moves without a swing, and moves of another moveset than the held
## weapon's, play from StickPose as before.
##
## Swings are in the fighter's own (right, up, forward) frame; skeleton space
## is +X to the fighter's left, +Y up, +Z forward, so a swing's x turns round.

## The hand track that places each held weapon, by its index.
const TRACKS: Array[StringName] = [&"right_hand", &"left_hand"]
## The rig's side for each hand track.
const SIDES: Dictionary[StringName, String] = {&"right_hand": "Right", &"left_hand": "Left"}


## A point or direction from the fighter's (right, up, forward) frame into
## skeleton space.
static func to_skeleton(v: V3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


## Whether fighter `f` plays a swing now: attacking with a move of its own
## moveset that has a swing.
static func plays(f: Fighter) -> bool:
	if f.state != &"attack" or f.atk == null or f.atk.def.swing == null:
		return false
	return f.moveset().moves.get(f.atk.def.id) == f.atk.def


## The attack's frame as the match shows it, `alpha` (MatchHost.alpha()) of
## the way from the step before to the last: frame - 1 + alpha, from 0; the
## frame itself while charging, where the rules hold the swing.
static func swing_frame(f: Fighter, alpha: float) -> float:
	if f.atk.charging:
		return float(f.atk.frame)
	return maxf(0.0, float(f.atk.frame) - 1.0 + alpha)


## The swing of the move fighter `f`'s attack follows, or null on a fresh
## start.
static func chained_swing(f: Fighter) -> Swing:
	return f.atk.chained_from.swing if f.atk.chained_from != null else null


## The pose of `part` of fighter `f`'s swing at frame `t`, entered as the
## rules enter it; null when the swing has no such track.
static func sample(f: Fighter, part: StringName, t: float) -> Swing.Sample:
	return f.atk.def.swing.sample(part, t, chained_swing(f))


## A weapon's transform in skeleton space for a hand track's sample (see
## FighterRig.weapon_frame()).
static func weapon_transform(s: Swing.Sample) -> Transform3D:
	return FighterRig.weapon_frame(to_skeleton(s.grip), to_skeleton(s.blade), to_skeleton(s.edge))


## The poses of fighter `f`'s held weapons now, by index, for a model holding
## `count` weapons (two for a pair): each from its hand track, at the frame
## swing_frame() gives for `alpha`. A weapon with no track is left out. Puts
## each track's elbow-pole tweak on `rig` (none for a hand without one).
static func weapon_poses(f: Fighter, alpha: float, count: int, rig: FighterRig) -> Dictionary[int, Transform3D]:
	var out: Dictionary[int, Transform3D] = {}
	var t: float = swing_frame(f, alpha)
	rig.clear_pole_tweaks()
	for i: int in mini(count, TRACKS.size()):
		var s: Swing.Sample = sample(f, TRACKS[i], t)
		if s == null:
			continue
		out[i] = weapon_transform(s)
		rig.pole_tweak[SIDES[TRACKS[i]]] = to_skeleton(s.pole)
	return out
