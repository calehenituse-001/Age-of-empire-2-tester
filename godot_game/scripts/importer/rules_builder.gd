class_name RulesBuilder
extends RefCounted
## Turns the parsed .dat (DatReader) and the language strings into rules.json and graphics.json: units, buildings, techs, effects,
## tech tree, terrains and graphics. A port of tools/import_dat.py.

const CIV_NAMES := ["Gaia", "Britons", "Franks", "Goths", "Teutons", "Japanese", "Chinese", "Byzantines", "Persians",
	"Saracens", "Turks", "Vikings", "Mongols", "Celts", "Spanish", "Aztecs", "Mayans", "Huns", "Koreans"]
const AGE_TECHS := {"feudal": 101, "castle": 102, "imperial": 103}

const UNIT_DEFAULTS := {
	"resource_cost": [], "attacks": [], "armors": [], "resource_storage": [], "drop_sites": [], "damage_graphics": [],
	"weapon_range_max": 0.0, "weapon_range_min": 0.0, "attack_speed": 0.0, "accuracy": 0, "projectile_id0": -1,
	"creation_time": 0, "train_location_id": -1, "creatable_type": 0, "work_rate": 0.0, "resource_capacity": 0,
	"attack_sprite_id": -1, "move_graphics": -1, "speed": 0.0, "train_sound_id": -1, "selection_sound_id": -1,
	"dying_sound_id": -1, "command_sound_id": -1, "damage_sound_id": -1, "garrison_graphic": -1,
	"projectile_min_count": 0, "projectile_max_count": 0, "dead_unit_id": -1, "garrison_capacity": 0,
	"idle_graphic0": -1, "dying_graphic": -1, "enabled": false, "language_dll_name": -1, "unit_class": -1,
	"hit_points": 0, "line_of_sight": 0.0, "research_id": -1, "construction_graphic_id": -1, "stack_unit_id": -1,
	"foundation_terrain_id": -1, "head_unit_id": -1, "transform_unit_id": -1, "terrain_restriction": -1,
	"search_radius": 0.0, "trait": 0, "blast_range": 0.0, "blast_level_offence": 0,
}

var S: Dictionary = {}            # string id -> text


## Returns {"rules": Dictionary, "graphics": Dictionary} ready to be written as JSON.
func build(d: Dictionary, strings: Dictionary) -> Dictionary:
	S = strings
	var civs: Array = d.civs
	var heads: Array = d.unit_headers
	var units := {}
	for u: Dictionary in civs[1].units:
		var i: int = u.id0
		units[str(i)] = _unit_row(u, heads[i] if i < heads.size() else {})
	for u: Dictionary in civs[0].units:        # Gaia's own units: fish, animals, trees, mines
		var i: int = u.id0
		if not units.has(str(i)):
			var row := _unit_row(u, heads[i] if i < heads.size() else {})
			row["gaia"] = true
			units[str(i)] = row

	# architecture sets: civs whose Feudal-and-later buildings share their graphics look the same
	var sig_of := {}
	var style_of := {}
	for ci in range(1, civs.size()):
		var byid := {}
		for u: Dictionary in civs[ci].units:
			byid[int(u.id0)] = u
		var sig := []
		for i in [463, 498, 71, 141, 142, 87, 103, 84, 104, 82, 45]:
			sig.append(byid[i].idle_graphic0)
		var key := str(sig)
		if not sig_of.has(key):
			sig_of[key] = sig_of.size()
		style_of[ci] = sig_of[key]
	var style_gfx := {}
	var seen := {}
	for ci in range(1, civs.size()):
		var st: int = style_of[ci]
		if seen.has(st):
			continue
		seen[st] = true
		var g := {}
		for u: Dictionary in civs[ci].units:
			if int(u.unit_type) == 80:
				var row := _unit_row(u, {})
				var gfx: Dictionary = row.gfx.duplicate()
				gfx["construction"] = u.get("construction_graphic_id", -1)
				g[str(int(u.id0))] = gfx
		style_gfx[str(st)] = g
	var civ_info := []
	for ci in range(1, civs.size()):
		var text: String = String(S.get(20149 + ci, "")).replace("<b>", "").replace("<br>", "\n")
		civ_info.append({"id": ci, "name": S.get(10230 + ci, CIV_NAMES[ci]), "style": style_of[ci],
			"tech_tree": civs[ci].tech_tree_id, "text": text})

	var techs := {}
	var researches: Array = d.researches
	for i in researches.size():
		var r: Dictionary = researches[i]
		var any_cost := false
		for c: Dictionary in r.research_resource_costs:
			if int(c.amount) != 0:
				any_cost = true
		if int(r.research_location_id) < 0 and not any_cost and int(r.tech_effect_id) < 0:
			continue
		var cost := []
		for c: Dictionary in r.research_resource_costs:
			if c.enabled and int(c.amount) != 0:
				cost.append([c.type_id, c.amount])
		var req := []
		for x: int in r.required_techs:
			if x >= 0:
				req.append(x)
		techs[str(i)] = {
			"id": i, "name": S.get(r.language_dll_name, ""), "desc": S.get(r.language_dll_description, ""),
			"cost": cost, "time": r.research_time, "loc": r.research_location_id, "effect": r.tech_effect_id,
			"req": req, "req_count": r.required_tech_count, "civ": r.civilization_id, "button": r.button_id, "type": r.tech_type,
		}
	var effects := {}
	var bundles: Array = d.effect_bundles
	for i in bundles.size():
		var list := []
		for e: Dictionary in bundles[i].effects:
			if int(e.type_id) != 255:
				list.append([e.type_id, e.attr_a, e.attr_b, e.attr_c, e.attr_d])
		if not list.is_empty():
			effects[str(i)] = list

	var terrains := []
	var dterr: Array = d.terrains
	for i in dterr.size():
		var t: Dictionary = dterr[i]
		var row := {}
		for k in ["internal_name", "filename", "slp_id", "blend_priority", "blend_mode", "map_color_hi", "map_color_med", "map_color_low", "sound_id", "is_animated", "animation_frame_count"]:
			row[k] = t[k]
		row["id"] = i
		terrains.append(row)
	var tree := {"buildings": d.building_connections, "units": d.unit_connections, "techs": d.tech_connections, "ages": d.age_connections}
	var rciv := []
	for i in civs.size():
		var c: Dictionary = civs[i]
		rciv.append({"id": i, "name": CIV_NAMES[i] if i < CIV_NAMES.size() else str(i), "tech_tree": c.tech_tree_id,
			"team_bonus": c.team_bonus_id, "start": c.resources.slice(0, 6)})
	var restr := []
	for r: Dictionary in d.terrain_restrictions:
		var a := []
		if r.has("passable_buildable_dmg_multiplier"):
			for x: float in r.passable_buildable_dmg_multiplier:
				a.append(_r(x, 2))
		restr.append(a)
	var names := {}
	for k: int in S:
		if (k >= 3000 and k < 10000) or (k >= 120000 and k < 190000):
			names[str(k)] = S[k]
	var rules := {
		"source": "AoE2 HD dat " + d.versionstr, "age_techs": AGE_TECHS, "civs": rciv, "civ_info": civ_info, "style_gfx": style_gfx,
		"units": units, "techs": techs, "effects": effects, "terrains": terrains, "terrain_restrictions": restr, "tree": tree, "names": names,
	}
	var graphics := {}
	for g: Dictionary in d.graphics:
		if int(g.slp_id) >= 0 or String(g.filename) != "":
			graphics[str(int(g.graphic_id))] = {"name": g.filename, "slp": g.slp_id, "layer": g.layer, "frames": g.frame_count,
				"angles": g.angle_count, "speed": _r(g.frame_rate, 3), "replay": _r(g.replay_delay, 3),
				"seq": g.sequence_type, "mirror": g.mirroring_mode, "deltas": g.graphic_deltas}
	return {"rules": rules, "graphics": graphics}


static func _r(x: float, digits: int) -> float:
	var m := pow(10.0, digits)
	return roundf(x * m) / m


func _unit_row(u0: Dictionary, header: Dictionary) -> Dictionary:
	var u: Dictionary = UNIT_DEFAULTS.duplicate()
	u.merge(u0, true)
	var cost := []
	for c: Dictionary in u.resource_cost:
		if c.enabled and int(c.amount) != 0:
			cost.append([c.type_id, c.amount])
	var atk := []
	for a: Dictionary in u.attacks:
		atk.append([a.type_id, a.amount])
	var arm := []
	for a: Dictionary in u.armors:
		arm.append([a.type_id, a.amount])
	var storage := []
	for r: Dictionary in u.resource_storage:
		if int(r.type) >= 0:
			storage.append([r.type, r.amount])
	var drops := []
	for x: int in u.drop_sites:
		if x >= 0:
			drops.append(x)
	var row := {
		"id": u.id0, "name": S.get(u.language_dll_name, ""), "type": u.unit_type, "class": u.unit_class,
		"hp": u.hit_points, "los": u.line_of_sight, "speed": _r(u.speed, 4),
		"radius": [_r(u.radius_x, 3), _r(u.radius_y, 3)],
		"atk": atk, "arm": arm,
		"range": _r(u.weapon_range_max, 3), "min_range": _r(u.weapon_range_min, 3),
		"reload": _r(u.attack_speed, 3), "accuracy": u.accuracy, "projectile": u.projectile_id0,
		"cost": cost, "time": u.creation_time, "loc": u.train_location_id, "creatable": u.creatable_type,
		"enabled": u.enabled, "work_rate": _r(u.work_rate, 4), "capacity": u.resource_capacity,
		"gfx": {"idle": u.idle_graphic0, "die": u.dying_graphic, "move": u.move_graphics,
			"attack": u.attack_sprite_id, "garrison": u.garrison_graphic},
		"dead": u.dead_unit_id, "garrison": u.garrison_capacity, "sound": {
			"train": u.train_sound_id, "select": u.selection_sound_id, "die": u.dying_sound_id,
			"command": u.command_sound_id, "damage": u.damage_sound_id},
		"resource_storage": storage, "drop_sites": drops,
		"projectiles": [u.projectile_min_count, u.projectile_max_count],
		"blast": _r(float(u.get("blast_range", 0.0)), 3), "blast_level": u.get("blast_level_offence", 0),
		"damage_gfx": u.get("damage_graphics", []),
	}
	var cmds := []
	for c: Dictionary in header.get("unit_commands", []):
		if int(c.type) != 7 or int(c.unit_id) != -1:
			var m := {}
			for k in ["type", "class_id", "unit_id", "resource_in", "resource_multiplier", "resource_out", "work_value1", "work_value2"]:
				m[k] = c[k]
			cmds.append(m)
	if not cmds.is_empty():
		row["cmds"] = cmds
	if int(u.unit_type) == 80:
		row["research_id"] = u.research_id
		row["construction_gfx"] = u.construction_graphic_id
		row["stack"] = u.stack_unit_id
		row["head"] = u.head_unit_id
		row["foundation_terrain"] = u.foundation_terrain_id
		var pop := 0
		for r: Dictionary in u.resource_storage:
			if int(r.type) == 4:
				pop += int(r.amount)
		row["pop"] = pop
		row["size"] = [_r(u.clearance_size_x, 2), _r(u.clearance_size_y, 2)]
		var annex := []
		for a: Dictionary in u.get("building_annex", []):
			if int(a.unit_id) > 0:
				annex.append([a.unit_id, _r(a.misplaced0, 3), _r(a.misplaced1, 3)])
		row["annex"] = annex
	row["terrain_restriction"] = u.terrain_restriction
	row["search_radius"] = u.search_radius
	return row
