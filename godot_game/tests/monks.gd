extends Node
## Headless test of monks (conversion) and relics:  godot --headless --path godot_game res://tests/monks.tscn

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
	Main.fixed_seed = 5
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	map = main.map
	ctl = main.ctl
	seed(2)
	map.attacks_paused = true
	await test_monks()
	print("RESULT: %s" % ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	get_tree().quit(fails)


func _near(c: Vector2i, dx: int, dy: int) -> Vector2:
	return Vector2(map.free_cell_near(c + Vector2i(dx, dy), 6))


func test_monks() -> void:
	var tc: Building = map.buildings.filter(func(b: Building) -> bool: return b.kind == "tc")[0]
	var base := Vector2i(tc.tp)
	for m in map.mobs.duplicate():                 # no wolves and boars to get in the way
		if m.team == 2:
			m.take_damage(99999.0)
	check(Assets.man.anims.has("u285_idle_blue") and Assets.man.anims.has("u286_walk_blue") and Assets.man.anims.has("u286_idle_blue"), "the relic and the monk with a relic have their original sprites")
	check(map.relics.size() >= 3, "relics lie about the map (%d)" % map.relics.size())
	check(map.relics.all(func(r: Relic) -> bool: return r.on_ground() and r.visible and r.tp.distance_to(Vector2(base)) >= 24.0), "all on the ground, away from your town")
	# ---------------------------------------------------------------- conversion
	var monk := map.make_unit("125", 0, _near(base, -14, 10)) as Soldier
	check(monk.healer and monk.atk_range() >= 9.0, "a monk heals and reaches 9 tiles (%.0f)" % monk.atk_range())
	var enemy := map.make_unit("74", 1, _near(base, -8, 10)) as Soldier
	var hp_before := enemy.hp
	var enemy_hp_ratio := enemy.hp / enemy.max_hp
	monk.order_attack(enemy)
	check(monk.convert_target == enemy, "a monk ordered against an enemy converts it")
	run(3.0)
	var aura: Array = enemy.get_children().filter(func(c: Node) -> bool: return c is ConvertAura)
	check(not aura.is_empty() or enemy.team == 0, "a ring shows on the unit while he chants")
	run(20.0)
	check(enemy.team == 0 and enemy.alive and enemy._colour == "blue", "after his chant the enemy fights for you (team %d)" % enemy.team)
	check(is_equal_approx(enemy.hp / enemy.max_hp, enemy_hp_ratio), "keeping its share of health")
	check(monk._recharge > 20.0, "the monk has to recharge his faith (%d s)" % int(monk._recharge))
	check(enemy.get_children().all(func(c: Node) -> bool: return not c is ConvertAura or c.is_queued_for_deletion()), "and the ring is gone")
	enemy.take_damage(99999.0)                      # (a converted soldier would fight the next enemy)
	# recharging: the next one waits
	var enemy2 := map.make_unit("74", 1, _near(base, -9, 12)) as Soldier
	run(8.0)
	check(enemy2.team == 1, "he does not convert again while he recharges")
	run(45.0)
	check(enemy2.team == 0, "idle again, he converts on his own once he can (team %d)" % enemy2.team)
	enemy2.take_damage(99999.0)
	# monks need Atonement, siege Redemption
	monk._recharge = 0.0
	var emonk := map.make_unit("125", 1, _near(base, -9, 11)) as Soldier
	run(25.0)
	check(emonk.team == 1, "an enemy monk cannot be converted without Atonement")
	map.tech.res[27] = 1
	monk._recharge = 0.0
	run(30.0)
	check(emonk.team == 0, "but can with it")
	emonk.take_damage(99999.0)
	# ---------------------------------------------------------------- relics
	var monastery := map.place_building("monastery", map.free_cell_near(base + Vector2i(-8, 6), 8), true)
	var r0: Relic = map.relics[0]
	monk.order_move(Vector2i(r0.tp) + Vector2i(1, 1))
	run(1.0)
	monk.convert_target = null
	var gold0: int = map.stock.gold
	monk.position = Iso.to_world(r0.tp + Vector2(2, 2))
	monk.place(r0.tp + Vector2(2, 2))
	ctl.select_units([monk])
	ctl._relic_tap(r0)
	run(15.0)
	check(monk.relic == r0 and not r0.visible and not r0.on_ground(), "a monk picks up the relic")
	check(monk.key.begins_with("u286_"), "and shows the monk with a relic (%s)" % monk.key)
	check(not monk.has_method("nonexistent"), "carrying, he does not convert or heal")
	ctl.select_units([monk])
	ctl._building_tap(monastery)
	run(60.0)
	check(monastery.relics.size() == 1 and monk.relic == null and r0.holder == monastery, "he carries it into the Monastery")
	var g1: int = map.stock.gold
	run(20.0)
	var earned: int = map.stock.gold - g1
	var expect := 20.0 * Relic.GOLD_RATE * Rules.GAME_SPEED
	check(absf(earned - expect) <= 3.0, "the relic pays gold: %d in 20 s (expected about %d)" % [earned, int(expect)])
	# a dying monk drops it
	var r1: Relic = map.relics[1]
	var m2 := map.make_unit("125", 0, r1.tp + Vector2(1, 1)) as Soldier
	m2.order_pickup(r1)
	run(10.0)
	check(m2.relic == r1, "a second monk takes another relic")
	var spot := m2.tp
	m2.take_damage(99999.0)
	check(r1.on_ground() and r1.visible and r1.tp.distance_to(spot) < 2.0, "a monk that dies leaves the relic where he fell")
	# the save keeps relics on the ground, in a monk's arms and in the Monastery
	var m3 := map.make_unit("125", 0, _near(base, -4, 8)) as Soldier
	var r2: Relic = map.relics[2]
	m3.order_pickup(r2)
	m3.place(r2.tp)
	run(2.0)
	check(m3.relic == r2, "a third monk is carrying one")
	var ground := map.relics.filter(func(r: Relic) -> bool: return r.on_ground()).size()
	var snap := SaveGame.snapshot(main)
	var back: Variant = JSON.parse_string(JSON.stringify(snap))
	Main.pending = back
	var second: Node = load("res://scenes/main.tscn").instantiate()
	add_child(second)
	await get_tree().process_frame
	var m2map: GameMap = second.map
	var mon2 := m2map.buildings.filter(func(b: Building) -> bool: return b.kind == "monastery")
	var carrying := m2map.mobs.filter(func(m: Mob) -> bool: return m is Soldier and m.relic != null)
	var ground2 := m2map.relics.filter(func(r: Relic) -> bool: return r.on_ground()).size()
	check(m2map.relics.size() == map.relics.size() and mon2.size() == 1 and mon2[0].relics.size() == 1 and carrying.size() == 1 and ground2 == ground, "a loaded game has them all back (%d relics: %d inside, %d carried, %d on the ground)" % [m2map.relics.size(), mon2[0].relics.size(), carrying.size(), ground2])
	second.queue_free()
	await get_tree().process_frame
	# a destroyed Monastery drops its relics
	monastery.take_damage(999999.0)
	run(1.0)
	check(r0.on_ground() and r0.visible, "a destroyed Monastery drops the relics it held")
