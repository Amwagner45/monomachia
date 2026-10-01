class_name ShrineProps
extends RefCounted
## Procedural shrine props, each added to a MeshKitSet at a transform so many
## props share one mesh per material. So far the platform's materials and the
## sacred rope; task 17.4 adds the lanterns, torii, pillars and trees.


## Materials for every kit key the platform uses.
static func materials() -> Dictionary[StringName, Material]:
	return {
		&"landing": ToonMaterials.prop(LookPalette.STONE_LIGHT, 0.4),
		&"parapet": ToonMaterials.prop(LookPalette.STONE, 0.35),
		&"stone_dark": ToonMaterials.prop(LookPalette.STONE_DARK, 0.3),
		&"pebbles": ToonMaterials.prop(LookPalette.STONE_DARK, 0.3, false),
		&"rope": ToonMaterials.prop(LookPalette.ROPE, 0.25),
		&"paper": ToonMaterials.prop(LookPalette.PAPER, 0.0, false),
	}


## A sacred straw rope (shimenawa) sagging from a to b, with paper streamers.
static func shimenawa(kits: MeshKitSet, a: Vector3, b: Vector3, sag: float, streamers: int, thickness: float) -> void:
	var rope: MeshKit = kits.kit(&"rope")
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	var n: int = 16
	for i: int in n + 1:
		var t: float = float(i) / n
		pts.append(a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))
		radii.append(thickness * (1.0 + 0.18 * sin(t * 40.0)) * (1.0 - 0.35 * absf(t * 2.0 - 1.0)))
	rope.tube(pts, radii, 7)
	var paper: MeshKit = kits.kit(&"paper")
	var along: Vector3 = (b - a).normalized()
	var face := Basis(along, Vector3.UP, along.cross(Vector3.UP).normalized())
	for k: int in streamers:
		var t: float = (k + 1.0) / (streamers + 1.0)
		var top: Vector3 = a.lerp(b, t) + Vector3.DOWN * (sag * 4.0 * t * (1.0 - t) + thickness)
		for piece: int in 4:
			var off: float = 0.045 if piece % 2 == 0 else -0.045
			paper.box(Transform3D(face, top + along * off + Vector3.DOWN * (0.07 + piece * 0.12)), Vector3(0.09, 0.12, 0.012))
		rope.box(Transform3D(face, top + Vector3.DOWN * 0.12 + along * 0.11), Vector3(0.025, 0.22, 0.025))
