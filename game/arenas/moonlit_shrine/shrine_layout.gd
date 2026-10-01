class_name ShrineLayout
extends Resource
## Where the Moonlit Shrine's pieces go: the numbers the builders read, kept in
## one data file so the arena can be re-dressed without touching code.
##
## Angles are in degrees around the arena centre, measured from +Z toward +X:
## 0 is player two's end (+Z) and 180 is player one's end (-Z), where the
## rules start each side. Player one's camera looks toward +Z, so the moon
## sits on that side. Radii are metres from the centre; heights are metres
## above the courtyard floor. The walls, spawns and gates come from the
## ArenaDef, not from here.

## Seed for every random choice in the builders (stone shades, pebbles).
@export var seed: int = 7

@export_group("Courtyard")
## Paving: radius of the round centre stone, width of each ring of tiles, and
## the target tile length along a ring.
@export var centre_radius: float = 2.7
@export var ring_width: float = 1.18
@export var tile_length: float = 1.5
## Flat pebbles along the inside foot of the parapet: the only things built
## inside the walkable circle.
@export var pebble_count: int = 14

@export_group("Parapet")
## Posts around the parapet (gate openings remove some).
@export var post_count: int = 52
## Half-angle of the opening in the parapet at each gate.
@export var gate_opening_deg: float = 7.5
## Rail segments (between post i and i + 1) whose top rail is broken.
@export var broken_rails: PackedInt32Array = PackedInt32Array([7, 18, 33, 45])
## Posts that are cracked short.
@export var damaged_posts: PackedInt32Array = PackedInt32Array([8, 34, 46])

@export_group("Gates")
## The width of each gate's torii; its landing is a little wider.
@export var torii_span: float = 5.4

@export_group("World")
## Direction toward the moon (normalised by the builders). The red rim light
## shines from it.
@export var moon_direction: Vector3 = Vector3(0.42, 0.25, 1.0)
## Direction the moonlight comes from (the key light), independent of the
## moon's disc.
@export var key_light_direction: Vector3 = Vector3(-0.95, 1.05, -0.25)


## Converts an angle (degrees, from +Z toward +X) and a radius to a point.
static func polar(angle_deg: float, radius: float, height: float = 0.0) -> Vector3:
	var a: float = deg_to_rad(angle_deg)
	return Vector3(sin(a) * radius, height, cos(a) * radius)
