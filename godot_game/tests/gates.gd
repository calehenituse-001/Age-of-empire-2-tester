extends Node
## Headless test of gates:  godot --headless --path godot_game res://tests/gates.tscn

var main: Node
var map: GameMap
var ctl: Controller
var fails := 0
var centre := Vector2i.ZERO
const HALF := 4


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
	Main.fixed_seed = 5
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	map = main.map
	ctl = main.ctl
	seed(1)
	map.attacks_paused = true
	map.stock.stone = 2000
	map.stock.wood = 2000
	await test_gates()
	print("RESULT: %s" % ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	get_tree().quit(fails)


## A closed box of wall around `centre`, the gate in the middle of its top side (cells x-1..x+1 at y - HALF).
func _box(with_gate: bool) -> Building:
	for i in range(-HALF, HALF + 1):
		for c: Vector2i in [Vector2i(centre.x + i, centre.y - HALF), Vector2i(centre.x + i, centre.y + HALF), Vector2i(centre.x - HALF, centre.y + i), Vector2i(centre.x + HALF, centre.y + i)]:
			if with_gate and c.y == centre.y - HALF and absi(c.x - centre.x) <= 1:
				continue
			if not map.walls.has(c):
				map.place_building("wall", c, true)
	return map.place_building("gate", Vector2i(centre.x - 1, centre.y - HALF), true, "x") if with_gate else null


func _inside_out(team: int) -> bool:
	return not map.find_path(Vector2(centre), Vector2i(centre.x, centre.y - HALF - 3), false, false, team).is_empty()


## A dry square of 17 x 17 cells without buildings, near the Town Center.
func _find_site(near: Vector2i) -> Vector2i:
	for r in range(10, 30):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := near + Vector2i(dx, dy)
				var ok := true
				for y in range(c.y - 8, c.y + 9):
					for x in range(c.x - 8, c.x + 9):
						var p := Vector2i(x, y)
						if not map.in_bounds(p) or map.inland[y * map.size + x] != 1 or map.is_occupied(p) and not map.res_by_cell.has(p):
							ok = false
							break
					if not ok:
						break
				if ok:
					return c
	return Vector2i(-1, -1)


func test_gates() -> void:
	var tc: Building = map.buildings.filter(func(b: Building) -> bool: return b.kind == "tc")[0]
	centre = _find_site(Vector2i(tc.tp))
	check(centre.x >= 0, "a dry open place for the test (%s)" % centre)
	map.clear_resources(centre, 10.0)
	check(Defs.lock_reason(map.tech, "gate") != "", "gates need the Feudal Age (%s)" % Defs.lock_reason(map.tech, "gate"))
	map.tech.research(Rules.AGE_TECHS[0])
	check(Defs.lock_reason(map.tech, "gate") == "", "and are available in it")
	var gate := _box(true)
	check(gate.rect() == Rect2i(Vector2i(centre.x - 1, centre.y - HALF), Vector2i(3, 1)), "a gate is 3 cells long (%s)" % gate.rect())
	check(map.walls.get(Vector2i(centre.x, centre.y - HALF)) == gate, "it counts as wall for its neighbours")
	check(gate.look_key() == "bld_490" and Assets.man.buildings.has("bld_490"), "its picture is the original's (%s)" % gate.look_key())
	check(_inside_out(0), "your units walk through your gate")
	check(not _inside_out(1), "enemy units cannot")
	map.set_gate_locked(gate, true)
	check(not _inside_out(0), "a locked gate shuts for your own units too")
	map.set_gate_locked(gate, false)
	check(_inside_out(0), "and opens again")
	# it opens for a unit that comes close
	var v := map.make_unit("villager", 0, Vector2(centre.x, centre.y - HALF + 2))
	run(1.0)
	check(gate.gate_open, "it opens when a unit of ours is close")
	v.order_move(Vector2i(centre.x, centre.y + 1))
	run(8.0)
	check(not gate.gate_open, "and shuts when it has gone")
	# a villager walks out through it
	v.order_move(Vector2i(centre.x, centre.y - HALF - 3))
	run(20.0)
	check(v.tp.y < centre.y - HALF - 1.0, "a villager walks out through the gate (y %.1f)" % v.tp.y)
	# an enemy outside cannot get in, so it breaks the wall or the gate
	map.attacks_paused = false
	var enemy := map.make_unit("74", 1, Vector2(centre.x, centre.y - HALF - 6))
	enemy.dmg_mult = 400.0
	var inside_house := map.place_building("house", Vector2i(centre.x - 1, centre.y), true)
	enemy.order_attack(inside_house) if enemy.has_method("order_attack") else null
	run(1.0)
	var hp_before := 0.0
	for w: Building in map.walls.values():
		hp_before += w.hp
	run(50.0)
	print("      enemy ", enemy.tp, " alive ", enemy.alive, " target ", enemy.target, " path ", enemy.path.size(), " mode ", enemy.foe_mode, " blocker ", map.nearest_blocker(enemy.tp, 1))
	var broke := false
	for w: Building in map.walls.values():
		if w.hp < w.max_hp - 1.0:
			broke = true
	var through := not map.find_path(Vector2(centre.x, centre.y - HALF - 6), Vector2i(centre.x, centre.y + 2), false, false, 1).is_empty()
	check(broke or through, "an enemy that cannot get in attacks the wall or gate (damage %s, opened %s)" % [broke, through])
	enemy.take_damage(999999.0)
	map.attacks_paused = true
	# destroying the gate opens the way for the enemy
	gate.take_damage(999999.0)
	run(1.0)
	check(not map.walls.has(Vector2i(centre.x, centre.y - HALF)) and _inside_out(1), "a destroyed gate leaves an opening for everybody")
	# placing a gate over a wall with the controller
	var top := Vector2i(centre.x + 2, centre.y + HALF)             # on the bottom side: a wall piece there
	var pieces := 0
	ctl.select_units([v])
	ctl.start_place("gate")
	ctl.move_ghost(Iso.to_world(Vector2(top)))
	check(ctl.place_axis == "x" and ctl.place_ok, "the placement turns the gate along the wall and accepts it (%s, %s)" % [ctl.place_axis, ctl.place_ok])
	check(ctl.place_origin == top - Vector2i(1, 0), "centred on the tapped piece (%s)" % ctl.place_origin)
	var stone0: int = map.stock.stone
	ctl.confirm_place()
	var g2: Building = null
	for b in map.buildings:
		if b.kind == "gate":
			g2 = b
	check(g2 != null and not g2.done and map.stock.stone == stone0 - 30, "it costs 30 stone and is a building site (%d -> %d)" % [stone0, map.stock.stone])
	for i in 3:
		var w2: Building = map.walls.get(g2.origin + Vector2i(i, 0))
		check(w2 == g2, "the wall pieces under it were replaced (cell %d)" % i)
	run(30.0)
	print("      builder ", v.tp, " state ", v.state, " job ", v.job, " site ", v.site, " g2 ", g2, " work ", g2.work, "/", g2.work_needed, " path ", v.path.size())
	check(g2.done, "a villager built it")
	# rotating
	ctl.start_place("gate")
	ctl.move_ghost(Iso.to_world(Vector2(centre.x + 12, centre.y)))
	var before_axis := ctl.place_axis
	ctl.rotate_gate()
	check(ctl.place_axis != before_axis and ctl._ghost.gate_axis == ctl.place_axis, "Turn rotates the gate (%s -> %s)" % [before_axis, ctl.place_axis])
	ctl.cancel_place()
	# the save keeps axis and lock
	map.set_gate_locked(g2, true)
	var snap := SaveGame.snapshot(main)
	var back: Variant = JSON.parse_string(JSON.stringify(snap))
	Main.pending = back
	var second: Node = load("res://scenes/main.tscn").instantiate()
	add_child(second)
	await get_tree().process_frame
	var m2: GameMap = second.map
	var gs := m2.buildings.filter(func(b: Building) -> bool: return b.kind == "gate")
	check(gs.size() == 1 and gs[0].gate_axis == "x" and gs[0].locked and gs[0].done, "a loaded game has the gate, its direction and its lock (%d)" % gs.size())
	check(m2.walls.get(gs[0].origin) == gs[0], "registered as wall")
	second.queue_free()
	await get_tree().process_frame
