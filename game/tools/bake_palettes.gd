extends SceneTree
## Bakes each fighter palette's outfit texture: recolours the Ranger outfit's
## T_Ranger_3 base colour with the palette's colours (see FighterPalette for
## the regions) and saves it next to the palette as <palette>_outfit.png.
##
## Run: node scripts/godot.mjs script res://tools/bake_palettes.gd
## then `node scripts/godot.mjs import`.
##
## Palettes are found through the fighter looks in LOOKS. A new palette's
## .tres can be written without its outfit_albedo first; point it at the
## baked PNG once the PNG has been imported.

const ImportAssets = preload("res://tools/import_assets.gd")

const SOURCE: String = "res://assets/quaternius/outfits/T_Ranger_3_BaseColor.png"
const LOOKS: Array[String] = ["res://fighters/rogue/rogue.tres", "res://fighters/hunter/hunter.tres"]


static func _ss(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)


func _initialize() -> void:
	var src: Image = Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	src.convert(Image.FORMAT_RGB8)
	var regions: Dictionary = analyse(src)
	print("bake_palettes: cloth %.0f%% (mean value %.2f), trim %.0f%% (%.2f), metal %.0f%%" % [
		regions.cloth_share * 100.0, regions.cloth_ref, regions.trim_share * 100.0, regions.trim_ref, regions.metal_share * 100.0])
	var failed: bool = false
	for look_path: String in LOOKS:
		var look: FighterLook = load(look_path)
		for p: FighterPalette in look.palettes:
			var out_path: String = p.resource_path.get_basename() + "_outfit.png"
			var img: Image = recolour(src, regions, p)
			var err: Error = img.save_png(ProjectSettings.globalize_path(out_path))
			if err != OK:
				printerr("bake_palettes: cannot save %s (%s)" % [out_path, error_string(err)])
				failed = true
				continue
			ImportAssets.write_texture_import(out_path, false)
			print("bake_palettes: %s (%s) -> %s" % [look.id, p.display_name, out_path])
	quit(1 if failed else 0)


## Per-pixel region weights of the source, and the reference brightness of
## the cloth and trim: the value a palette colour is pinned to, so the new
## colours keep the painted shading. The reference is the 75th percentile,
## which lands on the cloth itself rather than the dimmer padding between
## the UV islands that the cloth mask also catches.
static func analyse(src: Image) -> Dictionary:
	var data: PackedByteArray = src.get_data()
	var n: int = src.get_width() * src.get_height()
	var cloth: PackedFloat32Array = PackedFloat32Array()
	var trim: PackedFloat32Array = PackedFloat32Array()
	var warm: PackedFloat32Array = PackedFloat32Array()
	var value: PackedFloat32Array = PackedFloat32Array()
	cloth.resize(n)
	trim.resize(n)
	warm.resize(n)
	value.resize(n)
	var cloth_hist: PackedFloat64Array = PackedFloat64Array()
	var trim_hist: PackedFloat64Array = PackedFloat64Array()
	cloth_hist.resize(256)
	trim_hist.resize(256)
	var shares: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
	for i: int in n:
		var c: Color = Color8(data[i * 3], data[i * 3 + 1], data[i * 3 + 2])
		var hue: float = c.h * 360.0
		# Cool hues (the blue-grey metal and its glow) are left alone.
		var w: float = 1.0 - _ss(80.0, 110.0, hue) * (1.0 - _ss(300.0, 330.0, hue))
		# Cloth: unsaturated warm tones.
		var cl: float = (1.0 - _ss(0.26, 0.42, c.s)) * w
		# Trim: the saturated ochre quilting (hue about 47-50). The leather
		# vests are a darker, redder orange (hue about 36-42, value about 0.12).
		var tr: float = _ss(0.55, 0.7, c.s) * _ss(42.5, 45.5, hue) * (1.0 - _ss(68.0, 78.0, hue)) * _ss(0.15, 0.2, c.v) * w
		cloth[i] = cl
		trim[i] = tr
		warm[i] = w
		value[i] = c.v
		var bin: int = clampi(int(c.v * 255.0), 0, 255)
		cloth_hist[bin] += cl
		trim_hist[bin] += tr
		shares[0] += cl
		shares[1] += tr
		shares[2] += 1.0 - w
	return {
		"cloth": cloth, "trim": trim, "warm": warm, "value": value,
		"cloth_ref": _percentile(cloth_hist, 0.75), "trim_ref": _percentile(trim_hist, 0.75),
		"cloth_share": shares[0] / n, "trim_share": shares[1] / n, "metal_share": shares[2] / n,
	}


## The value (0..1) below which `fraction` of a 256-bin histogram lies.
static func _percentile(hist: PackedFloat64Array, fraction: float) -> float:
	var total: float = 0.0
	for h: float in hist:
		total += h
	var acc: float = 0.0
	for b: int in hist.size():
		acc += hist[b]
		if acc >= total * fraction:
			return (b + 0.5) / 256.0
	return 1.0


static func recolour(src: Image, regions: Dictionary, p: FighterPalette) -> Image:
	var data: PackedByteArray = src.get_data()
	var out: PackedByteArray = data.duplicate()
	var cloth: PackedFloat32Array = regions.cloth
	var trim: PackedFloat32Array = regions.trim
	var warm: PackedFloat32Array = regions.warm
	var value: PackedFloat32Array = regions.value
	var cloth_ref: float = regions.cloth_ref
	var trim_ref: float = regions.trim_ref
	for i: int in cloth.size():
		var c: Color = Color8(data[i * 3], data[i * 3 + 1], data[i * 3 + 2])
		var v: float = value[i]
		var grey: float = c.get_luminance()
		var leather: Color = Color(grey, grey, grey).lerp(c, p.leather_saturation) * p.leather_tint
		var o: Color = leather
		if trim[i] > 0.0:
			o = o.lerp(Color.from_hsv(p.trim_color.h, p.trim_color.s, clampf(p.trim_color.v * v / trim_ref, 0.0, 1.0)), trim[i])
		if cloth[i] > 0.0:
			o = o.lerp(Color.from_hsv(p.cloth_color.h, p.cloth_color.s, clampf(p.cloth_color.v * v / cloth_ref, 0.0, 1.0)), cloth[i])
		o = (c * p.metal_tint).lerp(o, warm[i])
		out[i * 3] = clampi(roundi(o.r * 255.0), 0, 255)
		out[i * 3 + 1] = clampi(roundi(o.g * 255.0), 0, 255)
		out[i * 3 + 2] = clampi(roundi(o.b * 255.0), 0, 255)
	return Image.create_from_data(src.get_width(), src.get_height(), false, Image.FORMAT_RGB8, out)
