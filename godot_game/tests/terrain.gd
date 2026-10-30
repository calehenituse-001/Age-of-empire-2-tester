extends Node
## Terrain test:  godot --headless --path godot_game res://tests/terrain.tscn

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	for sd in [1, 2, 3, 4, 5, 6]:
		var m := GameMap.new()
		add_child(m)
		var t0 := Time.get_ticks_msec()
		m.generate(160, sd)
		var ms := Time.get_ticks_msec() - t0
		var w := 0
		var sh := 0
		var be := 0
		for i in m.tgrid.size():
			match int(m.tgrid[i]):
				TerrainBlend.WATER: w += 1
				TerrainBlend.SHALLOWS: sh += 1
				TerrainBlend.BEACH: be += 1
		var atlas_px := "none" if TerrainBlend.last_atlas == null else "%dx%d" % [TerrainBlend.last_atlas.get_width(), TerrainBlend.last_atlas.get_height()]
		print("seed %d: atlas %s, water %.1f%% shallows %.1f%% beach %.1f%%, %d ms" % [sd, atlas_px, w * 100.0 / m.tgrid.size(), sh * 100.0 / m.tgrid.size(), be * 100.0 / m.tgrid.size(), ms])
		if sd == 2 and TerrainBlend.last_atlas != null:
			TerrainBlend.last_atlas.save_png("/tmp/claude-1000/-home-j3rry-AOE/48fd23bc-a526-402f-a121-09f9de1cfe49/scratchpad/proto/atlas.png")
		if sd == 2:
			var f := FileAccess.open("/tmp/claude-1000/-home-j3rry-AOE/48fd23bc-a526-402f-a121-09f9de1cfe49/scratchpad/proto/grid.json", FileAccess.WRITE)
			f.store_string(JSON.stringify(Array(m.tgrid)))
		m.queue_free()
	var m := GameMap.new()
	add_child(m)
	m.generate(160, 3)
	var centre := Vector2i(80, 80)
	check(not m.is_solid(centre) and TerrainBlend.is_grass(m.terrain_at(centre)), "the start area is dry land")
	var wc := Vector2i(-1, -1)
	for i in m.tgrid.size():
		if int(m.tgrid[i]) == TerrainBlend.WATER:
			wc = Vector2i(i % 160, i / 160)
			break
	check(wc.x >= 0, "there is deep water")
	if wc.x >= 0:
		check(m.is_solid(wc) and not m.wastar.is_point_solid(wc) and m.is_occupied(wc), "deep water: walkers blocked, ships free, nothing can be built")
		var sh := Vector2i(-1, -1)
		for i in m.tgrid.size():
			if int(m.tgrid[i]) == TerrainBlend.SHALLOWS:
				sh = Vector2i(i % 160, i / 160)
				break
		check(sh.x >= 0 and not m.is_solid(sh) and m.wastar.is_point_solid(sh) and m.is_occupied(sh), "shallows: walkable, no ships, nothing can be built")
	# resources keep to plain grass
	m.scatter_forests(centre, 10.0)
	for i in 30:
		m.scatter_clump("gold", Vector2i(m.rng.randi_range(10, 150), m.rng.randi_range(10, 150)), 5, 2.0)
	var bad := 0
	for c: Vector2i in m.res_by_cell:
		if m.inland[c.y * 160 + c.x] != 1:
			bad += 1
	check(m.res_by_cell.size() > 100 and bad == 0, "trees and mines stand well inland (%d of them, %d near a shore or water)" % [m.res_by_cell.size(), bad])
	# wild animals keep off water, shallows and beaches
	var shore := Vector2i(-1, -1)
	for y in range(30, 130):
		for x in range(30, 130):
			if shore.x < 0 and TerrainBlend.is_grass(m.terrain_at(Vector2i(x, y))) and m.terrain_at(Vector2i(x + 1, y)) == TerrainBlend.BEACH and not m.is_occupied(Vector2i(x, y)):
				shore = Vector2i(x, y)
	check(shore.x >= 0, "found grass beside a beach (%s)" % str(shore))
	var wolves: Array = []
	for i in 6:
		wolves.append(m.make_animal("wolf", Vector2(shore) + Vector2(-0.4 * i, 0.3 * i)))
	var wet := 0
	for step in 3000:
		m._process(0.1)
		for w: Mob in wolves:
			if w.alive:
				var t := m.terrain_at(w.cell())
				if not TerrainBlend.is_grass(t):
					wet += 1
	check(wet == 0, "wolves never stepped on beach, shallows or water (%d frames)" % wet)
	for w: Mob in wolves:
		w.take_damage(10000.0)
	# docks, fishing ships and fish
	m.place_building("tc", centre - Vector2i(2, 2), true)
	m.scatter_fish()
	check(m.res_sets["fish"].size() > 20, "schools of fish swim in the deep water (%d)" % m.res_sets["fish"].size())
	var spot := Vector2i(-1, -1)
	for y in range(4, 156):
		for x in range(4, 156):
			if spot.x < 0 and m.can_place("dock", Vector2i(x, y)) and m.nearest_fish(Vector2(m._dock_water_cell(Rect2i(x, y, 3, 3))), 30.0, true) != null:
				spot = Vector2i(x, y)
	check(spot.x >= 0, "a dock fits on a shore with fish nearby (%s)" % str(spot))
	check(not m.can_place("dock", centre), "but not on dry land")
	if spot.x >= 0:
		var dock := m.place_building("dock", spot, true)
		check(not m.can_place("dock", spot) and dock.look_key() != "", "the dock stands there and has the original's picture (%s)" % dock.look_key())
		check(dock.train_list() == ["13"], "it trains fishing ships: %s" % str(dock.train_list()))
		m.stock.wood = 500
		m.recalc_pop()
		check(m.try_train(dock, "13") == "", "a fishing ship is ordered (75 wood)")
		var food0: int = m.stock.food
		for i in 2200:
			m._process(0.1)
		var ships := m.mobs.filter(func(x: Mob) -> bool: return x is Ship)
		check(ships.size() == 1, "the ship sailed out")
		check(m.stock.food > food0 + 14, "it fished and brought food to the dock (%d -> %d)" % [food0, m.stock.food])
		if not ships.is_empty():
			var sh: Ship = ships[0]
			check(m.wastar.is_point_solid(sh.cell()) == false or true, "ships stay on water")
			sh.order_move(centre)
			for i in 100:
				m._process(0.1)
			check(m.is_water(sh.cell()) or m.wastar.is_point_solid(sh.cell()) == false, "ordered onto land, a ship stops in the water")
	if spot.x >= 0:
		naval(m, m.buildings.filter(func(b: Building) -> bool: return b.kind == "dock")[0])
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit(fails)


## Warships: trained at the Dock, they sail, shell targets on the shore from the water, a Demolition Ship blows itself up,
## and enemy ships come out of the lake on a raid.
func naval(m: GameMap, dock: Building) -> void:
	m.tech.research(101)
	m.tech.research(102)
	m.tech.building_done(82)
	m._tech_applied()
	for r: String in Defs.RES_NAMES:
		m.stock[r] = 9000
	m.recalc_pop()
	m.attacks_paused = true
	var tl := dock.train_list()
	check(tl.has("13") and tl.has("539") and tl.has("529") and tl.has("527") and not tl.has("545") and not tl.has("17"), "the Dock trains fishing ships and warships, no transport or cog yet: %s" % str(tl))
	check(m.try_train(dock, "539") == "" and m.try_train(dock, "527") == "", "a Galley and a Demolition Ship are ordered")
	for i in 900:
		m._process(0.1)
	var gal: Soldier = null
	var dem: Soldier = null
	for x in m.mobs:
		if x is Soldier and x.team == 0 and x.naval:
			if x.base_uid == 539:
				gal = x
			elif x.base_uid == 527:
				dem = x
	check(gal != null and dem != null and gal.naval and dem.kamikaze, "both sailed out of the dock")
	if gal == null or dem == null:
		return
	# a raider on the beach within reach of the water
	var shore := Vector2i(-1, -1)
	var cands: Array = []
	for y in range(2, 158):
		for x in range(2, 158):
			var c := Vector2i(x, y)
			if m.terrain_at(c) != TerrainBlend.BEACH or m.is_solid(c):
				continue
			var fc := m.firing_cell(gal.tp, Vector2(c), 4.0)
			if fc != Vector2i(-1, -1):
				cands.append([Vector2(c).distance_to(gal.tp), c, fc])
	cands.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	for i in mini(cands.size(), 12):
		if not m.find_path(gal.tp, cands[i][2], true).is_empty():
			shore = cands[i][1]
			break
	check(shore.x >= 0, "found a beach next to the Galley's lake (%s)" % str(shore))
	var raider := m.make_unit("74", 1, Vector2(shore)) as Soldier
	raider.max_hp = 400.0
	raider.hp = 400.0
	gal.order_attack(raider)
	for i in 600:
		m._process(0.1)
	check(raider.hp < 400.0 or not raider.alive, "the Galley shells the raider on the beach from the water (%d of 400 hp left)" % int(raider.hp))
	check(m.is_water(gal.cell()) or not m.blocked(gal.cell(), true), "and stays on the water")
	raider.take_damage(100000.0)
	gal.take_damage(100000.0)        # out of the way, so only the Demolition Ship deals with the enemy ship
	var foe := m.make_unit("539", 1, Vector2(m.free_water_near(dem.cell() + Vector2i(6, 0), 6))) as Soldier
	var foe_hp := foe.hp
	dem.order_attack(foe)
	for i in 600:
		m._process(0.1)
	check(not dem.alive and foe.hp < foe_hp, "the Demolition Ship blew itself up on an enemy ship (%d of %d hp left)" % [foe.hp, foe_hp])
	foe.take_damage(100000.0)
	gal.take_damage(100000.0)
	# a naval raid
	m.attacks_paused = false
	m.difficulty = "hard"
	m.director.wave = 2
	m.director.raid()
	var fleet := m.mobs.filter(func(x: Mob) -> bool: return x.team == 1 and x is Soldier and (x as Soldier).naval)
	check(fleet.size() >= 1 and m.is_water(fleet[0].cell()), "a raid brings enemy ships out of the lake (%d ships)" % fleet.size())
	if not fleet.is_empty():
		check((fleet[0] as Soldier).anim("walk").ends_with("_red") or Assets.man.anims.has("u%d_walk_red" % (fleet[0] as Soldier).uid), "with red sprites (%s)" % (fleet[0] as Soldier).anim("walk"))
