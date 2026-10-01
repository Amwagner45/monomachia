class_name FighterConfig
extends RefCounted
## Port of the FighterConfig interface in src/sim/fighter.ts: what a fighter is
## built from.
##
## Port notes: the optional TS fields need sentinels. An empty abilities array
## means undefined (the Fighter then uses weapon.default_abilities), and an
## empty name means undefined (the Fighter then uses weapon.name).

var weapon: WeaponDef
## [string, string], or empty for undefined
var abilities: Array[StringName] = []
## empty for undefined
var name: String = ""


## { weapon, abilities?, name? }. abilities may be any Array of ids (String or
## StringName); it is copied into a typed array.
static func make(p_weapon: WeaponDef, p_abilities: Array = [], p_name: String = "") -> FighterConfig:
	var c: FighterConfig = FighterConfig.new()
	c.weapon = p_weapon
	c.abilities.assign(p_abilities)
	c.name = p_name
	return c
