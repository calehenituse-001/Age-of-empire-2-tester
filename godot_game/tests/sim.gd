extends Node
## Headless gameplay test:  godot --headless --path godot_game res://tests/sim.tscn
## Plays the game logic without rendering and prints PASS/FAIL lines.

var main: Node
var map: GameMap
var ctl: Controller
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func run(seconds: float, dt := 0.1) -> void:
	for i in int(seconds / dt):
		map._process(dt)


func _ready() -> void:
	Main.map_size = 96
	Main.opponent = "raids"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	map = main.map
	ctl = main.ctl
	seed(1)
	map.attacks_paused = true
	test_economy()
	test_gather()
	test_build()
	test_train()
	test_extras()
	test_builders_and_repair()
	test_sound()
	test_difficulty()
	test_military()
	test_roster()
	test_hunting()
	test_smart_and_decon()
	test_chatter()
	test_tombstone()
	await test_save_load()
	test_defense()
	test_pause()
	print("RESULT: %s" % ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	get_tree().quit(fails)


## A free spot near the town centre for a building of this kind (centre cell, in tile coordinates).
func spot(kind: String) -> Vector2:
	var sz := int(Defs.BUILDINGS[kind].size)
	var c := Vector2i(map.size / 2, map.size / 2)
	for r in range(5, 14):
		for x in range(c.x - r, c.x + r + 1):
			for y in range(c.y - r, c.y + r + 1):
				if maxi(absi(x - c.x), absi(y - c.y)) != r:
					continue
				var o := Vector2i(x, y)
				var ok := map.can_place(kind, o)
				if ok:
					# keep a one-cell lane around it so builders can reach every side
					for i in range(-1, sz + 1):
						for j in range(-1, sz + 1):
							var cc := o + Vector2i(i, j)
							if map.in_bounds(cc) and map.is_occupied(cc):
								ok = false
				if ok:
					return Vector2(o) + Vector2.ONE * ((sz - 1) * 0.5)
	return Vector2(c)


func villagers() -> Array[Villager]:
	var out: Array[Villager] = []
	for m in map.mobs:
		if m is Villager:
			out.append(m)
	return out


func test_gather() -> void:
	var v := villagers()
	var c := Vector2i(map.size / 2, map.size / 2)
	var tree := map.find_resource("wood", c, 40)
	var berries := map.find_resource("food", c, 40)
	var gold := map.find_resource("gold", c, 40)
	check(tree != null and berries != null and gold != null, "map has trees, berries and gold near the start")
	var w0: int = map.stock.wood
	var f0: int = map.stock.food
	var g0: int = map.stock.gold
	v[0].order_gather(tree)
	v[1].order_gather(berries)
	v[2].order_gather(gold)
	run(120.0)
	check(map.stock.wood > w0, "wood gathered and delivered (%d -> %d)" % [w0, map.stock.wood])
	check(map.stock.food > f0, "food gathered and delivered (%d -> %d)" % [f0, map.stock.food])
	check(map.stock.gold > g0, "gold gathered and delivered (%d -> %d)" % [g0, map.stock.gold])


func test_build() -> void:
	map.stock.wood = 1000
	map.stock.stone = 500
	var cap0 := map.pop_cap
	var v := villagers()
	ctl.select_units([v[3], v[4]])
	ctl.start_place("house")
	ctl.move_ghost(Iso.to_world(spot("house")))
	check(ctl.placing == "house", "placement mode starts")
	ctl.confirm_place()
	var houses := map.buildings.filter(func(b: Building) -> bool: return b.kind == "house")
	check(houses.size() == 1, "house site placed")
	run(60.0)
	check(houses[0].done, "house finished by two builders")
	check(map.pop_cap == cap0 + 5, "house raised the population cap (%d -> %d)" % [cap0, map.pop_cap])
	for kind in ["lumber_camp", "mill", "farm", "barracks", "tower"]:
		ctl.select_units([v[3], v[4]])
		ctl.start_place(kind)
		ctl.move_ghost(Iso.to_world(spot(kind)))
		ctl.confirm_place()
		run(100.0)
		var bs := map.buildings.filter(func(b: Building) -> bool: return b.kind == kind)
		check(bs.size() == 1 and bs[0].done, "%s built" % kind)
	# progress bar while building, repair of a damaged building
	ctl.select_units([v[3]])
	ctl.start_place("house")
	ctl.move_ghost(Iso.to_world(spot("house")))
	ctl.confirm_place()
	var site: Building = map.buildings.filter(func(b: Building) -> bool: return b.kind == "house" and not b.done)[0]
	for i in 40:
		run(1.0)
		if site.work > 2.0:
			break
	check(site._prog != null and site._prog.frac > 0.0 and site._prog.frac < 1.0, "construction progress bar (%.2f)" % (site._prog.frac if site._prog else -1.0))
	run(60.0)
	check(site.done and site._prog == null, "progress bar removed when finished")
	site.hp = site.max_hp * 0.4
	ctl.select_units([v[3]])
	ctl._building_tap(site)
	run(10.0)
	check(site.hp > site.max_hp * 0.4 and site.hp < site.max_hp, "villager repairs slowly (%d/%d)" % [site.hp, site.max_hp])
	run(60.0)
	check(site.hp >= site.max_hp, "repair completes")
	var farm: Building = map.buildings.filter(func(b: Building) -> bool: return b.kind == "farm")[0]
	check(farm.farmer != null or farm.food < 300.0, "builder started farming the new farm")


func test_train() -> void:
	map.stock.food = 1000
	map.stock.gold = 500
	map.stock.wood = 500
	var n0 := map.mobs.size()
	var tc: Building = map.buildings.filter(func(b: Building) -> bool: return b.kind == "tc")[0]
	check(map.try_train(tc, "villager") == "", "train villager accepted")
	run(20.0)
	check(map.mobs.size() == n0 + 1, "villager appeared")
	var bar: Building = map.buildings.filter(func(b: Building) -> bool: return b.kind == "barracks")[0]
	for i in 3:
		check(map.try_train(bar, "74") == "", "train militia %d" % i)
	for i in 2:
		check(map.try_train(bar, "93") == "", "train spearman %d" % i)
	run(100.0)
	var army := 0
	for m in map.mobs:
		if m is Soldier and m.team == 0:
			army += 1
	check(army >= 5, "army of %d soldiers (7 minus any lost to wolves)" % army)


func test_extras() -> void:
	map.stock.stone = 500
	map.stock.wood = 1000
	var v := villagers()
	# walls: a line of six pieces along x, built by two villagers
	var start := Vector2i(-1, -1)
	var c := Vector2i(map.size / 2, map.size / 2)
	for y in range(c.y + 8, c.y + 30):
		for x in range(c.x - 12, c.x + 6):
			var ok := true
			for i in range(-1, 8):
				for j in range(-1, 2):
					if not map.in_bounds(Vector2i(x + i, y + j)) or map.is_occupied(Vector2i(x + i, y + j)):
						ok = false
			if ok and start.x < 0:
				start = Vector2i(x, y)
	check(start.x >= 0, "free row for a wall found")
	ctl.select_units([v[0], v[1]])
	var stone0: int = map.stock.stone
	ctl.start_place("wall")
	ctl.move_ghost(Iso.to_world(Vector2(start)))
	ctl.move_ghost(Iso.to_world(Vector2(start + Vector2i(5, 0))))
	check(ctl.wall_cells.size() == 6, "wall line previews 6 pieces (%d)" % ctl.wall_cells.size())
	ctl.confirm_place()
	check(map.stock.stone == stone0 - 30, "wall costs 5 stone per piece")
	run(5.0)
	var sites := map.buildings.filter(func(b: Building) -> bool: return b.kind == "wall")
	check(sites.size() == 6, "six wall sites placed")
	run(90.0)
	check(sites.all(func(b: Building) -> bool: return b.done), "all wall pieces built")
	var mid: Building = map.walls[start + Vector2i(2, 0)]
	check(mid.piece == 1, "wall run along x uses the straight piece")
	check((map.walls[start] as Building).piece == 2, "the end of a wall is a post like a corner")
	map.walls[start + Vector2i(5, 0)].take_damage(1000000.0)
	check(not map.walls.has(start + Vector2i(5, 0)), "destroyed wall piece removed")
	ctl.cancel_place()
	# an L-shaped wall with a diagonal tail: tap, tap, tap, tap
	var o := start + Vector2i(0, 4)
	ctl.select_units([v[0]])
	ctl.start_place("wall")
	ctl.move_ghost(Iso.to_world(Vector2(o)))
	ctl.move_ghost(Iso.to_world(Vector2(o + Vector2i(4, 0))))
	ctl.move_ghost(Iso.to_world(Vector2(o + Vector2i(4, 4))))
	check(ctl.wall_cells.size() == 9, "L-shaped plan has 9 cells (%d)" % ctl.wall_cells.size())
	ctl.move_ghost(Iso.to_world(Vector2(o + Vector2i(7, 7))))
	check(ctl.wall_pts.back() == o + Vector2i(7, 8) or ctl.wall_pts.back() == o + Vector2i(7, 7) or ctl.wall_pts.back().x > o.x + 4, "diagonal leg accepted %s" % str(ctl.wall_pts.back()))
	var planned := {}
	for pc in ctl.wall_cells:
		planned[pc] = true
	check(map.wall_piece(o + Vector2i(4, 0), planned) == 2, "L corner is a post")
	check(map.wall_piece(o + Vector2i(2, 0), planned) == 1, "straight run piece")
	ctl.cancel_place()
	# see-through: a villager behind a building makes it transparent
	var hut := map.place_building("house", spot("house").floor() as Vector2i if false else Vector2i(map.size / 2 + 12, map.size / 2 - 12), true)
	var vv: Villager = v[2]
	vv.place(hut.tp + Vector2(-0.4, -0.4))
	vv.path.clear()
	map._update_see_through()
	check(hut._see, "building behind a villager goes see-through")
	vv.place(hut.tp + Vector2(2.5, 2.5))
	map._update_see_through()
	check(not hut._see, "and solid again when the villager is in front")
	# resources never run out
	var gold0: int = map.res_sets["gold"].size()
	var g: ResNode = map.res_sets["gold"].values()[0]
	map.remove_res(g)
	check(map.res_sets["gold"].size() == gold0, "an exhausted gold mine respawns (%d)" % map.res_sets["gold"].size())
	var wood0: int = map.res_sets["wood"].size()
	for i in 10:
		map.remove_res(map.res_sets["wood"].values()[0])
	check(map.res_sets["wood"].size() == wood0, "10 trees cut grow 10 new ones (%d -> %d)" % [wood0, map.res_sets["wood"].size()])
	# towers get better through the University (Guard Tower, then Keep): more arrows per volley
	var tower: Building = map.buildings.filter(func(b: Building) -> bool: return b.kind == "tower")[0]
	check(tower.tower_shots() == 1 and tower.title() == "Watch Tower", "a Watch Tower looses one arrow")
	for r: String in Defs.RES_NAMES:
		map.stock[r] = 5000
	var uni := map.place_building("university", Vector2i(int(spot("university").x), int(spot("university").y)), true)
	check(map.try_research(uni, 140) == "", "Guard Tower can be researched at the University")
	run(30.0 / 1.5 + 2.0)
	check(tower.tower_shots() == 2 and tower.title() == "Guard Tower" and tower.max_hp > 1400.0, "the tower became a Guard Tower: %d arrows, %d hp" % [tower.tower_shots(), int(tower.max_hp)])
	var boar := map.make_animal("boar", tower.tp + Vector2(3, 0))
	var hp0 := boar.hp
	run(1.5)
	check(boar.hp <= hp0 - 2.0 * 5.0, "both arrows hit one target (%d -> %d)" % [hp0, boar.hp])
	boar.take_damage(1000.0)
	var b1 := map.make_animal("boar", tower.tp + Vector2(3, 0))
	var b2 := map.make_animal("boar", tower.tp + Vector2(-3, 1))
	var h1 := b1.hp
	var h2 := b2.hp
	run(2.0)
	check(b1.hp < h1 and b2.hp < h2, "two targets are both hit")
	b1.take_damage(1000.0)
	b2.take_damage(1000.0)
	check(map.try_research(uni, 63) == "", "Keep can be researched too")
	run(75.0 / 1.5 + 2.0)
	check(tower.tower_shots() == 3 and tower.title() == "Keep", "Keep: three arrows")
	uni.take_damage(1000000.0)
	# damage fire and rubble
	tower.take_damage(tower.max_hp * 0.5)
	check(tower._fire != null, "damaged tower burns (%s)" % tower._fire_name)
	var ground0 := map.ground.get_child_count()
	tower.take_damage(1000000.0)
	check(map.ground.get_child_count() == ground0 + 1, "destroyed tower leaves rubble")


func test_builders_and_repair() -> void:
	map.stock.wood = 1000
	var v := villagers()
	var a := map.place_building("house", Vector2i(spot("house") - Vector2.ONE * 0.5), false)
	var b := map.place_building("house", Vector2i(spot("house") - Vector2.ONE * 0.5), false)
	check(a != b and a.origin != b.origin, "two house plots placed")
	var w: Villager = v[3]
	w.place(Vector2(a.origin) + Vector2(-1.0, 0.0))
	w.order_build(a)
	run(60.0)
	check(a.done and b.work > 0.0, "builder carries on to the next plot nearby (work %.1f)" % b.work)
	run(60.0)
	check(b.done, "second plot finished too")
	# repairing pulls the attackers off the building
	a.hp = a.max_hp * 0.5
	var raider := map.make_unit("74", 1, a.tp + Vector2(2.0, 2.0))
	raider.target = a
	raider.hp = 5000.0
	raider.max_hp = 5000.0
	w.order_repair(a)
	run(10.0)    # the villager gets there and starts repairing
	check(w.job == "repair" and w.state == Villager.S.WORK, "villager is repairing")
	raider.target = a
	w._draw_aggro()
	var drew: bool = raider.target == w
	check(drew, "repairer drew the attacker's aggro")
	raider.take_damage(100000.0)
	# repair from the button resumes the old job afterwards
	var x: Villager = v[4]
	var tree := map.find_resource("wood", x.cell(), 20)
	x.order_gather(tree)
	run(1.0)
	a.hp = a.max_hp * 0.4
	x.order_repair(a, true)
	check(x.job == "repair", "button repair sends the villager")
	run(40.0)
	check(a.hp >= a.max_hp and x.job == "gather", "after repair the villager returns to gathering (job %s)" % x.job)


func test_economy() -> void:
	for r: String in Defs.RES_NAMES:
		map.stock[r] = 3000
	var tc: Building = map.buildings.filter(func(b: Building) -> bool: return b.kind == "tc")[0]
	check(map.tech.age() == 0 and tc.level == 1 and tc.title() == "Town Center", "start in the Dark Age with the plain Town Center")
	check(Defs.BUILDINGS.house.cost == {"wood": 30} and Defs.BUILDINGS.house.pop == 5, "house costs 30 wood and houses 5, from the data")
	check(absf(Defs.UNITS.villager.time - 25.0 / 1.5) < 0.01 and Defs.UNITS.villager.cost == {"food": 50}, "villager 50 food, 25 game seconds")
	check(absf(map.gather_rate("wood") - 0.39 * 1.5) < 0.01 and absf(map.gather_rate("farm") - 0.53 * 1.5) < 0.01, "real gather rates (wood %.2f/s, farm %.2f/s)" % [map.gather_rate("wood"), map.gather_rate("farm")])
	check(Defs.lock_reason(map.tech, "tower") == "Needs Feudal Age", "towers need the Feudal Age (%s)" % Defs.lock_reason(map.tech, "tower"))
	ctl.start_place("tower")
	check(ctl.placing == "", "a locked building cannot be placed")
	check(Defs.lock_reason(map.tech, "farm") == "Needs a Mill", "farms need a mill")
	check(map.try_research(tc, 101) != "", "Feudal Age needs two buildings: %s" % map.try_research(tc, 101))
	var mill_o := Vector2i(int(spot("mill").x), int(spot("mill").y))
	var extra: Array[Building] = [map.place_building("mill", mill_o, true)]
	check(Defs.lock_reason(map.tech, "farm") == "", "a mill unlocks farms")
	var home_o := Vector2i(int(spot("house").x), int(spot("house").y))
	extra.append(map.place_building("house", home_o, true))
	check(map.try_research(tc, 101) != "", "a house does not count as an age building: the mill is only one")
	var bar_o := Vector2i(int(spot("barracks").x), int(spot("barracks").y))
	extra.append(map.place_building("barracks", bar_o, true))
	var food0: int = map.stock.food
	check(map.try_research(tc, 101) == "", "Feudal Age can start with a mill and a barracks")
	check(map.stock.food == food0 - 500 and tc.res_tech == 101, "it costs 500 food and the Town Center is busy")
	check(map.try_research(tc, 22) != "", "one technology at a time")
	run(130.0 / 1.5 + 2.0)
	check(map.tech.age() == 1 and tc.level == 2 and tc.title() == "Feudal Town Center", "Feudal Age reached, the Town Center looks Feudal")
	check(Defs.lock_reason(map.tech, "tower") == "" and Defs.lock_reason(map.tech, "wall") == "", "towers and walls are open")
	# Loom and Wheelbarrow
	var vv: Villager = villagers()[0]
	var hp0 := vv.max_hp
	check(map.try_research(tc, 22) == "", "Loom starts")
	run(25.0 / 1.5 + 2.0)
	check(absf(vv.max_hp - (hp0 + 15.0)) < 0.01, "Loom: villagers +15 hit points (%d)" % int(vv.max_hp))
	var spd0 := vv.speed_mult()
	var cap0 := map.carry_cap("wood")
	check(map.try_research(tc, 213) == "", "Wheelbarrow starts")
	run(75.0 / 1.5 + 2.0)
	check(vv.speed_mult() > spd0 * 1.09 and map.carry_cap("wood") > cap0, "Wheelbarrow: faster (%.2f) and carries more (%d)" % [vv.speed_mult(), map.carry_cap("wood")])
	# lumber camp tool
	var camp_o := Vector2i(int(spot("lumber_camp").x), int(spot("lumber_camp").y))
	var camp := map.place_building("lumber_camp", camp_o, true)
	extra.append(camp)
	var r0 := map.gather_rate("wood")
	check(map.try_research(camp, 202) == "", "Double-Bit Axe starts at the lumber camp")
	run(25.0 / 1.5 + 2.0)
	check(absf(map.gather_rate("wood") / r0 - 1.2) < 0.01, "Double-Bit Axe: wood gathered 20%% faster (%.2f)" % map.gather_rate("wood"))
	# Castle and Imperial need two buildings of the age before
	check(map.try_research(tc, 102) != "", "Castle Age needs two Feudal buildings")
	map.tech.building_done(87)
	map.tech.building_done(84)
	check(map.try_research(tc, 102) == "", "Castle Age starts")
	run(160.0 / 1.5 + 2.0)
	check(map.tech.age() == 2 and tc.level == 3, "Castle Age reached")
	map.tech.building_done(49)
	map.tech.building_done(104)
	check(map.try_research(tc, 103) == "", "Imperial Age starts")
	run(190.0 / 1.5 + 2.0)
	check(map.tech.age() == 3 and tc.level == 4 and absf(tc.max_hp - float(map.tech.stats(142).hp)) < 1.0, "Imperial Age: Imperial Town Center with %d hp" % int(tc.max_hp))
	check(not map.tech_cards(tc).has(103), "no further age to research")
	map.tech.restore(map.tech.researched.keys())
	for b in extra:
		map.deconstruct(b)
	for r: String in Defs.RES_NAMES:
		map.stock[r] = 3000


func test_sound() -> void:
	Sfx.set_volume("Combat", 0.0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Combat")), "volume 0 mutes the fighting bus")
	Sfx.set_volume("Combat", 0.8)
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Combat")), "and back on")
	Sfx.play("sword")
	check(Sfx._pool.any(func(p: AudioStreamPlayer) -> bool: return p.stream != null), "an effect was handed to a player")
	check(Sfx._tracks.size() == 2, "two music tracks loaded")


func test_difficulty() -> void:
	var dir := map.director
	var want := {"easy": 3, "medium": 4, "hard": 6}
	for d: String in ["easy", "medium", "hard"]:
		map.difficulty = d
		dir.wave = 0
		var before := map.mobs.filter(func(m: Mob) -> bool: return m.team == 1).size()
		dir.raid()
		var raiders := map.mobs.filter(func(m: Mob) -> bool: return m.team == 1)
		check(raiders.size() - before == want[d], "%s: first raid has %d soldiers (%d)" % [d, want[d], raiders.size() - before])
		for m in raiders:
			m.take_damage(100000.0)
		run(10.0)
	# easy never upgrades: even at wave 40 only the basic soldiers come, and softer
	map.difficulty = "easy"
	dir.wave = 40
	var kinds := {}
	for i in 200:
		kinds[dir._pick_kind()] = true
	check(kinds.keys().all(func(k: String) -> bool: return k in ["74", "4"]), "easy raids never upgrade (%s)" % str(kinds.keys()))
	dir.raid()
	var e: Mob = map.mobs.filter(func(m: Mob) -> bool: return m.team == 1)[0]
	check(e.dmg_mult < 1.0 and e.max_hp < float(Combat.base_stats(int(e.kind)).hp), "easy raiders are softer (hp %d)" % int(e.max_hp))
	for m in map.mobs.filter(func(m: Mob) -> bool: return m.team == 1):
		m.take_damage(100000.0)
	map.difficulty = "hard"
	dir.wave = 5
	kinds.clear()
	for i in 300:
		kinds[dir._pick_kind()] = true
	check(kinds.has("24") and kinds.has("75") and kinds.has("35"), "hard raids bring crossbowmen, men-at-arms and rams by wave 5")
	dir.wave = 0
	dir.next_raid = 9999.0
	map.difficulty = "hard"


func test_military() -> void:
	for r: String in Defs.RES_NAMES:
		map.stock[r] = 9000
	# the original damage rule
	var mil := Combat.base_stats(74)
	var vil := Combat.base_stats(83)
	check(Combat.damage(mil.atk, vil.arm) == 4.0, "a Militia hits a villager for 4")
	check(Combat.damage({4: 1.0}, {4: 5.0}) == 1.0, "a blow always does at least 1")
	var kn := Combat.base_stats(38)
	check(Combat.damage(Combat.base_stats(93).atk, kn.arm) > 4.0 * Combat.damage(mil.atk, kn.arm), "a Spearman hurts a Knight far more than a Militia does (%d vs %d)" % [Combat.damage(Combat.base_stats(93).atk, kn.arm), Combat.damage(mil.atk, kn.arm)])
	# the buildings train what the tech tree allows
	var bar: Building = map.buildings.filter(func(b: Building) -> bool: return b.kind == "barracks" and b.done)[0]
	check(bar.train_list().has("74") and bar.train_list().has("93") and not bar.train_list().has("4"), "the Barracks trains Militia and Spearmen: %s" % str(bar.train_list()))
	var ar := map.place_building("archery_range", Vector2i(int(spot("archery_range").x), int(spot("archery_range").y)), true)
	check(ar.train_list().has("4") and ar.train_list().has("7"), "the Archery Range trains Archers and Skirmishers: %s" % str(ar.train_list()))
	var st := map.place_building("stable", Vector2i(int(spot("stable").x), int(spot("stable").y)), true)
	check(st.train_list().has("448") and st.train_list().has("38"), "the Stable trains Scouts and Knights: %s" % str(st.train_list()))
	map.recalc_pop()
	var k := map.spawn_unit("38", st)
	check(absf(k.max_hp - float(map.tech.stats(38).hp)) < 0.01 and absf(k.speed - 1.35 * Rules.GAME_SPEED) < 0.01, "a Knight has the data's hit points and speed (%d hp)" % int(k.max_hp))
	check(Assets.man.anims.has(k.anim("walk")) and k.anim("walk") == "u38_walk_blue", "and its own sprites (%s)" % k.anim("walk"))
	# upgrades turn existing units into the better ones
	var old: Soldier = map.mobs.filter(func(m: Mob) -> bool: return m is Soldier and m.team == 0 and m.kind == "74")[0]
	check(map.try_research(bar, 222) == "", "Man-at-Arms starts at the Barracks")
	run(40.0 / 1.5 + 2.0)
	check(old.uid == 75 and old.stats().name == "Man-at-Arms" and old.max_hp >= 45.0, "the existing Militia became a Man-at-Arms (%d hp)" % int(old.max_hp))
	check(bar.train_list().has("75") and not bar.train_list().has("74"), "and the Barracks now trains Men-at-Arms")
	# Blacksmith attack upgrade
	var bs := map.place_building("blacksmith", Vector2i(int(spot("blacksmith").x), int(spot("blacksmith").y)), true)
	var atk0: float = map.tech.stats(75).atk[4]
	check(map.try_research(bs, 67) == "", "Forging starts at the Blacksmith")
	run(50.0 / 1.5 + 2.0)
	check(map.tech.stats(75).atk[4] == atk0 + 1.0, "Forging: melee attack +1 (%d -> %d)" % [atk0, map.tech.stats(75).atk[4]])
	# a ram only goes for buildings and does real siege damage
	var ram := map.make_unit("35", 1, bar.tp + Vector2(8, 8)) as Soldier
	check(ram.siege and Combat.damage(ram.atk_dict(), bar.armor()) > 100.0, "a Ram is siege and flattens buildings (%d per blow)" % int(Combat.damage(ram.atk_dict(), bar.armor())))
	check(ram.anim("walk") == "u35_walk_red" or ram.anim("walk") == "u35_walk_blue", "the Ram has sprites (%s)" % ram.anim("walk"))
	ram.take_damage(100000.0)
	var red := map.make_unit("74", 1, bar.tp + Vector2(9, 9)) as Soldier
	check(red.anim("attack") == "u74_attack_red" and absf(red.max_hp - 40.0) < 0.01, "enemy Militia: red sprites and 40 hp")
	red.take_damage(100000.0)
	k.take_damage(100000.0)
	ar.take_damage(1000000.0)
	st.take_damage(1000000.0)
	bs.take_damage(1000000.0)


func test_roster() -> void:
	for r: String in Defs.RES_NAMES:
		map.stock[r] = 20000
	var cap0 := map.pop_cap
	for i in 6:
		map.place_building("house", Vector2i(int(spot("house").x), int(spot("house").y)), true)
	check(map.pop_cap > cap0 + 20, "more houses, more room")
	var sw := map.place_building("siege_workshop", Vector2i(int(spot("siege_workshop").x), int(spot("siege_workshop").y)), true)
	var tl := sw.train_list()
	check(tl.has("35") and tl.has("280") and not tl.has("279"), "the Siege Workshop trains Rams and Mangonels: %s" % str(tl))
	check(map.try_research(sw, 94) == "", "the Scorpion is researched there")
	run(60.0)
	check(sw.train_list().has("279"), "and then it can be trained")
	var mo := map.place_building("monastery", Vector2i(int(spot("monastery").x), int(spot("monastery").y)), true)
	check(mo.train_list() == ["125"], "the Monastery trains Monks: %s" % str(mo.train_list()))
	var ca := map.place_building("castle", Vector2i(int(spot("castle").x), int(spot("castle").y)), true)
	check(ca.train_list().has("8") and not ca.train_list().has("42") and not ca.train_list().has("128"), "the Castle trains the Britons' Longbowman, no Trebuchet or trade carts: %s" % str(ca.train_list()))
	var mk := map.place_building("market", Vector2i(int(spot("market").x), int(spot("market").y)), true)
	check(mk.train_list().is_empty() and map.tech_cards(mk).has(23), "the Market trains nothing and researches Coinage")
	# the Castle shoots like a tower
	var boar := map.make_animal("boar", ca.tp + Vector2(5, 0))
	var hp0 := boar.hp
	run(3.0)
	check(boar.hp < hp0 and ca.tower_shots() == 3, "the Castle looses arrows at what comes close (%d -> %d)" % [hp0, boar.hp])
	boar.take_damage(1000.0)
	# a monk heals the wounded
	var wounded: Soldier = map.mobs.filter(func(m: Mob) -> bool: return m is Soldier and m.team == 0 and not (m as Soldier).healer)[0]
	var monk := map.spawn_unit("125", mo) as Soldier
	monk.order = "idle"
	monk.path.clear()
	for m in map.mobs:
		if m.team == 0 and m != wounded:
			m.hp = m.max_hp                       # only one wounded unit, so the monk has no other choice
	wounded.place(monk.tp + Vector2(3, 1))
	wounded.target = null
	wounded.order = "idle"
	wounded.path.clear()
	wounded.hp = wounded.max_hp * 0.3
	var w0 := wounded.hp
	run(12.0)
	check(monk.healer and wounded.hp > w0 + 8.0, "a monk heals a wounded soldier (%d -> %d of %d)" % [w0, wounded.hp, wounded.max_hp])
	# a mangonel's blast hurts everything near the target
	var far := Vector2(map.free_cell_near(Vector2i(10, 10), 10))      # away from the Town Center's and Castle's arrows
	var b1 := map.make_animal("boar", far + Vector2(4, 4))        # within the Mangonel's range of 7, so it has no walking to do
	var b2 := map.make_animal("boar", far + Vector2(4.5, 4.4))
	b1.wait = 999.0           # standing still, so the shell lands where they are
	b2.wait = 999.0
	var mg := map.make_unit("280", 0, far) as Soldier
	var h1 := b1.hp
	var h2 := b2.hp
	mg.order_attack(b1)
	run(14.0)
	check(b1.hp < h1 and b2.hp < h2, "a Mangonel's blast hits both boars (%d, %d)" % [h1 - b1.hp, h2 - b2.hp])
	b1.take_damage(1000.0)
	b2.take_damage(1000.0)
	mg.take_damage(1000.0)
	# the Market's prices
	var gold0: int = map.stock.gold
	var fee0 := map.barter_fee()
	check(absf(fee0 - 0.30) < 0.001 and map.barter("food", true) == "" and map.stock.gold == gold0 + 70, "selling 100 food fetches 70 gold at a 30%% fee (+%d)" % (map.stock.gold - gold0))
	check(map.prices.food < 100.0 and map.prices.gold > 100.0, "the price of food fell, gold rose")
	check(map.try_research(mk, 15) == "", "Guilds start")
	run(80.0)
	check(absf(map.barter_fee() - 0.15) < 0.001, "Guilds halve the fee")
	check(map.barter("wood", false) == "" and map.stock.wood >= 20100 - 1, "buying 100 wood works")
	# many cards: they come in pages that fit between the selection card and the quick buttons
	var bsm := map.place_building("blacksmith", Vector2i(int(spot("blacksmith").x), int(spot("blacksmith").y)), true)
	ctl.select_building(bsm)
	var hud: Hud = main.hud
	hud.refresh_commands()
	check(hud._cmd_items.size() > 4 and hud.pager.visible, "a Blacksmith with %d cards gets pages (%s)" % [hud._cmd_items.size(), hud.page_label.text])
	hud._flip(1)
	check(hud.page_label.text.begins_with("2/") and hud.cmd_box.get_child_count() > 0, "the arrow turns the page (%s)" % hud.page_label.text)
	ctl.clear_selection()
	bsm.take_damage(10000000.0)
	for m in map.mobs.filter(func(x: Mob) -> bool: return x is Soldier and x.team == 0 and (x as Soldier).healer):
		m.take_damage(1000.0)
	for b in [sw, mo, ca, mk]:
		b.take_damage(10000000.0)


func test_hunting() -> void:
	map.attacks_paused = true
	check(Defs.ANIMALS.deer.food == 140 and Defs.ANIMALS.boar.food == 340 and Defs.ANIMALS.wolf.hp == 25 and not Defs.ANIMALS.wolf.has("food"), "animals follow the data: deer 140 food, boar 340, wolf 25 hp and no meat")
	var tc: Building = map.buildings.filter(func(b: Building) -> bool: return b.kind == "tc")[0]
	var spot_cell := map.free_cell_near(Vector2i(tc.tp) + Vector2i(7, 7), 8)
	var deer := map.make_animal("deer", Vector2(spot_cell))
	deer.wait = 999.0
	check(not deer.is_threat() and map.nearest_hostile(deer.tp, 2.0) == null, "a deer is no threat: towers and soldiers leave it alone")
	var v: Villager = villagers()[0]
	v._clear_job()
	v.place(deer.tp + Vector2(2, 2))
	v.order_hunt(deer)
	run(25.0)
	var meat := map.carcass_near(deer.tp, 4.0)
	check(not deer.alive and meat != null and meat.amount > 0 and meat.amount <= 140, "a villager hunts the deer and it leaves meat (%d food left of 140)" % (meat.amount if meat else -1))
	var food0: int = map.stock.food
	run(240.0)
	check(map.stock.food > food0 + 30, "and brings the meat home (%d -> %d)" % [food0, map.stock.food])
	# a boar killed by a soldier also leaves meat (no hunter about to eat it first)
	v._clear_job()
	v.state = Villager.S.IDLE
	v.place(Vector2(tc.tp) + Vector2(-3, -3))
	for old in map.carcasses.duplicate():
		map.remove_res(old)
	var boar := map.make_animal("boar", Vector2(map.free_cell_near(Vector2i(tc.tp) + Vector2i(-9, 7), 8)))
	boar.wait = 999.0
	boar.hp = 12.0                    # a healthy boar beats a lone Militia (as in the original); this one is already hurt
	var sol: Soldier = map.make_unit("74", 0, boar.tp + Vector2(3, 0)) as Soldier
	sol.order_attack(boar)
	run(60.0)
	check(not boar.alive, "the soldier kills the boar")
	check(map.carcass_near(boar.tp, 4.0) != null and map.carcass_near(boar.tp, 4.0).amount > 0, "and it leaves meat")
	sol.take_damage(10000.0)


func test_smart_and_decon() -> void:
	for r: String in Defs.RES_NAMES:
		map.stock[r] = 2000
	var vs := villagers()
	var a: Villager = vs[0]
	var b: Villager = vs[1]
	a.order_move(a.cell())
	b.order_move(b.cell())
	run(2.0)
	for v in [a, b]:
		v._clear_job()
		v.state = Villager.S.IDLE
	var s := spot("lumber_camp")
	var o := Vector2i(int(s.x - 0.5), int(s.y - 0.5))
	var camp := map.place_building("lumber_camp", o, false)
	a.place(Vector2(o) + Vector2(-2.0, 0.0))
	b.place(Vector2(o) + Vector2(-2.0, 1.0))
	run(1.5)
	check(a.job == "build" and b.job == "build", "idle villagers nearby help build the new camp (%s, %s)" % [a.job, b.job])
	run(40.0)
	check(camp.done and (a.job == "gather" or b.job == "gather"), "and then go gathering wood around it (%s, %s)" % [a.job, b.job])
	# deconstruct
	var wood0: int = map.stock.wood
	var tower := map.place_building("tower", Vector2i(int(spot("tower").x), int(spot("tower").y)), true)
	var cost_before: int = map.stock.wood
	var txt := map.deconstruct(tower)
	check(map.stock.wood - cost_before == 25 and map.stock.stone >= 2000 + 125 - 125, "deconstruct gives the cost back (%s)" % txt)
	check(not tower.alive and not map.buildings.has(tower), "building is gone")
	var home := map.place_building("barracks", Vector2i(int(spot("barracks").x), int(spot("barracks").y)), true)
	var back := home.refund_cost()
	check(back.wood == 175, "refund is the build price (%s)" % str(back))
	home.res_tech = 22
	check(map.tech.cost_of(22) == {3: 50} and home.refund_cost().gold == 50, "plus a technology being researched")
	home.res_tech = -1
	map.deconstruct(home)
	var tcb: Building = map.buildings.filter(func(x: Building) -> bool: return x.kind == "tc")[0]
	check(tcb.alive, "the town center is never deconstructed here")


func test_chatter() -> void:
	var v := villagers()
	ctl.select_units([v[0], v[1], v[2]])
	for u in v:
		if u.has_node("Chatter"):
			u.get_node("Chatter").free()
	Chatter.enabled = true
	ctl._move_to(Vector2i(map.size / 2 + 6, map.size / 2 + 6))
	var talkers := v.filter(func(u: Villager) -> bool: return u.has_node("Chatter"))
	check(talkers.size() >= 1 and talkers.size() <= 2, "ordered villagers say something (%d speakers)" % talkers.size())
	for u in v:
		if u.has_node("Chatter"):
			u.get_node("Chatter").free()
	Chatter.enabled = false
	ctl._move_to(Vector2i(map.size / 2 + 7, map.size / 2 + 6))
	check(not v.any(func(u: Villager) -> bool: return u.has_node("Chatter")), "chatter off: silence")
	Chatter.enabled = true
	# building orders and being hurt also trigger comments
	for u in v:
		if u.has_node("Chatter"):
			u.get_node("Chatter").free()
	ctl.select_units([v[0], v[1]])
	ctl.start_place("house")
	ctl.move_ghost(Iso.to_world(spot("house")))
	ctl.confirm_place()
	check(v.any(func(u: Villager) -> bool: return u.has_node("Chatter")), "villagers comment when sent to build")
	for u in v:
		if u.has_node("Chatter"):
			u.get_node("Chatter").free()
	var heard := false
	for i in 40:
		v[3]._hurt_say = -10.0
		v[3].take_damage(0.01)
		if v[3].has_node("Chatter"):
			heard = true
			break
	check(heard, "a villager under attack shouts something")
	var tsp := spot("tower")
	var tw := map.place_building("tower", Vector2i(int(tsp.x), int(tsp.y)), true)
	if tw.has_node("Chatter"):
		tw.get_node("Chatter").free()
	var said := false
	for round in 8:
		var prey := map.make_animal("boar", tw.tp + Vector2(3, 0))
		prey.hp = 1.0
		for i in 20:
			run(0.2)
			if tw.has_node("Chatter"):
				said = true
				break
		prey.take_damage(1000.0)
		if said:
			break
	check(said, "the tower speaks when it shoots or kills")
	map.deconstruct(tw)


func test_tombstone() -> void:
	var v := map.make_unit("villager", 0, Vector2(map.size / 2 + 9, map.size / 2 - 9))
	var spot := v.position
	v.take_damage(1000.0)
	var n0 := map.tombs.size()
	run(12.0)
	check(map.tombs.size() == n0 + 1 and map.tombs.back().position.distance_to(spot) < 5.0, "a tombstone appears where the corpse was (%d)" % map.tombs.size())
	var tomb: Tombstone = map.tombs.back()
	run(4.0)
	check(is_instance_valid(tomb) and tomb.modulate.a > 0.99, "it stays for its 10 seconds (alpha %.2f)" % tomb.modulate.a)
	run(6.0)
	check(not map.tombs.has(tomb), "then it fades away and is removed")
	var wolf := map.make_animal("wolf", Vector2(map.size / 2 + 12, map.size / 2 - 9))
	var n1 := map.tombs.size()
	wolf.take_damage(1000.0)
	run(14.0)
	check(map.tombs.size() == n1, "animals get no tombstone")


func test_save_load() -> void:
	var vill := villagers()[0]
	var tree := map.find_resource("wood", vill.cell(), 30)
	vill.order_gather(tree)
	run(2.0)
	map.stock.wood = 1234
	map.game_time = 779.0
	check(SaveGame.write("user://test_save.json", main), "game written")
	var snap := SaveGame.read("user://test_save.json")
	check(not snap.is_empty() and snap.stock.wood == 1234, "save file reads back")
	var count := func(m: GameMap, kind: String) -> int:
		return m.buildings.filter(func(b: Building) -> bool: return b.kind == kind).size()
	var bl: Dictionary = {}
	for k in ["tc", "house", "barracks", "tower", "wall", "farm"]:
		bl[k] = count.call(map, k)
	var n_mobs := map.mobs.size()
	var n_res := map.res_by_cell.values().filter(func(n: ResNode) -> bool: return not n is Carcass).size()      # carcasses are not saved
	var lvl_tc: int = (map.buildings.filter(func(b: Building) -> bool: return b.kind == "tc")[0] as Building).level
	Main.pending = snap
	var second: Node = load("res://scenes/main.tscn").instantiate()
	add_child(second)
	var m2: GameMap = second.map
	check(m2.stock.wood == 1234 and absf(m2.game_time - 779.0) < 0.5, "loaded stock and time (%d, %.1f)" % [m2.stock.wood, m2.game_time])
	var same := true
	for k in bl:
		if count.call(m2, k) != bl[k]:
			same = false
			print("      differs: ", k, " ", count.call(m2, k), " vs ", bl[k])
	check(same, "same buildings after loading")
	check(m2.mobs.size() == n_mobs, "same units after loading (%d vs %d)" % [m2.mobs.size(), n_mobs])
	check(absi(m2.res_by_cell.size() - n_res) <= 1, "same resources (%d vs %d)" % [m2.res_by_cell.size(), n_res])
	check((m2.buildings.filter(func(b: Building) -> bool: return b.kind == "tc")[0] as Building).level == lvl_tc, "town center level kept")
	check(m2.tech.researched.has(222) and m2.mobs.any(func(m: Mob) -> bool: return m is Soldier and m.team == 0 and (m as Soldier).uid == 75), "research kept: the Militia is still a Man-at-Arms")
	var gatherers := m2.mobs.filter(func(m: Mob) -> bool: return m is Villager and m.job == "gather")
	check(gatherers.size() >= 1, "villager went back to gathering")
	check(m2.pop_cap == map.pop_cap, "population cap equal (%d)" % m2.pop_cap)
	second.queue_free()
	await get_tree().process_frame


func test_defense() -> void:
	map.attacks_paused = false
	map.director.next_raid = 9999.0
	map.director.raid()
	var raiders := 0
	for m in map.mobs:
		if m.team == 1:
			raiders += 1
	check(raiders >= 6, "raid spawned %d enemy soldiers" % raiders)
	var bld0 := map.buildings.size()
	for i in 7:
		run(100.0)
		if map.mobs.filter(func(m: Mob) -> bool: return m.team == 1).is_empty():
			break
	var left := 0
	for m in map.mobs:
		if m.team == 1:
			left += 1
	print("      raiders left %d, buildings %d -> %d, player units %d" % [left, bld0, map.buildings.size(), map.mobs.filter(func(m: Mob) -> bool: return m.team == 0).size()])
	check(left < raiders, "raiders were fought off (%d -> %d)" % [raiders, left])
	var tc_alive := map.buildings.any(func(b: Building) -> bool: return b.kind == "tc")
	check(tc_alive, "town center survived the first raid")


func test_pause() -> void:
	map.attacks_paused = true
	var before := map.director.next_raid
	run(30.0)
	check(is_equal_approx(map.director.next_raid, before), "raid timer frozen while attacks are paused")
	map.attacks_paused = false
	var wolves := 0
	for m in map.mobs:
		if m is Animal:
			wolves += 1
	check(wolves > 0, "wild animals exist (%d)" % wolves)
