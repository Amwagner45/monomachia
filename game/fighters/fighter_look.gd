class_name FighterLook
extends Resource
## What a fighter looks like: the parts FighterModel assembles into a rigged
## model, the two palettes, and the clips that carry the fighter's
## personality. A fighter's scene (fighters/<id>/<id>.tscn) is a FighterModel
## pointing at its look.
##
## All parts share the Quaternius 65-bone skeleton, retargeted to Godot's
## humanoid profile at import. The fighter's skeleton is the first outfit
## part's: outfits and hair were modelled on it, so they fit it exactly. The
## base body only supplies the head (cut at import by tools/cut_heads.gd),
## the eyes and the eyebrows, which ride on the Head and Neck bones.

## The fighters that have a look, in fighter-select order. Fighter `id`'s
## look is fighters/<id>/<id>.tres and its scene fighters/<id>/<id>.tscn.
const IDS: Array[StringName] = [&"rogue", &"hunter"]

@export var id: StringName = &""
@export var display_name: String = ""
## The full Quaternius base body (.gltf). Its body mesh is replaced by
## `head_mesh`; its eyes and eyebrows are kept.
@export var body_scene: PackedScene
## The head-only cut of the body mesh, made by tools/cut_heads.gd.
@export var head_mesh: ArrayMesh
## Outfit parts (.gltf), each a skinned mesh on the shared skeleton. The
## first one supplies the fighter's skeleton.
@export var outfit_parts: Array[PackedScene] = []
## Hairstyles and beards (.gltf, rigged to the head bone).
@export var hair: Array[PackedScene] = []
## The outfit material the palettes recolour (by its imported name).
@export var outfit_material: StringName = &"MI_Ranger"
## Exactly two: the first is the default, the second dresses the second
## fighter of a mirror match.
@export var palettes: Array[FighterPalette] = []
## The weapon offered by default at fighter select (a WeaponDef id).
@export var signature_weapon: StringName = &""
## Clip names in the shared animation library (without the library prefix).
@export var idle_clip: StringName = &"Idle"
@export var walk_clip: StringName = &"Walk"


static func path_for(fighter_id: StringName) -> String:
	return "res://fighters/%s/%s.tres" % [fighter_id, fighter_id]


static func scene_path_for(fighter_id: StringName) -> String:
	return "res://fighters/%s/%s.tscn" % [fighter_id, fighter_id]


## Instantiates a fighter's scene: a built FighterModel.
static func instantiate_fighter(fighter_id: StringName) -> FighterModel:
	return (load(scene_path_for(fighter_id)) as PackedScene).instantiate() as FighterModel
