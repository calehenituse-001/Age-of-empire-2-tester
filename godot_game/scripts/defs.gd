class_name Defs
## Game data: costs, sizes and stats. Times are in game seconds.

# Difficulty modes. Raids come on a fixed timer: the first after `first` seconds, then every `interval`.
# A raid has `base` + `per_wave` x wave soldiers (at most `max`). `tiers` says from which wave each kind of
# soldier may join: the stronger kinds are missing on Easy, so the enemy never upgrades there.
# hp / atk scale the raiders, wild scales how many wild animals roam.
const DIFFICULTY := {
	"easy": {"name": "Easy", "first": 600.0, "interval": 300.0, "base": 2, "per_wave": 1.0, "max": 10,
		"tiers": {"74": 1, "4": 2}, "naval": {}, "hp": 0.75, "atk": 0.7, "wild": 0.4,
		"rival": {"walls": false, "techs": "eco", "tower_mult": 0.5, "gather": 0.8, "workers": 16, "first_attack": 780.0, "army": 8, "step": 3, "prod": 1, "ages": [780.0, 1560.0, 2500.0]}},
	"medium": {"name": "Medium", "first": 420.0, "interval": 210.0, "base": 3, "per_wave": 1.5, "max": 22,
		"tiers": {"74": 1, "4": 2, "93": 3, "75": 6, "24": 7, "35": 9, "280": 12}, "naval": {"539": 5, "529": 9, "442": 12}, "hp": 0.9, "atk": 0.85, "wild": 0.7,
		"rival": {"walls": true, "techs": "all", "tower_mult": 1.0, "gather": 1.0, "workers": 26, "first_attack": 600.0, "army": 12, "step": 4, "prod": 2, "ages": [600.0, 1200.0, 1900.0]}},
	"hard": {"name": "Hard", "first": 300.0, "interval": 150.0, "base": 4, "per_wave": 2.0, "max": 36,
		"tiers": {"74": 1, "4": 2, "93": 2, "75": 3, "24": 4, "35": 5, "448": 3, "38": 6, "280": 8}, "naval": {"539": 3, "529": 5, "442": 8, "527": 10}, "hp": 1.0, "atk": 1.0, "wild": 1.0,
		"rival": {"walls": true, "techs": "all", "tower_mult": 1.3, "gather": 1.25, "workers": 38, "first_attack": 480.0, "army": 16, "step": 5, "prod": 3, "ages": [450.0, 900.0, 1400.0]}},
}
# The rival's base (see Rival): what each production building trains by age (Dark, Feudal, Castle, Imperial) as unit ids,
# the age it needs, and its build order (kind, age needed, how many at most scale with the difficulty's "prod").
const RIVAL_ROSTER := {
	"barracks": [["74"], ["75", "93"], ["77", "358"], ["473", "358"]],
	"archery_range": [[], ["4", "7"], ["24", "7"], ["492", "6"]],
	"stable": [[], ["448"], ["38", "448"], ["283", "38"]],
	"siege_workshop": [[], [], ["35", "280"], ["35", "550"]],
}
const RIVAL_PLAN := [["barracks", 0, 1], ["archery_range", 1, 1], ["stable", 1, 1],
	["blacksmith", 1, 1], ["barracks", 1, 2], ["university", 2, 1], ["siege_workshop", 2, 1], ["archery_range", 2, 2], ["stable", 2, 2],
	["castle", 2, 1], ["barracks", 2, 3], ["archery_range", 3, 3], ["stable", 3, 3], ["siege_workshop", 3, 2]]
# What the rival researches at each kind of building, in the order it wants it (technology ids of the data). The economy ones come
# first on every difficulty; the rest (armour, attack, unit upgrades) when the difficulty allows ("techs": "all") and an army stands.
const RIVAL_TECHS := {
	"tc": [22, 213, 249], "mill": [14, 13, 12], "lumber_camp": [202, 203, 221], "mining_camp": [55, 278, 182, 279],
	"blacksmith": [67, 74, 199, 211, 81, 76, 68, 200, 212, 82, 201, 77, 75, 219, 80],
	"barracks": [222, 215, 207, 217, 264], "archery_range": [100, 437, 237], "stable": [435, 39, 209, 265],
	"siege_workshop": [96, 255, 257], "university": [50, 51, 93],
}
const RIVAL_ECO_TECHS := ["tc", "mill", "lumber_camp", "mining_camp"]
# Towers the original AI builds by age (Watch Tower 3 / Guard Tower 6 / Keep 9) and how a tower is called by age.
const RIVAL_TOWERS := [0, 3, 6, 9]
const RIVAL_AGE_COST := [{"food": 500}, {"food": 800, "gold": 200}, {"food": 1000, "gold": 800}]
const RIVAL_AGE_TIME := [130.0, 160.0, 190.0]
const OPPONENTS := ["rival", "raids"]
const OPPONENT_NAMES := ["Rival base", "Raids only"]


static func load_opponent() -> String:
	var cf := ConfigFile.new()
	if cf.load(GAME_CONFIG) == OK:
		var o := String(cf.get_value("game", "opponent", "rival"))
		if o in OPPONENTS:
			return o
	return "rival"


static func save_opponent(o: String) -> void:
	var cf := ConfigFile.new()
	cf.load(GAME_CONFIG)
	cf.set_value("game", "opponent", o)
	cf.save(GAME_CONFIG)


const DIFFICULTY_ORDER := ["easy", "medium", "hard"]
const GAME_CONFIG := "user://game.cfg"
const CARRY := 10              # what a villager carries before walking to a drop-off
const RES_NAMES := ["wood", "food", "gold", "stone"]

static var BUILDINGS := {
	"tc": {"name": "Town Center", "uid": 109, "ages": true, "shoots": true, "size": 4, "hp": 800, "cost": {"wood": 275}, "time": 66.0,
		"pop": 5, "train": ["villager"], "drop": ["wood", "food", "gold", "stone"],
		# the look and strength follow the age (research Feudal, Castle and Imperial Age in the Town Center)
		"levels": [
			{"name": "Town Center", "sprite": "tc", "decal": "tc_plaza1", "hp": 800},
			{"name": "Feudal Town Center", "sprite": "tc2", "decal": "tc_plaza2", "hp": 1100},
			{"name": "Castle Town Center", "sprite": "tc3", "decal": "tc_plaza3", "hp": 1500},
			{"name": "Imperial Town Center", "sprite": "tc4", "decal": "tc_plaza4", "hp": 2000},
		]},
	"house": {"name": "House", "uid": 70, "size": 2, "hp": 150, "cost": {"wood": 30}, "time": 15.0, "pop": 5},
	"lumber_camp": {"name": "Lumber Camp", "uid": 562, "size": 2, "hp": 200, "cost": {"wood": 100}, "time": 25.0, "drop": ["wood"]},
	"mining_camp": {"name": "Mining Camp", "uid": 584, "size": 2, "hp": 200, "cost": {"wood": 100}, "time": 25.0, "drop": ["gold", "stone"]},
	"mill": {"name": "Mill", "uid": 68, "size": 2, "hp": 200, "cost": {"wood": 100}, "time": 30.0, "drop": ["food"]},
	"farm": {"name": "Farm", "uid": 50, "size": 3, "hp": 100, "cost": {"wood": 60}, "time": 15.0, "food": 300},
	"barracks": {"name": "Barracks", "uid": 12, "size": 3, "hp": 1200, "cost": {"wood": 175}, "time": 40.0, "train": []},
	"archery_range": {"name": "Archery Range", "uid": 87, "size": 3, "hp": 1500, "cost": {"wood": 175}, "time": 50.0, "train": []},
	"stable": {"name": "Stable", "uid": 101, "size": 3, "hp": 1500, "cost": {"wood": 175}, "time": 50.0, "train": []},
	"blacksmith": {"name": "Blacksmith", "uid": 103, "size": 2, "hp": 1800, "cost": {"wood": 150}, "time": 40.0},
	"university": {"name": "University", "uid": 209, "size": 3, "hp": 2100, "cost": {"wood": 200}, "time": 60.0},
	"siege_workshop": {"name": "Siege Workshop", "uid": 49, "size": 4, "hp": 2100, "cost": {"wood": 200}, "time": 40.0, "train": []},
	"monastery": {"name": "Monastery", "uid": 104, "size": 3, "hp": 2100, "cost": {"wood": 175}, "time": 40.0, "train": []},
	"market": {"name": "Market", "uid": 84, "size": 4, "hp": 2100, "cost": {"wood": 175}, "time": 60.0},
	"castle": {"name": "Castle", "uid": 82, "size": 4, "hp": 4800, "cost": {"stone": 650}, "time": 200.0, "train": [], "shoots": true},
	"dock": {"name": "Dock", "uid": 45, "size": 3, "hp": 1800, "cost": {"wood": 150}, "time": 35.0, "train": []},
	"tower": {"name": "Watch Tower", "uid": 79, "size": 1, "hp": 1020, "cost": {"wood": 25, "stone": 125}, "time": 80.0, "shoots": true},
	"wall": {"name": "Stone Wall", "uid": 117, "size": 1, "hp": 300, "cost": {"stone": 5}, "time": 5.0},
	"gate": {"name": "Gate", "uid": 487, "size": 1, "hp": 2750, "cost": {"stone": 30}, "time": 30.0},      # 3 cells long (see Building.rect), along x or y
}
const BUILD_ORDER := ["house", "lumber_camp", "mining_camp", "mill", "farm", "dock", "barracks", "archery_range", "stable", "blacksmith", "university", "siege_workshop", "monastery", "market", "castle", "tower", "wall", "gate", "tc"]

# The villager (a soldier's kind is its unit id as text, see GameMap.unit_info)
static var UNITS := {
	"villager": {"name": "Villager", "uid": 83, "cost": {"food": 50}, "time": 12.0, "hp": 25, "speed": 1.7},
}

# Everything that sails (unit ids): the fishing ship fishes, the others are warships. A Dock trains what the tech tree allows
# of these.
const NAVAL := [13, 21, 250, 420, 442, 527, 528, 529, 532, 533, 539, 691, 831, 832]


static func is_ship(ukind: String) -> bool:
	return ukind.is_valid_int() and int(ukind) in NAVAL


static func is_warship(ukind: String) -> bool:
	return is_ship(ukind) and int(ukind) != 13


# arrows a tower looses per volley, by what the tower is (Watch Tower, Guard Tower, Keep)
const TOWER_SHOTS := {79: 1, 234: 2, 235: 3, 82: 3, 109: 1, 71: 1, 141: 2, 142: 3}

# units a building must not offer: the Trebuchet (needs packing), trade carts and cogs (no trade yet), the Missionary,
# the Transport Ship (no garrison yet) and the Korean hero ship
const NO_TRAIN := [42, 331, 128, 204, 775, 17, 545, 844]

# Wild animals. hp, speed, attack and food come from the data (Rules 126 Wolf, 48 Wild Boar, 65 Deer) in sync_rules;
# aggro (how close they must come to attack) is a game setting. Only deer and boars leave meat.
static var ANIMALS := {
	"wolf": {"name": "Wolf", "uid": 126, "hp": 25, "speed": 1.05, "atk": 3.0, "range": 0.9, "cd": 1.5, "aggro": 7.0, "run": true},
	"boar": {"name": "Wild Boar", "uid": 48, "hp": 75, "speed": 1.2, "atk": 7.0, "range": 0.9, "cd": 1.5, "aggro": 5.0, "run": true, "food": 340},
	"deer": {"name": "Deer", "uid": 65, "hp": 5, "speed": 1.1, "atk": 0.0, "range": 0.9, "cd": 1.5, "aggro": 0.0, "run": true, "food": 140},
}



## Pulls costs, build and train times, speeds and housing from the original data (Rules). Times in the data are
## game seconds; the original runs 1.5x faster than the clock, so they are divided by Rules.GAME_SPEED.
static func sync_rules() -> void:
	if not Rules.loaded:
		return
	for k: String in BUILDINGS:
		var d: Dictionary = BUILDINGS[k]
		if not d.has("uid"):
			continue
		var row: Dictionary = Rules.units[int(d.uid)]
		d.cost = name_cost(Rules.cost_dict(row.cost))
		d.time = float(row.time) / Rules.GAME_SPEED
		d.hp = int(row.hp)
		if k != "wall" and k != "gate":
			d.size = maxi(1, roundi(float(row.radius[0]) * 2.0))      # footprint in tiles
		if float(row.get("pop", 0)) > 0.0:
			d.pop = int(row.pop)
	BUILDINGS.farm.food = 175
	for k: String in ANIMALS:
		var a: Dictionary = ANIMALS[k]
		var ar: Dictionary = Rules.units[int(a.uid)]
		a.hp = int(ar.hp)
		a.speed = float(ar.speed) * Rules.GAME_SPEED
		for hit: Array in ar.atk:
			if int(hit[0]) == 4:
				a.atk = float(hit[1])
		if float(ar.reload) > 0.0:
			a.cd = float(ar.reload) / Rules.GAME_SPEED
		if not ar.resource_storage.is_empty() and float(ar.resource_storage[0][1]) > 0.0:
			a.food = int(ar.resource_storage[0][1])
	var v: Dictionary = UNITS.villager
	var vr: Dictionary = Rules.units[int(v.uid)]
	v.cost = name_cost(Rules.cost_dict(vr.cost))
	v.time = float(vr.time) / Rules.GAME_SPEED
	v.speed = float(vr.speed) * Rules.GAME_SPEED
	v.hp = int(vr.hp)


## {0: 50} (original resource ids) -> {"food": 50}
static func name_cost(c: Dictionary) -> Dictionary:
	var out := {}
	for r: int in c:
		if int(c[r]) > 0:
			out[Rules.RES_NAMES[r]] = int(c[r])
	return out


## "" when the building may be built now, otherwise why not.
static func lock_reason(tech: TechState, key: String) -> String:
	if key == "gate":
		return "" if tech.age() >= 1 else "Needs %s" % Rules.AGE_NAMES[1]
	var d: Dictionary = BUILDINGS[key]
	if tech.age() < int(d.get("required_age", 0)):
		return "Needs %s" % Rules.AGE_NAMES[int(d.required_age)]
	if not d.has("uid") or tech.enabled.get(int(d.uid), false):
		return ""
	if key == "farm":
		return "Needs a Mill"
	for age in range(1, 4):
		if int(d.uid) in Rules.age_buildings[age] or String(d.name) in Rules.age_buildings[age].map(func(i: int) -> String: return Rules.name_of(i)):
			return "Needs %s" % Rules.AGE_NAMES[age]
	return "Not available yet"


## Why a technology cannot be researched yet.
static func tech_lock_reason(tech: TechState, id: int) -> String:
	if id in Rules.AGE_TECHS:
		var prev: String = Rules.AGE_NAMES[Rules.AGE_TECHS.find(id)]
		return "Needs 2 %s buildings" % prev
	var t: Dictionary = Rules.techs[id]
	for r: int in t.req:
		if not tech.researched.has(r) and Rules.techs.has(r):
			var nm: String = Rules.techs[r].name
			return "Needs %s" % (nm if nm != "" else "more buildings")
	return "Not available yet"

static func cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r: String in RES_NAMES:
		if cost.has(r):
			parts.append("%d %s" % [cost[r], r])
	return ", ".join(parts)


# Start modifiers that the data does not hold (they are in the civilization texts): extra villagers and stock changes.
# Huns need no houses.
const CIV_START := {
	6: {"villagers": 3, "wood": -50, "food": -200},     # Chinese
	8: {"wood": 50, "food": 50},                        # Persians
	16: {"villagers": 1, "food": -50},                  # Mayans
	17: {"wood": -100, "no_houses": true},              # Huns
}


static func civ_name(c: int) -> String:
	return String(Rules.raw.civ_info[c - 1].name)


static func load_civ() -> int:
	var cf := ConfigFile.new()
	if cf.load(GAME_CONFIG) == OK:
		return clampi(int(cf.get_value("game", "civ", 1)), 1, Rules.raw.civ_info.size())
	return 1


static func save_civ(c: int) -> void:
	var cf := ConfigFile.new()
	cf.load(GAME_CONFIG)
	cf.set_value("game", "civ", c)
	cf.save(GAME_CONFIG)


static func load_difficulty() -> String:
	var cf := ConfigFile.new()
	if cf.load(GAME_CONFIG) == OK:
		var d := String(cf.get_value("game", "difficulty", "medium"))
		if DIFFICULTY.has(d):
			return d
	return "medium"


static func load_ui_scale() -> float:
	var cf := ConfigFile.new()
	if cf.load(GAME_CONFIG) == OK:
		return clampf(float(cf.get_value("game", "ui_scale", 1.0)), 0.7, 1.5)
	return 1.0


static func save_ui_scale(v: float) -> void:
	var cf := ConfigFile.new()
	cf.load(GAME_CONFIG)
	cf.set_value("game", "ui_scale", v)
	cf.save(GAME_CONFIG)


static func load_chatter() -> bool:
	var cf := ConfigFile.new()
	return cf.load(GAME_CONFIG) != OK or bool(cf.get_value("game", "chatter", true))


static func save_chatter(on: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(GAME_CONFIG)
	cf.set_value("game", "chatter", on)
	cf.save(GAME_CONFIG)


static func load_tombs() -> bool:
	var cf := ConfigFile.new()
	return cf.load(GAME_CONFIG) != OK or bool(cf.get_value("game", "tombstones", true))


static func save_tombs(on: bool) -> void:
	var cf := ConfigFile.new()
	cf.load(GAME_CONFIG)
	cf.set_value("game", "tombstones", on)
	cf.save(GAME_CONFIG)


static func save_difficulty(d: String) -> void:
	var cf := ConfigFile.new()
	cf.load(GAME_CONFIG)
	cf.set_value("game", "difficulty", d)
	cf.save(GAME_CONFIG)
