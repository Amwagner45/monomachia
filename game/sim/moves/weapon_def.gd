class_name WeaponDef
extends RefCounted
## Port of the weapon half of src/sim/moves/types.ts (WeaponId, UltimateId,
## WeaponClass, WeaponDef). The attack half is in attack_def.gd.
##
## Port notes:
## - String unions are StringNames equal to the TS literals:
##     WeaponId: katana greatsword daggers fists
##     UltimateId: moonsplitter impaler tempest disarmed
##     WeaponClass: small medium colossal fists
## - Move ids (moves keys, the slot ids, abilities) are StringNames.
## - Weapon files write the weapon as a Dictionary literal with the TS keys in
##   snake_case and build it with from_dict().

const WEAPON_IDS: Array[StringName] = [&"katana", &"greatsword", &"daggers", &"fists"]
const ULTIMATE_IDS: Array[StringName] = [&"moonsplitter", &"impaler", &"tempest", &"disarmed"]
const WEAPON_CLASSES: Array[StringName] = [&"small", &"medium", &"colossal", &"fists"]

var id: StringName = &""
var name: String = ""
var cls: StringName = &""
## movement speed multiplier
var speed_mult: float = 1.0
## dodge distance multiplier
var dodge_mult: float = 1.0
## frames before impact in which a block press parries
var parry_window: int = 0
## fraction of an attack's posture damage taken when blocking
var block_mitigation: float = 1.0
var moves: Dictionary[StringName, AttackDef] = {}
var light_start: StringName = &""
var heavy_start: StringName = &""
var sprint_light: StringName = &""
var sprint_heavy: StringName = &""
var dodge_light: StringName = &""
var dodge_heavy: StringName = &""
var back_light: StringName = &""
var back_heavy: StringName = &""
var jump_light: StringName = &""
var jump_heavy: StringName = &""
## block-ability options: pick 2
var abilities: Array[StringName] = []
## [string, string]
var default_abilities: Array[StringName] = []
var ultimate: StringName = &""
## preferred fighting distance for the AI
var reach: float = 0.0
## blurb for menus
var blurb: String = ""

## Every key a weapon record has: the fields above, in order.
const KEYS: Array[String] = [
	"id", "name", "cls", "speed_mult", "dodge_mult", "parry_window", "block_mitigation", "moves",
	"light_start", "heavy_start", "sprint_light", "sprint_heavy", "dodge_light", "dodge_heavy",
	"back_light", "back_heavy", "jump_light", "jump_heavy", "abilities", "default_abilities",
	"ultimate", "reach", "blurb",
]


## Builds a WeaponDef from a weapon record (snake_case keys). "moves" must
## already be finalized: the result of AttackDef.finalize_moves().
static func from_dict(d: Dictionary) -> WeaponDef:
	for key: Variant in d:
		if not KEYS.has(String(key)):
			push_error("WeaponDef: unknown key %s in weapon %s" % [key, d.get("id", "?")])
	for key: String in KEYS:
		if not d.has(key):
			push_error("WeaponDef: missing key %s in weapon %s" % [key, d.get("id", "?")])
	var w: WeaponDef = WeaponDef.new()
	w.id = StringName(d["id"])
	w.name = String(d["name"])
	w.cls = StringName(d["cls"])
	w.speed_mult = float(d["speed_mult"])
	w.dodge_mult = float(d["dodge_mult"])
	w.parry_window = int(d["parry_window"])
	w.block_mitigation = float(d["block_mitigation"])
	w.moves = d["moves"]
	w.light_start = StringName(d["light_start"])
	w.heavy_start = StringName(d["heavy_start"])
	w.sprint_light = StringName(d["sprint_light"])
	w.sprint_heavy = StringName(d["sprint_heavy"])
	w.dodge_light = StringName(d["dodge_light"])
	w.dodge_heavy = StringName(d["dodge_heavy"])
	w.back_light = StringName(d["back_light"])
	w.back_heavy = StringName(d["back_heavy"])
	w.jump_light = StringName(d["jump_light"])
	w.jump_heavy = StringName(d["jump_heavy"])
	w.abilities.assign(d["abilities"])
	w.default_abilities.assign(d["default_abilities"])
	w.ultimate = StringName(d["ultimate"])
	w.reach = float(d["reach"])
	w.blurb = String(d["blurb"])
	return w
