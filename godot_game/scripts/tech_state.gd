class_name TechState
extends RefCounted
## One player's technologies: which are researched, which units and buildings are unlocked, what they became in
## the new ages, and every unit's current stats. Follows the original rules:
##  - a tech's effects are applied when it is researched;
##  - "free" techs (no cost, no building) are researched on their own once their prerequisites are met. This is how
##    the original unlocks buildings and checks that two buildings of an age stand before the next age may start;
##  - a finished building researches its marker tech (the unit's research_id).

const ATTR := {0: "hp", 1: "los", 2: "garrison", 5: "speed", 10: "reload", 11: "accuracy", 12: "range", 13: "work_rate",
	14: "capacity", 20: "min_range", 101: "time"}
const COST_ATTR := {103: 0, 104: 1, 105: 2, 106: 3}
const SET := 0
const ADD := 1
const MUL := 2

var civ := 1
var researched := {}      # tech id -> true
var enabled := {}         # unit id -> bool
var upgrades := {}        # unit id -> the unit it became
var units := {}           # unit id -> this player's copy of the stats
var res := {}             # original resource id -> value (6 is the age)
var disabled_techs := {}
var tech_cost := {}       # tech id -> cost dictionary override
var tech_time := {}       # tech id -> seconds override
var generation := 0       # grows whenever stats change, so units know to refresh


func _init(civ_id := 1) -> void:
	civ = civ_id
	for id: int in Rules.units:
		var u: Dictionary = Rules.units[id].duplicate(true)
		u.atk = _class_dict(u.atk)
		u.arm = _class_dict(u.arm)
		u.cost = Rules.cost_dict(u.cost)
		u.extra = {}
		units[id] = u
		enabled[id] = bool(u.enabled)
	var tree: int = int(Rules.civs[civ].tech_tree)
	apply_bundle(tree)
	research(Rules.TECH_DARK_AGE)


static func _class_dict(pairs: Array) -> Dictionary:
	var d := {}
	for p: Array in pairs:
		d[int(p[0])] = float(p[1])
	return d


# ------------------------------------------------------------------ queries
func age() -> int:
	return int(res.get(6, 0))


func is_researched(tech: int) -> bool:
	return researched.has(tech)


func stats(id: int) -> Dictionary:
	return units[id]


## What a unit or building has become (Militia -> Man-at-Arms ...). Follows the whole chain.
func current(id: int) -> int:
	var guard := 0
	while upgrades.has(id) and guard < 16:
		id = upgrades[id]
		guard += 1
	return id


func prereqs_met(tech: Dictionary) -> bool:
	var need: int = int(tech.req_count)
	var have := 0
	for r: int in tech.req:
		if researched.has(r):
			have += 1
	return have >= need


func tech_ok(tech_id: int) -> bool:
	if not Rules.techs.has(tech_id) or disabled_techs.has(tech_id):
		return false
	var t: Dictionary = Rules.techs[tech_id]
	return int(t.civ) < 0 or int(t.civ) == civ


func can_research(tech_id: int) -> bool:
	return tech_ok(tech_id) and not researched.has(tech_id) and prereqs_met(Rules.techs[tech_id])


func cost_of(tech_id: int) -> Dictionary:
	return tech_cost.get(tech_id, Rules.cost_dict(Rules.techs[tech_id].cost))


func time_of(tech_id: int) -> float:
	return float(tech_time.get(tech_id, Rules.techs[tech_id].time))


## Technologies a building (given by its base unit id) offers that are not done yet, in button order.
func techs_at(base_building: int, only_ready := false) -> Array:
	var out: Array = []
	for id: int in Rules.techs:
		var t: Dictionary = Rules.techs[id]
		if int(t.loc) != base_building or researched.has(id) or not tech_ok(id) or t.name == "":
			continue
		if only_ready and not prereqs_met(t):
			continue
		out.append(id)
	out.sort_custom(func(a: int, b: int) -> bool:
		return int(Rules.techs[a].button) < int(Rules.techs[b].button) or (int(Rules.techs[a].button) == int(Rules.techs[b].button) and a < b))
	return out


## Units a building (base unit id) can train now, each already in its newest form.
func train_list(base_building: int) -> Array:
	var out: Array = []
	var names := {}
	for id: int in Rules.units:
		var r: Dictionary = Rules.units[id]
		if int(r.loc) != base_building or not enabled.get(id, false):
			continue
		var cur := current(id)
		var nm: String = String(Rules.units[cur].name)
		if names.has(nm) or out.has(cur):
			continue
		names[nm] = true
		out.append(cur)
	out.sort()
	return out


## Buildings that can be placed now (base unit ids; use current() for what actually gets built).
func build_list() -> Array:
	var out: Array = []
	var names := {}
	for id: int in Rules.units:
		var r: Dictionary = Rules.units[id]
		if int(r.type) != 80 or int(r.loc) != 118 or not enabled.get(id, false):
			continue
		var nm: String = String(r.name)
		if names.has(nm):
			continue
		names[nm] = true
		out.append(id)
	out.sort()
	return out


## Rebuilds the state from the list of researched tech ids (a saved game).
func restore(ids: Array) -> void:
	for id in ids:
		var t := int(id)
		if not researched.has(t) and Rules.techs.has(t):
			researched[t] = true
			apply_bundle(int(Rules.techs[t].effect))
	generation += 1
	_auto()


# ------------------------------------------------------------------ changes
func research(tech_id: int) -> void:
	if researched.has(tech_id) or not Rules.techs.has(tech_id):
		return
	researched[tech_id] = true
	apply_bundle(int(Rules.techs[tech_id].effect))
	generation += 1
	_auto()


## A building has been finished: its marker tech counts as researched.
func building_done(unit_id: int) -> void:
	var rid: int = int(Rules.units[unit_id].get("research_id", -1))
	if rid >= 0 and not researched.has(rid):
		researched[rid] = true
		_auto()


func _auto() -> void:
	var changed := true
	while changed:
		changed = false
		for id: int in Rules.techs:
			var t: Dictionary = Rules.techs[id]
			if researched.has(id) or int(t.loc) >= 0 or not t.cost.is_empty() or not tech_ok(id):
				continue
			if (t.req.is_empty() and int(t.req_count) <= 0 or not t.req.is_empty() and prereqs_met(t)) and int(t.effect) >= 0:
				if t.req.is_empty() and id != Rules.TECH_DARK_AGE and int(t.civ) != civ:
					continue
				researched[id] = true
				apply_bundle(int(t.effect))
				generation += 1
				changed = true


func apply_bundle(bundle: int) -> void:
	for e: Array in Rules.effects.get(bundle, []):
		_apply(int(e[0]), int(e[1]), int(e[2]), int(e[3]), float(e[4]))


func _apply(type: int, a: int, b: int, c: int, d: float) -> void:
	match type:
		0: _unit_attr(a, b, c, d, SET)
		4: _unit_attr(a, b, c, d, ADD)
		5: _unit_attr(a, b, c, d, MUL)
		1: res[a] = d if b == 0 else float(res.get(a, 0.0)) + d
		6: res[a] = float(res.get(a, 0.0)) * d
		2: enabled[a] = b == 1
		3: upgrades[a] = b
		101:
			var cost: Dictionary = tech_cost.get(a, Rules.cost_dict(Rules.techs[a].cost) if Rules.techs.has(a) else {}).duplicate()
			cost[c] = int(d) if b == 0 else int(cost.get(c, 0)) + int(d)
			tech_cost[a] = cost
		102: disabled_techs[int(d)] = true
		103: tech_time[a] = d if b == 0 else float(tech_time.get(a, Rules.techs[a].time if Rules.techs.has(a) else 0)) + d


func _unit_attr(unit: int, cls: int, attr: int, d: float, mode: int) -> void:
	if unit >= 0:
		if units.has(unit):
			_modify(units[unit], attr, d, mode)
	elif cls >= 0:
		for id: int in units:
			if int(units[id]["class"]) == cls:
				_modify(units[id], attr, d, mode)


func _modify(u: Dictionary, attr: int, d: float, mode: int) -> void:
	if attr == 8 or attr == 9:
		var key := "arm" if attr == 8 else "atk"
		var tbl: Dictionary = u[key]
		if mode == MUL:
			for k in tbl:
				tbl[k] = float(tbl[k]) * d
			return
		var klass: int = int(d) >> 8
		var amt := float(int(d) & 0xFF)
		if mode == SET:
			tbl[klass] = amt
		else:
			tbl[klass] = float(tbl.get(klass, 0.0)) + amt
		return
	if COST_ATTR.has(attr):
		var r: int = COST_ATTR[attr]
		var cost: Dictionary = u.cost
		cost[r] = _mode(float(cost.get(r, 0)), d, mode)
		return
	if ATTR.has(attr):
		var k: String = ATTR[attr]
		u[k] = _mode(float(u[k]), d, mode)
		return
	u.extra[attr] = _mode(float(u.extra.get(attr, 0.0)), d, mode)


static func _mode(v: float, d: float, mode: int) -> float:
	match mode:
		SET: return d
		ADD: return v + d
	return v * d
