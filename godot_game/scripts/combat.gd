class_name Combat
extends RefCounted
## The original damage rule: every attack class a weapon has is checked against the same armour class of the
## target; what is left after armour is added up (an attack class the target has no armour entry for does
## nothing), and a blow always does at least 1.

const PIERCE := 3
const MELEE := 4


## `atk` and `arm` map a class id to its amount.
static func damage(atk: Dictionary, arm: Dictionary) -> float:
	var total := 0.0
	for cls: int in arm:
		if atk.has(cls):
			total += maxf(0.0, float(atk[cls]) - float(arm[cls]))
	return maxf(1.0, total)


## Stats of a unit as the data has them (no research): attack and armour as class dictionaries.
static var _base: Dictionary = {}


static func base_stats(unit_id: int) -> Dictionary:
	if not _base.has(unit_id):
		var u: Dictionary = Rules.units[unit_id].duplicate(true)
		u.atk = TechState._class_dict(u.atk)
		u.arm = TechState._class_dict(u.arm)
		_base[unit_id] = u
	return _base[unit_id]
