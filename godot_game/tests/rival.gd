extends Node
## Headless test of the rival base:  godot --headless --path godot_game res://tests/rival.tscn

var main: Node
var map: GameMap
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func run(seconds: float, dt := 0.1) -> void:
	for i in int(seconds / dt):
		map._process(dt)


func _ready() -> void:
	Main.map_size = 128
	Main.opponent = "rival"
	Main.fixed_seed = 7
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	map = main.map
	seed(3)
	test_base()
	test_growth()
	test_farms()
	test_convert()
	test_defences()
	test_attack()
	test_conquest()
	test_techs()
	await test_save()
	print("RESULT: %s" % ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	get_tree().quit(fails)


func test_base() -> void:
	check(map.opponent == "rival" and map.rival != null and map.rival.started, "the rival base was started")
	var tc: FoeBuilding = map.rival.tc()
	check(tc != null and tc.done and tc.team == 1, "it has a finished Town Center")
	if tc == null:
		return
	var player_tc := Vector2(map.size / 2.0, map.size / 2.0)
	check(tc.tp.distance_to(player_tc) > map.size * 0.35, "far from the player (%d tiles)" % int(tc.tp.distance_to(player_tc)))
	check(not map.adjacent_path(player_tc + Vector2(3, 3), tc.rect()).is_empty(), "and reachable by land")
	check(map.foes.size() == 1, "nothing else built yet")
	check(map.rival.villagers.size() == 6 and map.rival.workers == 6, "it starts with six visible villagers (%d)" % map.rival.villagers.size())
	check(map.rival.soldiers().size() == 2 and map.rival.soldiers().all(func(m: Soldier) -> bool: return m.foe_mode == "guard"), "and two soldiers on guard")
	check(tc.material != null and tc.texture != null, "it has a red picture")
	map.attacks_paused = true
	run(60.0)
	check(map.foes.size() == 1, "a paused game freezes the rival")
	map.attacks_paused = false


func test_growth() -> void:
	map.difficulty = "medium"
	var r := map.rival
	var builder_seen := false
	var worked := {}                   # what the villagers were seen gathering
	var trees := {}                    # distinct trees felled from
	var work_last := {}                # building -> its progress at the last look
	var cheats := 0                    # progress made with no villager working on it
	var over := 0                      # most the population went over the houses
	for i in 600:
		run(0.5)
		for b: FoeBuilding in map.foes:
			if b.alive and not b.done:
				if work_last.has(b) and b.work > work_last[b] + 0.001:
					if not map.rival.villagers.any(func(v: FoeVillager) -> bool: return v.site == b and v.state == FoeVillager.S.WORK):
						cheats += 1
				work_last[b] = b.work
		if i > 180:                    # (it starts with more people than its Town Center houses)
			over = maxi(over, r.pop() - r.pop_cap())
		for v: FoeVillager in map.rival.villagers:
			if v.state == FoeVillager.S.WORK and v.job == "build":
				builder_seen = true
			if v.state == FoeVillager.S.WORK and v.job == "gather":
				worked[v.gather_kind] = true
				if v.gather_kind == "wood":
					trees[v.res.cell] = true
	check(builder_seen, "villagers were seen building")
	check(cheats == 0, "nothing was built without a villager working on it (%d)" % cheats)
	check(over <= 2, "its population never ran far over its houses (%d over)" % over)
	print("      gathered: ", worked.keys(), " trees ", trees.size(), " stock ", r.stock)
	check(worked.has("wood") and worked.has("food") and worked.has("gold"), "and gathering wood, food and gold")
	check(trees.size() >= 3, "from several different trees (%d)" % trees.size())
	var felled := trees.keys().filter(func(c: Vector2i) -> bool: return not map.res_sets.wood.has(c))
	check(not felled.is_empty(), "and trees do run out (%d of those %d are gone)" % [felled.size(), trees.size()])
	print("      delivered: ", r.gathered)
	check(r.gathered.wood > 300 and r.gathered.food > 100 and r.gathered.gold > 50 and r.gathered.stone > 50, "all of its stock came from what villagers carried in")
	var kinds := {}
	for b: FoeBuilding in map.foes:
		kinds[b.kind] = int(kinds.get(b.kind, 0)) + 1
	print("      after 5 min: ", kinds, " workers ", r.workers, " stock ", r.stock)
	check(kinds.size() >= 3, "it builds (%d kinds of building)" % kinds.size())
	check(kinds.has("lumber_camp") and kinds.has("mining_camp"), "a lumber camp and a mining camp beside the resources")
	check(kinds.has("mill") or kinds.has("farm"), "and a mill or farms for food")
	var near_camp := map.foes.filter(func(b: FoeBuilding) -> bool: return b.kind == "lumber_camp" and not r.tc().tp.distance_to(b.tp) < 5.0)
	check(not near_camp.is_empty(), "the lumber camp stands away from the Town Center (%.0f tiles)" % r.tc().tp.distance_to(near_camp[0].tp))
	check(kinds.has("house"), "it builds houses for its population")
	var built := map.foes.filter(func(b: FoeBuilding) -> bool: return b.done)
	check(built.size() >= 3, "and finishes them (%d done)" % built.size())
	check(r.workers > 6, "its workforce grows (%d)" % r.workers)
	var w0 := r.workers
	r.villagers[0].take_damage(9999.0)
	check(r.workers == w0 - 1, "killing a villager costs the rival a worker (%d -> %d)" % [w0, r.workers])
	check(r.soldiers().size() >= 1, "it trains soldiers (%d)" % r.soldiers().size())
	check(r.soldiers().all(func(m: Soldier) -> bool: return m.foe_mode == "guard"), "which guard the base")
	run(600.0)
	print("      after 14 min: age ", r.age, " soldiers ", r.soldiers().size(), " wave ", r.wave, " stock ", r.stock)
	check(r.count("barracks") >= 1, "it built a Barracks (%d)" % r.count("barracks"))
	var done_techs := r.tech.researched.keys().filter(func(id: int) -> bool: return Rules.techs.has(id) and Rules.techs[id].loc >= 0 and not Rules.AGE_TECHS.has(id))
	print("      civ ", Defs.civ_name(r.civ), " researched: ", done_techs.map(func(id: int) -> String: return String(Rules.techs[id].name)))
	check(r.tech.is_researched(22), "it researched Loom at the Town Center")
	check(done_techs.size() >= 3, "and several more technologies (%d)" % done_techs.size())
	check(r.villagers.all(func(v: FoeVillager) -> bool: return v.max_hp > 30.0), "Loom gave its villagers more hit points (%d)" % int(r.villagers[0].max_hp))
	if r.tech.is_researched(202):
		check(r.rate("wood") > float(Combat.base_stats(123).work_rate) * Rules.GAME_SPEED * float(r.d().gather) * 1.05, "Double-Bit Axe made its woodcutters faster")
	if r.count("blacksmith", true) > 0:
		check(r.tech.is_researched(67) or r.tech.is_researched(199) or r.tech.is_researched(74), "the Blacksmith researched something (%d techs)" % done_techs.size())
	check(r.age >= 1, "it has advanced to the Feudal Age or beyond (age %d)" % r.age)
	check(map.rival.tc().uid_now() != 109, "its Town Center took the new age's look")


func _amounts() -> int:
	var n := 0
	for kind: String in ["wood", "food", "gold", "stone"]:
		for res: ResNode in map.res_sets[kind].values():
			n += res.amount
	return n


## The berries are gone: it sows farms and works them.
## A wave of the rival's may have destroyed the player's Town Center (the game over window pauses the map): set the game right again.
func _keep_player_alive() -> void:
	if not map.buildings.any(func(b: Building) -> bool: return b.alive and b.kind == "tc"):
		map.place_building("tc", Vector2i(map.size / 2, map.size / 2) - Vector2i(2, 2), true)
	for b in map.buildings:
		if b.kind == "tc":
			b.hp = b.max_hp
	map.finished = false
	map.paused = false


func test_farms() -> void:
	var r := map.rival
	_keep_player_alive()
	for res: ResNode in map.res_sets.food.values():
		map.remove_res(res)
	r.stock.wood = 800.0
	var farmed := false
	var cycled := false
	var food0: int = r.gathered.food
	for i in 400:
		run(0.5)
		_keep_player_alive()
		for v: FoeVillager in r.villagers:
			if v.state == FoeVillager.S.WORK and v.job == "farm":
				farmed = true
		r.stock.wood = maxf(float(r.stock.wood), 300.0)
	var farms := map.foes.filter(func(b: FoeBuilding) -> bool: return b.kind == "farm")
	print("      farms ", farms.size(), " done ", farms.filter(func(b: FoeBuilding) -> bool: return b.done).size(), " food ", int(r.stock.food))
	check(farms.size() >= 1, "with the berries gone it sows farms (%d)" % farms.size())
	check(farmed, "and villagers work them")
	var idle_farms := farms.filter(func(b: FoeBuilding) -> bool: return b.done and not (is_instance_valid(b.farmer) and b.farmer.alive))
	check(idle_farms.size() <= 1, "every farm has a farmer (%d without)" % idle_farms.size())
	cycled = farms.any(func(b: FoeBuilding) -> bool: return b.done and b.food < float(Defs.BUILDINGS.farm.food))
	check(cycled, "the farms are being eaten down")
	check(r.gathered.food > food0 + 100, "food keeps coming in (%d delivered)" % (r.gathered.food - food0))


## A monk's conversion of the rival's units: a worker becomes a villager of ours, a soldier changes sides with the same share of health.
func test_convert() -> void:
	var r := map.rival
	var v: FoeVillager = r.villagers[0]
	v.hp = v.max_hp * 0.5
	var n0 := r.villagers.size()
	var mine0 := map.mobs.filter(func(m: Mob) -> bool: return m is Villager and m.team == 0).size()
	var rival_pop0 := r.pop()
	var our_pop0: int = map.pop
	var out := map.convert_mob(v, 0)
	check(r.pop() == rival_pop0 - 1 and map.pop == our_pop0 + 1, "a converted worker leaves the rival's housing and takes a place in ours (rival %d -> %d, ours %d -> %d)" % [rival_pop0, r.pop(), our_pop0, map.pop])
	check(out is Villager and out.team == 0 and absf(out.hp / out.max_hp - 0.5) < 0.01, "a converted worker is a villager of ours with half its health")
	check(r.villagers.size() == n0 - 1 and not map.mobs.has(v) and map.mobs.filter(func(m: Mob) -> bool: return m is Villager and m.team == 0).size() == mine0 + 1, "the rival lost a worker and we gained one")
	var s_list := r.soldiers()
	if not s_list.is_empty():
		var sol: Soldier = s_list[0]
		sol.hp = sol.max_hp * 0.25
		var rn := s_list.size()
		var rp1 := r.pop()
		var op1: int = map.pop
		map.convert_mob(sol, 0)
		check(r.pop() == rp1 - 1 and map.pop == op1 + 1, "and so does a converted soldier (rival %d -> %d, ours %d -> %d)" % [rp1, r.pop(), op1, map.pop])
		check(sol.team == 0 and sol._colour == "blue" and absf(sol.hp / sol.max_hp - 0.25) < 0.01 and r.soldiers().size() == rn - 1, "a converted soldier fights for us with its share of health, and the rival's army is smaller")


func test_defences() -> void:
	var r := map.rival
	# the rival's first waves may have cost the player the game (and the game over window paused the map): start fresh
	if not map.buildings.any(func(b: Building) -> bool: return b.alive and b.kind == "tc"):
		map.place_building("tc", Vector2i(map.size / 2, map.size / 2) - Vector2i(2, 2), true)
	map.finished = false
	map.paused = false
	for m: Soldier in r.soldiers():
		if m.foe_mode == "attack":
			m.target = null
			m.guard(r.rally)
	r.attacking = false
	var wave0 := r.wave
	r.wave = 100                       # no attack wave while we watch the guards
	map.difficulty = "medium"
	# a Castle Age rival with plenty of stone: walls, towers and guards
	r.age = 2
	for b: FoeBuilding in map.foes:
		b.set_age(2)
	r.researching = 99999.0            # it stays in the Castle Age
	r.stock.stone = 6000.0
	r.stock.wood = 6000.0
	r.stock.gold = 3000.0
	r.stock.food = 3000.0
	run(420.0)
	var walls := map.foes.filter(func(b: FoeBuilding) -> bool: return b.kind == "wall")
	var wdone := walls.filter(func(b: FoeBuilding) -> bool: return b.done)
	print("      walls ", walls.size(), " done ", wdone.size(), " ring ", int(r.wall_complete() * 100), "% towers ", r.count("tower"), " target ", r.tower_target())
	check(wdone.size() >= 40, "it built a wall ring (%d pieces standing)" % wdone.size())
	var ring_ok := wdone.all(func(w: FoeBuilding) -> bool: return maxi(absi(w.origin.x - r.base.x), absi(w.origin.y - r.base.y)) == Rival.WALL_R)
	check(ring_ok, "all on the ring, %d tiles from the Town Center" % Rival.WALL_R)
	var gates := map.foes.filter(func(b: FoeBuilding) -> bool: return b.kind == "gate")
	var gates_done := gates.filter(func(b: FoeBuilding) -> bool: return b.done)
	print("      gates ", gates.size(), " done ", gates_done.size())
	check(gates_done.size() >= 2, "gates close the openings of the ring (%d standing)" % gates_done.size())
	check(gates.all(func(g: FoeBuilding) -> bool: return g.rect().size.x * g.rect().size.y == 3 and absi(g.origin.x - r.base.x) <= Rival.WALL_R and absi(g.origin.y - r.base.y) <= Rival.WALL_R), "3 cells long, in the ring")
	var inside_cell := map.free_cell_near(Vector2i(r.base.x + 6, r.base.y), 4)
	var outside_cell := map.free_cell_near(Vector2i(r.base.x, r.base.y - Rival.WALL_R - 3), 5)
	check(not map.find_path(Vector2(inside_cell), outside_cell, false, false, 1).is_empty(), "so that its own units can leave the base")
	var g0: FoeBuilding = gates_done[0]
	check(map.blocked(Vector2i(g0.tp), false, false, 0) and not map.blocked(Vector2i(g0.tp), false, false, 1), "a gate is shut for the player's walkers and open for its own")
	check(r.wall_complete() > 0.9, "the ring is almost closed (%d%%)" % int(r.wall_complete() * 100))
	var towers := map.foes.filter(func(b: FoeBuilding) -> bool: return b.kind == "tower")
	check(towers.size() >= 2, "towers were built (%d)" % towers.size())
	check(towers.all(func(b: FoeBuilding) -> bool: return b.uid_now() == 234), "Guard Towers in the Castle Age")
	var toward := (r.enemy - Vector2(r.base)).normalized()
	var facing := 0.0
	for b: FoeBuilding in towers:
		facing += (b.tp - Vector2(r.base)).normalized().dot(toward)
	check(not towers.is_empty() and facing / towers.size() > 0.4, "the towers stand on the side the player will come from (%.2f)" % (facing / maxf(1.0, towers.size())))
	var inside := towers.all(func(b: FoeBuilding) -> bool: return maxi(absi(b.origin.x - r.base.x), absi(b.origin.y - r.base.y)) < Rival.WALL_R)
	check(inside, "inside the wall")
	var done_towers := towers.filter(func(b: FoeBuilding) -> bool: return b.done)
	if not done_towers.is_empty():
		var tw: FoeBuilding = done_towers[0]
		var victim := map.make_unit("74", 0, Vector2(map.free_cell_near(Vector2i(tw.tp) + Vector2i(3, 0), 4)))
		var hp0 := victim.hp
		run(6.0)
		check(victim.hp < hp0 or not victim.alive, "a tower shoots a player's unit within reach (%d -> %d)" % [hp0, victim.hp])
		if victim.alive:
			victim.take_damage(9999.0)
	# defend groups: with a small army share the guards split over the posts
	var camp := map.foes.filter(func(b: FoeBuilding) -> bool: return b.kind == "mining_camp" and b.done)
	check(not camp.is_empty() and r.posts().size() >= 2, "there are defend posts: the town and the mining camp (%d)" % r.posts().size())
	r.pop_extra = 400
	var barracks: FoeBuilding = map.foes.filter(func(b: FoeBuilding) -> bool: return b.kind == "barracks" and b.done)[0]
	var fresh: Array[Soldier] = []
	for i in 10:
		r.spawn("74", barracks)
	for m in r.soldiers():
		if m.foe_mode == "guard":
			fresh.append(m)
	var at_town := fresh.filter(func(m: Soldier) -> bool: return m.guard_pos.distance_to(r.rally) < 2.0).size()
	var at_camp := fresh.size() - at_town
	print("      guards: town ", at_town, " camp ", at_camp, " posts ", r.posts().size())
	check(at_camp >= 2 and at_town >= 2, "guards are split between the town and the mines (%d / %d)" % [at_town, at_camp])
	# over 30 percent military: everyone gathers at the center
	r.pop_extra = 1 - r.workers
	check(r._post_for_new() == r.rally, "a big army gathers at the center")
	r.pop_extra = 0
	# patrol: a guard strolls around its post and stays within the sentry distance
	var g: Soldier = fresh[0]
	for m in map.mobs.duplicate():
		if m.team == 0 and m.alive:
			m.take_damage(9999.0)
	run(90.0)                          # first it walks to its post
	var spots := {}
	var far := 0.0
	for i in 400:
		run(0.5)
		spots[g.cell()] = true
		far = maxf(far, g.tp.distance_to(g.guard_pos))
	check(spots.size() >= 3, "an idle guard patrols (%d cells visited)" % spots.size())
	check(far < 9.0, "but stays near its post (%.1f tiles at most)" % far)
	r.researching = -1.0
	r.wave = wave0


func test_attack() -> void:
	var r := map.rival
	# make sure there is an army and the clock is past the first attack
	for i in 40:
		if r.soldiers().size() >= int(r.d().army):
			break
		run(60.0)
	check(r.soldiers().size() >= int(r.d().army), "the army reached the attack size (%d)" % r.soldiers().size())
	var wave_before := r.wave
	for i in 40:
		if r.wave > wave_before and r.attacking:
			break
		run(30.0)
	check(r.wave > wave_before, "it launched a new attack wave (wave %d)" % r.wave)
	var marching := r.soldiers().filter(func(m: Soldier) -> bool: return m.foe_mode == "attack")
	check(not marching.is_empty(), "its soldiers march (%d)" % marching.size())
	# nobody freezes on a leftover path: a soldier that has a path moves
	run(10.0)
	var pos := {}
	for m: Soldier in r.soldiers():
		pos[m] = m.tp
	run(8.0)
	var frozen := 0
	for m: Soldier in pos:
		if is_instance_valid(m) and m.alive and not m.path.is_empty() and m.tp.distance_to(pos[m]) < 0.3:
			frozen += 1
	check(frozen == 0, "no soldier stands frozen with a path (%d)" % frozen)
	var nearest := 9999.0
	for _i in 30:
		run(20.0)
		for m: Soldier in r.soldiers():
			nearest = minf(nearest, m.tp.distance_to(Vector2(map.size / 2.0, map.size / 2.0)))
		if nearest < 25.0:
			break
	print("      closest the attackers got to the player's Town Center: %d tiles" % int(nearest))
	check(nearest < 25.0, "the attack reached the player's base")


func test_conquest() -> void:
	_keep_player_alive()          # the attack may have cost the player the game (and its window paused the map): start fresh
	map.attacks_paused = true
	var won := [false]
	map.victory.connect(func() -> void: won[0] = true)
	for b in map.mobs.duplicate():
		if b.team == 1:
			b.take_damage(99999.0)
	# a player soldier next to a rival building attacks it on its own
	for b: FoeBuilding in map.foes:
		b.res_tech = -1                 # (a research finishing would restore the range below)
		b.range_t = 0.0                 # the Town Center's arrows would kill the lone soldier before it hits anything
	var foe: FoeBuilding = null
	var spot := Vector2.ZERO
	for h: FoeBuilding in map.foes.filter(func(b: FoeBuilding) -> bool: return b.kind == "house"):
		var cell := map.free_cell_near(Vector2i(h.tp) + Vector2i(h.bsize + 1, 0), 6)
		if not map.adjacent_path(Vector2(cell), h.rect()).is_empty():
			foe = h
			spot = Vector2(cell)
			break
	var s := map.make_unit("74", 0, spot)
	var before := {}
	for b: FoeBuilding in map.foes:
		if b.done and b.kind != "wall":
			before[b] = b.hp
	var hurt := false                 # (the rival stays paused so that it trains no new villagers to chase)
	for i in 200:
		map._process(0.1)
		_keep_player_alive()
		for b: FoeBuilding in before:
			if is_instance_valid(b) and (not b.alive or b.hp < float(before[b])):
				hurt = true
		if hurt:
			break
	var engaged: bool = hurt or is_instance_valid(s.target)       # (it may walk to a farther building first)
	check(engaged, "a player soldier beside an enemy building attacks one (hit %s, target %s %s)" % [hurt, s.target, s.target.get("kind") if is_instance_valid(s.target) else ""])
	map.attacks_paused = true
	check(not won[0], "no victory while the base stands")
	for b in map.foes.duplicate():
		b.take_damage(99999.0)
	check(map.foes.is_empty(), "every building destroyed")
	check(won[0] and map.finished, "victory is declared")
	map.finished = false
	map.attacks_paused = true


## Research changes the rival's soldiers: a unit upgrade turns a Militia into a Man-at-Arms.
func test_techs() -> void:
	var r := map.rival
	map.attacks_paused = true
	var m := map.make_unit("74", 1, Vector2(map.free_cell_near(Vector2i(r.rally), 5)))
	r._arm(m)
	check(m.uid == r.tech.current(74), "a Militia starts as what the rival has upgraded it to (%d)" % m.uid)
	var hp0 := m.max_hp
	var before: int = m.uid
	var upgrade := -1                  # the next unit upgrade at the Barracks that it does not have yet
	for id in [222, 207, 217, 264]:
		if not r.tech.is_researched(id):
			upgrade = id
			break
	if upgrade >= 0:
		r.finish_research(upgrade)
		check(m.uid != before and m.uid == r.tech.current(74), "researching %s upgrades the rival's Militia (%d -> %d)" % [Rules.techs[upgrade].name, before, m.uid])
		check(m.max_hp >= hp0 * 0.99 and m.hp_mult > 0.0, "with the difficulty's hit point factor kept (%d -> %d)" % [int(hp0), int(m.max_hp)])
	var atk0: float = 0.0
	for k: int in m.stats().atk:
		atk0 += float(m.stats().atk[k])
	var forge := 67                     # the first attack upgrade at the Blacksmith it does not have yet
	for id in [67, 68, 75]:
		if not r.tech.is_researched(id):
			forge = id
			break
	r.finish_research(forge)
	var atk1: float = 0.0
	for k: int in m.stats().atk:
		atk1 += float(m.stats().atk[k])
	check(atk1 > atk0, "%s raised its attack (%.0f -> %.0f)" % [Rules.techs[forge].name, atk0, atk1])
	m.take_damage(99999.0)
	map.attacks_paused = true


func test_save() -> void:
	# a fresh rival state for the round trip
	map.rival.age = 1
	map.rival.stock.wood = 777.0
	map.rival.tech.research(213)
	var civ0: int = map.rival.civ
	var base := map.rival.base
	var tcb := map.place_foe_building("tc", base - Vector2i(2, 2), true)
	tcb.set_age(1)
	map.place_foe_building("barracks", base + Vector2i(8, 0), false)
	var farm := map.place_foe_building("farm", base + Vector2i(0, 10), true)
	farm.food = 120.0
	var snap := SaveGame.snapshot(main)
	check(snap.has("rival") and snap.foes.size() == 3, "the rival is in the save (%d buildings)" % snap.foes.size())
	var text := JSON.stringify(snap)
	var back: Variant = JSON.parse_string(text)
	check(back is Dictionary and back.rival.age == 1 and int(back.rival.stock.wood) == 777 and int(back.rival.civ) == civ0, "and survives JSON")
	Main.pending = back
	var second: Node = load("res://scenes/main.tscn").instantiate()
	add_child(second)
	await get_tree().process_frame
	var m2: GameMap = second.map
	check(m2.rival != null and m2.rival.age == 1 and int(m2.rival.stock.wood) == 777, "a loaded game has the rival back")
	check(m2.rival.civ == civ0 and m2.rival.tech.is_researched(213) and m2.rival.tech.is_researched(22), "and its civilization and research (%s)" % Defs.civ_name(m2.rival.civ))
	check(m2.foes.size() == 3 and m2.foes[0].kind == "tc" and m2.foes[0].age == 1, "with its buildings")
	check(m2.foes.any(func(b: FoeBuilding) -> bool: return b.kind == "farm" and is_equal_approx(b.food, 120.0)), "a farm with what is left in it")
	check(m2.foes.any(func(b: FoeBuilding) -> bool: return b.kind == "barracks" and not b.done), "including the one under construction")
	second.queue_free()
	await get_tree().process_frame
