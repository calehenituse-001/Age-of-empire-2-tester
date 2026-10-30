extends Node
## Balance harness:  godot --headless --path godot_game res://tests/balance.tscn
## Not a pass/fail test: it prints how the economy and the raids behave so the numbers can be tuned.

const OUT := "/tmp/claude-1000/-home-j3rry-AOE/48fd23bc-a526-402f-a121-09f9de1cfe49/scratchpad/balance.txt"
var lines: PackedStringArray = []


func say(t: String) -> void:
	print(t)
	lines.append(t)


func new_map(seed_: int) -> GameMap:
	var m := GameMap.new()
	m.difficulty = "medium"
	add_child(m)
	m.generate(128, seed_)
	m.attacks_paused = false
	m.director.next_raid = 1.0e9
	m.place_building("tc", Vector2i(62, 62), true)
	return m


func run(m: GameMap, seconds: float) -> void:
	for i in int(seconds / 0.1):
		m._process(0.1)


func _ready() -> void:
	wildlife()
	perf()
	economy()
	for diff in ["easy", "medium", "hard"]:
		for wave in [1, 2, 3, 5, 7, 9]:
			raid(diff, wave, 8, false)
			raid(diff, wave, 16, true)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	get_tree().quit()


## What N villagers bring in per minute with the real rates, camps next to the work.
func economy() -> void:
	var m := new_map(11)
	say("== economy (real rates, per villager per minute, game time) ==")
	for k in ["wood", "food", "gold", "stone"]:
		say("%s gathering: %.2f/s = %.0f/min at the start (data work rate x 1.5)" % [k, m.gather_rate(k if k != "food" else "food"), m.gather_rate(k if k != "food" else "food") * 60.0])
	say("farm: %.2f/s = %.0f/min; villager walks %.2f tiles/s; carries %d wood" % [m.gather_rate("farm"), m.gather_rate("farm") * 60.0, Defs.UNITS.villager.speed, m.carry_cap("wood")])
	say("villager train time %.1f s, house %.1f s to build, Feudal Age %.0f s to research" % [Defs.UNITS.villager.time, Defs.BUILDINGS.house.time, m.tech.time_of(101) / Rules.GAME_SPEED])
	# 10 villagers chopping with a camp: how much wood in 5 minutes
	var camp_cell := Vector2i(-1, -1)
	var tree := m.find_resource("wood", Vector2i(62, 62), 40)
	if tree != null:
		camp_cell = tree.cell + Vector2i(-2, 0)
		var camp := m.place_building("lumber_camp", Vector2i(clampi(camp_cell.x, 2, 120), clampi(camp_cell.y, 2, 120)), true)
		for i in 10:
			var v := m.make_unit("villager", 0, camp.tp + Vector2(2 + i % 4, 2 + i / 4)) as Villager
			v.order_gather(m.find_resource("wood", camp.origin, 30))
		var w0: int = m.stock.wood
		run(m, 300.0)
		say("10 villagers on wood with a camp: +%d wood in 5 min = %.0f per villager per minute (camp %.0f tiles from the tree)" % [m.stock.wood - w0, (m.stock.wood - w0) / 50.0, camp.tp.distance_to(Vector2(tree.cell))])
	m.queue_free()


## A raid of `wave` on `diff` against `n` soldiers (Militia, with half Spearmen), optionally with two Watch Towers.
func raid(diff: String, wave: int, n: int, towers: bool) -> void:
	var m := new_map(21)
	m.difficulty = diff
	m.tech.research(101)
	m._tech_applied()
	var centre := Vector2(64, 64)
	for i in n:
		m.make_unit("93" if i % 2 == 1 else "74", 0, centre + Vector2(3 + i % 4, 3 + i / 4))
	if towers:
		m.place_building("tower", Vector2i(58, 58), true)
		m.place_building("tower", Vector2i(68, 58), true)
	m.director.wave = wave - 1
	m.director.raid()
	var raiders := m.mobs.filter(func(x: Mob) -> bool: return x.team == 1).size()
	var tc: Building = m.buildings[0]
	var t := 0.0
	while t < 400.0:
		run(m, 5.0)
		t += 5.0
		if m.mobs.filter(func(x: Mob) -> bool: return x.team == 1).is_empty():
			break
	var left := m.mobs.filter(func(x: Mob) -> bool: return x.team == 1).size()
	var mine := m.mobs.filter(func(x: Mob) -> bool: return x.team == 0 and x is Soldier).size()
	say("%-6s wave %d vs %2d soldiers%s: %2d raiders -> %2d left after %3.0f s, my soldiers %2d/%d, town center %3.0f%%" % [diff, wave, n, " +2 towers" if towers else "          ", raiders, left, t, mine, n, tc.hp / tc.max_hp * 100.0])
	m.queue_free()


## Late-game cost of one simulation step: a big map with trees, 70 villagers, 40 soldiers, 40 buildings, fish and wild animals.
func perf() -> void:
	var m := GameMap.new()
	m.difficulty = "medium"
	add_child(m)
	m.generate(160, 5)
	m.place_building("tc", Vector2i(78, 78), true)
	m.scatter_forests(Vector2i(80, 80), 10.0)
	for i in 8:
		m.scatter_clump("gold", Vector2i(m.rng.randi_range(20, 140), m.rng.randi_range(20, 140)), 5, 1.6)
		m.scatter_clump("berries", Vector2i(m.rng.randi_range(20, 140), m.rng.randi_range(20, 140)), 5, 1.5)
	m.scatter_fish()
	m.director.populate_wild(40)
	m.tech.research(101)
	m.tech.research(102)
	m._tech_applied()
	for i in 40:
		var o := Vector2i(70 + (i % 8) * 4, 90 + (i / 8) * 3)
		if m.can_place("house", o):
			m.place_building("house", o, true)
	for i in 70:
		var v := m.make_unit("villager", 0, Vector2(78, 80) + Vector2(i % 10, i / 10)) as Villager
		var r := m.find_resource("wood", Vector2i(78, 80), 40)
		if r != null:
			v.order_gather(r)
	for i in 40:
		m.make_unit("74" if i % 2 == 0 else "4", 0, Vector2(80, 76) + Vector2(i % 8, i / 8))
	m.attacks_paused = true
	run(m, 20.0)
	var t0 := Time.get_ticks_usec()
	var steps := 300
	for i in steps:
		m._process(0.1)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0 / steps
	say("late game: %d mobs, %d buildings, %d resources: %.2f ms per simulation step (desktop; budget 8.3 ms at 120 Hz, a tablet is 3-5x slower)" % [m.mobs.size(), m.buildings.size(), m.res_by_cell.size(), ms])
	m.queue_free()


## Wild animals against a starting village: 5 villagers chopping and farming near the Town Center, 2 militia, 5 minutes.
func wildlife() -> void:
	for diff in ["easy", "medium", "hard"]:
		var lost := 0
		var seeds := [3, 4, 5, 6]
		for sd in seeds:
			var m := new_map(sd)
			m.difficulty = diff
			m.scatter_forests(Vector2i(64, 64), 10.0)
			m.director.populate_wild(int(m.director.wild_cap() * 0.7))
			for i in 5:
				var v := m.make_unit("villager", 0, Vector2(62, 66) + Vector2(i, 0)) as Villager
				var r := m.find_resource("wood", Vector2i(62, 66), 40)
				if r != null:
					v.order_gather(r)
			for i in 2:
				m.make_unit("74", 0, Vector2(66, 66) + Vector2(i, 0))
			run(m, 300.0)
			lost += 5 - m.mobs.filter(func(x: Mob) -> bool: return x is Villager and x.team == 0).size()
			m.queue_free()
		say("wildlife, %-6s: %.1f of 5 villagers lost per 5 minutes (average over %d maps)" % [diff, lost / float(seeds.size()), seeds.size()])
