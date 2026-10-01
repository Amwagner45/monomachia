class_name JsFormat
extends RefCounted
## Prints numbers and small objects exactly as the TypeScript tools do under
## Node, so the output of the ported tools (soak.gd, counterlab.gd) can be
## compared with scripts/soak.ts and scripts/counterlab.ts line for line.
## Tools only: the rules never format text.


## Number.prototype.toFixed(digits) for a finite x with |x| < 2^52 and
## digits 0..3: the exact decimal value rounded half up (JS picks the larger
## n on a tie), not printf's rounding of the binary value.
static func to_fixed(x: float, digits: int) -> String:
	var neg: bool = x < 0.0
	if neg:
		x = -x
	var scale: int = 1
	for _i: int in digits:
		scale *= 10
	# x = mant * 2^e exactly
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, x)
	var bits: int = bytes.decode_s64(0)
	var exp_bits: int = (bits >> 52) & 0x7FF
	var mant: int = bits & ((1 << 52) - 1)
	var e: int = -1074
	if exp_bits != 0:
		mant |= 1 << 52
		e = exp_bits - 1075
	var n: int = 0
	if e >= 0:
		n = (mant << e) * scale
	else:
		var sh: int = -e
		var num: int = mant * scale # < 2^63 for digits <= 3
		if sh < 62:
			n = (num + (1 << (sh - 1))) >> sh
		# else: x * scale < 0.5, so n = 0
	@warning_ignore("integer_division")
	var s: String = str(n / scale)
	if digits > 0:
		s += "." + str(n % scale).lpad(digits, "0")
	return ("-" if neg else "") + s


## String(x) for a number: integers without a decimal point, other values in
## Godot's shortest form (only used in error messages).
static func num(x: float) -> String:
	if x == floorf(x) and absf(x) < 1e15:
		return str(int(x))
	return str(x)


## console.log of a flat object (util.inspect): keys in insertion order,
## quoted when they are not identifiers, ints and arrays of ints as values. The
## object stays on one line when it fits Node's 80-column break length.
static func inspect(obj: Dictionary) -> String:
	if obj.is_empty():
		return "{}"
	var ident: RegEx = RegEx.create_from_string("^[A-Za-z_$][A-Za-z0-9_$]*$")
	var entries: Array[String] = []
	for k: Variant in obj:
		var key: String = String(k)
		if ident.search(key) == null:
			key = "'" + key + "'"
		entries.append("%s: %s" % [key, _value(obj[k])])
	# util.inspect's reduceToSingleString / isBelowBreakLength
	var n: int = entries.size()
	var start: int = n + 1 + 10
	var total: int = n + start
	var single: bool = total + n <= 80
	if single:
		for s: String in entries:
			total += s.length()
			if total > 80:
				single = false
				break
	if single:
		return "{ " + ", ".join(entries) + " }"
	return "{\n  " + ",\n  ".join(entries) + "\n}"


static func _value(v: Variant) -> String:
	if v is Array:
		var a: Array = v
		if a.is_empty():
			return "[]"
		var parts: Array[String] = []
		for x: Variant in a:
			parts.append(_value(x))
		return "[ " + ", ".join(parts) + " ]"
	if v is float:
		return num(v)
	return str(v)
