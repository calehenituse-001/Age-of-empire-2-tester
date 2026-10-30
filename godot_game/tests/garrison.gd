extends Node
## Headless test of garrisons:  godot --headless --path godot_game res://tests/garrison.tscn

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
	await test_garrison()
	print("RESULT: %s" % ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	get_tree().quit(fails)


func _tower_spot() -> Vector2i:
	var tc := map.buildings[0]
	return map.free_cell_near(Vector2i(tc.tp) + Vector2i(7, 0), 8)


func test_garrison() -> void:
	var tc: Building = map.buildings.filter(func(b: Building) -> bool: return b.kind == "tc")[0]
	var tower := map.place_building("tower", _tower_spot(), true)
	var house := map.place_building("house", map.free_cell_near(Vector2i(tc.tp) + Vector2i(0, 8), 8), true)
	var barracks := map.place_building("barracks", map.free_cell_near(Vector2i(tc.tp) + Vector2i(-8, 0), 8), true)
	check(house.garrison_cap() == 0, "a house takes nobody")
	var soldiers: Array[Mob] = []
	for i in 3:
		soldiers.append(map.make_unit("74", 0, Vector2(map.free_cell_near(Vector2i(tower.tp) + Vector2i(3, i), 6))))
	var vills: Array[Mob] = []
	for i in 2:
		vills.append(map.make_unit("villager", 0, Vector2(map.free_cell_near(Vector2i(tower.tp) + Vector2i(5, 4 + i), 6))))
	map.recalc_pop()
	check(not tower.can_garrison(soldiers[0]) and not tc.can_garrison(vills[0]) and not barracks.can_garrison(soldiers[0]), "nothing can garrison: neither soldiers nor villagers")
	check(tower.tower_shots() == 1, "a tower shoots its own arrows only")
	ctl.select_units(soldiers)
	ctl._building_tap(tower)
	check(ctl.sel_b == tower and tower.garrison.is_empty() and soldiers.all(func(m: Mob) -> bool: return m.visible and m.garrisoned_in == null and m.garrison_target == null), "tapping a tower with soldiers selected just selects the tower")
	ctl.select_units([vills[0]])
	ctl._building_tap(tc)
	check(ctl.sel_b == tc and vills[0].garrisoned_in == null, "and a Town Center with a villager selected too")
	check(Building.GARRISON == false and tc.garrison_cap() == 0, "the garrison size is 0 everywhere")
	# a villager that is given a job is let go of, so that a later tap does not send it away
	var tree := map.find_resource("wood", Vector2i(tc.tp), 40)
	var worker := map.make_unit("villager", 0, Vector2(map.free_cell_near(Vector2i(tc.tp) + Vector2i(0, 4), 5)))
	var friend := map.make_unit("villager", 0, Vector2(map.free_cell_near(Vector2i(tc.tp) + Vector2i(2, 4), 5)))
	ctl.select_units([worker, friend])
	ctl._gather(tree)
	check(ctl.sel_units.is_empty() and not worker.selected and worker.job == "gather", "villagers given a job to gather are deselected (%d selected)" % ctl.sel_units.size())
	ctl._move_to(Vector2i(tc.tp) + Vector2i(6, 6))
	check(worker.job == "gather", "so a tap elsewhere does not take them off it")
	var dest := Vector2i(tc.tp) + Vector2i(6, 6)
	ctl.select_units([friend])
	ctl._move_to(dest)
	var markers := map.entities.get_children().filter(func(c: Node) -> bool: return c is MoveMarker)
	var marker: MoveMarker = markers[markers.size() - 1] if not markers.is_empty() else null
	check(marker != null and marker.position.distance_to(Iso.to_world(Vector2(dest))) < 1.0 and marker.get_child_count() == 4, "a move order puts the four arrows on the tapped spot")
	var site := map.place_building("house", map.free_cell_near(Vector2i(tc.tp) + Vector2i(-6, -6), 6), false)
	ctl.select_units([friend, worker])
	ctl._building_tap(site)
	check(ctl.sel_units.is_empty() and friend.job == "build", "and the same for building")
