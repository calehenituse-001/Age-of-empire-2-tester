extends Node
## The game rules as the original data file defines them: every unit and building (hit points, attack and armour
## per class, range, speed, cost, train time), every technology and its effects, and the tech tree.
## Imported once from the player's own install by tools/import_dat.py into res://assets/aoe/data/rules.json.

const RES_FOOD := 0
const RES_WOOD := 1
const RES_STONE := 2
const RES_GOLD := 3
const RES_NAMES := {0: "food", 1: "wood", 2: "stone", 3: "gold"}
const TECH_DARK_AGE := 104
const AGE_TECHS := [101, 102, 103]       # Feudal, Castle, Imperial
const AGE_NAMES := ["Dark Age", "Feudal Age", "Castle Age", "Imperial Age"]
# Original game time runs 1.5x faster than the clock at "normal" speed; durations in the data are in game seconds.
const GAME_SPEED := 1.5

var loaded := false
var units := {}        # unit id -> row
var techs := {}        # tech id -> row
var effects := {}      # effect bundle id -> [[type, a, b, c, d], ...]
var civs: Array = []
var terrains: Array = []
var age_buildings: Array = []   # per age: the building ids that belong to it
var raw := {}


func _ready() -> void:
	load_rules()


## Reads the tables again from the (newly imported) game data.
func reload() -> void:
	loaded = false
	units.clear()
	techs.clear()
	effects.clear()
	civs = []
	terrains = []
	age_buildings = []
	load_rules()


func load_rules() -> void:
	if loaded:
		return
	if not GameData.exists("data/rules.json"):
		push_warning("rules.json missing: run tools/import_dat.py (or the import wizard)")
		return
	var d: Variant = GameData.json("data/rules.json")
	if typeof(d) != TYPE_DICTIONARY:
		push_error("rules.json unreadable")
		return
	raw = d
	for k: String in d.units:
		units[int(k)] = d.units[k]
	for k: String in d.techs:
		techs[int(k)] = d.techs[k]
	for k: String in d.effects:
		effects[int(k)] = d.effects[k]
	civs = d.civs
	terrains = d.terrains
	for a: Dictionary in d.tree.ages:
		age_buildings.append(a.buildings)
	if not AppRuntime.mods.apply_rules(self):
		return
	loaded = true


func name_of(id: int) -> String:
	return String(units[id].name) if units.has(id) else "?"


static func cost_dict(cost: Array) -> Dictionary:
	var out := {}
	for c: Array in cost:
		out[int(c[0])] = int(c[1])
	return out


static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r: int in [0, 1, 3, 2]:
		if cost.get(r, 0) > 0:
			parts.append("%d %s" % [cost[r], RES_NAMES[r]])
	return ", ".join(parts)
