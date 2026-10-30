class_name SaveGame
## Saves and loads a whole game as JSON in the app's private storage (one manual slot, one autosave).

const MANUAL := "user://save.json"
const AUTO := "user://autosave.json"
const VERSION := 6


static func exists(path: String) -> bool:
	return FileAccess.file_exists(path)


static func info(path: String) -> String:
	var d := read(path)
	if d.is_empty():
		return ""
	var t := int(d.get("game_time", 0.0))
	return "%d:%02d game time, %d x %d map" % [t / 60, t % 60, int(d.size), int(d.size)]


static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and int(parsed.get("version", 0)) == VERSION:
		return parsed
	return {}


static func write(path: String, main: Node) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(snapshot(main)))
	return true


static func _v(v: Vector2) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001)]


static func snapshot(main: Node) -> Dictionary:
	var map: GameMap = main.map
	var d := {"version": VERSION, "civ": map.civ, "seed": map.world_seed, "size": map.size, "difficulty": map.difficulty, "game_time": map.game_time,
		"stock": map.stock, "wave": map.director.wave, "next_raid": map.director.next_raid, "trees_cut": map.trees_cut,
		"attacks_paused": map.attacks_paused, "cam": _v(main.cam.position), "zoom": main.cam.zoom.x, "opponent": map.opponent}
	if map.rival:
		d["rival"] = map.rival.snapshot()
		var fs: Array = []
		for b: FoeBuilding in map.foes:
			if b.alive:
				fs.append({"k": b.kind, "o": [b.origin.x, b.origin.y], "done": b.done, "work": b.work, "hp": b.hp, "q": b.queue, "qt": b.qt, "food": b.food, "rt": b.res_tech, "rtt": b.res_t, "ax": b.gate_axis})
		d["foes"] = fs
	var res: Array = []
	for n: ResNode in map.res_by_cell.values():
		if n.alive and not n is Carcass:
			res.append([n.rname, n.variant, n.cell.x, n.cell.y, n.amount])
	d["res"] = res
	var bs: Array = []
	for b in map.buildings:
		if not b.alive:
			continue
		bs.append({"k": b.kind, "o": [b.origin.x, b.origin.y], "done": b.done, "work": b.work, "hp": b.hp, "lvl": b.level,
			"q": b.queue, "qt": b.qt, "food": b.food, "rt": b.res_tech, "rtt": b.res_t, "ax": b.gate_axis, "lk": b.locked, "rel": b.relics.size()})
	d["buildings"] = bs
	d["tech"] = map.tech.researched.keys()
	var ms: Array = []
	for m in map.mobs:
		if m.alive:
			ms.append(_mob_entry(m))
	var holders: Array = []
	holders.append_array(map.buildings)
	holders.append_array(map.foes)
	for h in holders:                       # units inside a building are saved with where they are
		if h.alive:
			for m in h.garrison:
				var ge := _mob_entry(m)
				ge["gb"] = [h.origin.x, h.origin.y]
				ge["gf"] = h.team == 1
				ms.append(ge)
	d["mobs"] = ms
	d["relics"] = map.relics.filter(func(r: Relic) -> bool: return r.on_ground()).map(func(r: Relic) -> Array: return _v(r.tp))
	return d


static func _mob_entry(m: Mob) -> Dictionary:
	var e := {"k": m.kind, "t": m.team, "p": _v(m.tp), "hp": m.hp}
	if m is Soldier and m.team == 1:
		e["fm"] = m.foe_mode
		e["gp"] = _v(m.guard_pos)
	if m is Soldier and m.relic != null:
		e["relic"] = true
	if m is Villager:
		e["male"] = m.male
		e["cn"] = m.carry_n
		e["ck"] = m.carry_kind
		e["gk"] = m.gather_kind
		e["job"] = m.job
		if m.job == "gather" and m.res and is_instance_valid(m.res):
			e["jt"] = [m.res.cell.x, m.res.cell.y]
		elif m.job == "farm" and m.farm and is_instance_valid(m.farm):
			e["jt"] = [m.farm.origin.x, m.farm.origin.y]
		elif (m.job == "build" or m.job == "repair") and m.site and is_instance_valid(m.site):
			e["jt"] = [m.site.origin.x, m.site.origin.y]
	elif m is Animal:
		e["home"] = _v(m.home)
	return e


## Rebuilds the world from a snapshot. `main` has just made an empty map.
static func restore(main: Node, d: Dictionary) -> void:
	var map: GameMap = main.map
	map.difficulty = String(d.difficulty)
	map.game_time = float(d.game_time)
	for r: String in Defs.RES_NAMES:
		map.stock[r] = int(d.stock.get(r, 0))
	map.trees_cut = int(d.trees_cut)
	map.tech.restore(d.get("tech", []))
	map.attacks_paused = bool(d.attacks_paused)
	map.director.wave = int(d.wave)
	map.director.next_raid = float(d.next_raid)
	for e: Array in d.res:
		var n := map.spawn_res_node(String(e[0]), int(e[1]), Vector2i(int(e[2]), int(e[3])))
		n.amount = int(e[4])
	var sites := {}
	for e: Dictionary in d.buildings:
		var o := Vector2i(int(e.o[0]), int(e.o[1]))
		var b := map.place_building(String(e.k), o, bool(e.done), String(e.get("ax", "x")))
		sites[o] = b
		if bool(e.get("lk", false)):
			map.set_gate_locked(b, true)
		for i in int(e.get("rel", 0)):
			map.add_relic(b.tp).store(b)
		b.work = float(e.work)
		b.hp = float(e.hp)
		b.food = float(e.food)
		b.queue.assign(e.q)
		b.qt = float(e.qt)
		if b.done and int(e.get("rt", -1)) >= 0:
			b.start_research(int(e.rt))
			b.res_t = float(e.get("rtt", 0.0))
		b._update_visual()
		b._update_fire()
		b._show_bar()
	map.opponent = String(d.get("opponent", "raids"))
	if d.has("rival"):
		map.rival = Rival.new()
		map.rival.map = map
		map.add_child(map.rival)
		map.rival.restore(d.rival)
		for e: Dictionary in d.get("foes", []):
			var fb := map.place_foe_building(String(e.k), Vector2i(int(e.o[0]), int(e.o[1])), bool(e.done), String(e.get("ax", "x")))
			fb.set_age(map.rival.age)
			fb.work = float(e.work)
			fb.hp = float(e.hp)
			fb.queue.assign(e.q)
			fb.qt = float(e.qt)
			fb.food = float(e.get("food", fb.food))
			fb.res_tech = int(e.get("rt", -1))
			fb.res_t = float(e.get("rtt", 0.0))
			fb._update_visual()
	for e: Dictionary in d.mobs:
		var k := String(e.k)
		var p := Vector2(float(e.p[0]), float(e.p[1]))
		var m: Mob
		if int(e.t) == 2:
			m = map.make_animal(k, Vector2(float(e.home[0]), float(e.home[1])))
			m.place(p)
		else:
			m = map.make_unit(k, int(e.t), p)
			if m is Soldier and e.has("fm"):
				m.foe_mode = String(e.fm)
				m.guard_pos = Vector2(float(e.gp[0]), float(e.gp[1]))
			if m is Villager:
				m.male = bool(e.male)
				m.pre = "vm_" if m.male else "vf_"
				m.stand()
		m.hp = minf(float(e.hp), m.max_hp)
		if m is Soldier and bool(e.get("relic", false)):
			map.add_relic(m.tp).pick_up(m)
			m.relic = map.relics[map.relics.size() - 1]
		if m is Villager:
			m.carry_n = int(e.cn)
			m.carry_kind = String(e.ck)
			m.gather_kind = String(e.gk)
			if not e.has("gb"):
				_resume_job(map, m, e, sites)
		if e.has("gb"):                    # it was inside a building
			var go := Vector2i(int(e.gb[0]), int(e.gb[1]))
			var holder: Building = null
			if bool(e.get("gf", false)):
				for f in map.foes:
					if f.origin == go:
						holder = f
			else:
				holder = sites.get(go)
			if holder and not holder.garrison_add(m):         # (old saves: villagers used to be allowed in) it steps out beside the building
				m.place(Vector2(map.free_cell_near(Vector2i(holder.origin) + Vector2i(holder.bsize, holder.bsize / 2), 6)))
	for p: Array in d.get("relics", []):
		map.add_relic(Vector2(float(p[0]), float(p[1])))
	map.recalc_pop()


static func _resume_job(map: GameMap, v: Villager, e: Dictionary, sites: Dictionary) -> void:
	if not e.has("jt"):
		return
	var t := Vector2i(int(e.jt[0]), int(e.jt[1]))
	match String(e.job):
		"gather":
			var r: ResNode = map.res_by_cell.get(t)
			if r:
				v.order_gather(r)
		"farm":
			if sites.has(t):
				v.order_farm(sites[t])
		"build":
			if sites.has(t) and not sites[t].done:
				v.order_build(sites[t])
		"repair":
			if sites.has(t):
				v.order_repair(sites[t])
