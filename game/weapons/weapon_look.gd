class_name WeaponLook
extends Resource
## What a weapon looks like and how it is held: its model scene, the markers
## the swing and trail code read, and how it sits in the hand. Each weapon's
## look is weapons/<id>/<id>.tres, with `id` equal to its WeaponDef id.
##
## Weapon space, which every weapon scene's root uses:
## - origin: the centre of the main hand's grip, where the hand closes;
## - +Y: along the blade, from the grip toward the tip;
## - +X: toward the cutting edge (the side that leads a cut);
## - +Z: X cross Y, out of the flat of the blade;
## - metres, at the size the weapon has in the game.
##
## Markers, Marker3D children of the scene root, in weapon space:
## - BladeBase: where the cutting part of the blade starts, above the guard;
## - BladeTip: the point;
## - OffHandGrip (two-handed weapons only): the centre of the off hand's
##   grip, below the origin.
##
## A fighter's hand socket (FighterModel.right_hand / left_hand) uses the same
## frame for a closed fist: origin in the hollow of the fist, +Y out of the
## thumb side, +X out of the knuckles. A weapon attached to a socket with an
## identity `grip_offset` therefore sits in the fist blade-up and edge-forward;
## `grip_offset` corrects for each model's handle.

## The weapons that have a look (WeaponDef ids).
const IDS: Array[StringName] = [&"katana", &"greatsword", &"daggers"]

const BLADE_BASE: StringName = &"BladeBase"
const BLADE_TIP: StringName = &"BladeTip"
const OFF_HAND_GRIP: StringName = &"OffHandGrip"

@export var id: StringName = &""
@export var display_name: String = ""
## The weapon's model, its root in weapon space, with the markers above.
@export var scene: PackedScene
## The weapon's transform in the hand socket's space.
@export var grip_offset: Transform3D = Transform3D.IDENTITY
## Held in both hands: the off hand goes to OffHandGrip.
@export var two_handed: bool = false
## One copy in each hand (the daggers).
@export var paired: bool = false
## Width in metres of the swing trail, measured from the tip toward the base.
@export var trail_width: float = 0.5


static func path_for(weapon_id: StringName) -> String:
	return "res://weapons/%s/%s.tres" % [weapon_id, weapon_id]


static func load_id(weapon_id: StringName) -> WeaponLook:
	return load(path_for(weapon_id)) as WeaponLook


## Instantiates the model and puts it in `socket` at the grip offset, turned
## first by `hold` (a fighter's way of holding it: see WeaponHold).
func attach(socket: Node3D, hold: Transform3D = Transform3D.IDENTITY) -> Node3D:
	var weapon: Node3D = scene.instantiate()
	weapon.transform = hold * grip_offset
	socket.add_child(weapon)
	return weapon


## A marker of a weapon instance, or null when it has none.
static func marker(weapon: Node, marker_name: StringName) -> Marker3D:
	return weapon.get_node_or_null(NodePath(String(marker_name))) as Marker3D


## The blade's base and tip in weapon space.
static func blade_segment(weapon: Node) -> PackedVector3Array:
	return PackedVector3Array([marker(weapon, BLADE_BASE).position, marker(weapon, BLADE_TIP).position])
