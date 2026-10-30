extends Node
## Headless test of the lasso selection (touch events fed to the camera):  godot --headless --path godot_game res://tests/lasso.tscn

var main: Node
var map: GameMap
var ctl: Controller
var cam: RtsCamera
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	Main.map_size = 96
	Main.opponent = "raids"
	Main.fixed_seed = 5
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	map = main.map
	ctl = main.ctl
	cam = main.cam
	seed(2)
	map.attacks_paused = true
	await test_lasso()
	print("RESULT: %s" % ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	get_tree().quit(fails)


func touch(idx: int, p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = p
	e.pressed = pressed
	cam._unhandled_input(e)


func drag(idx: int, p: Vector2, last: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = p
	e.relative = p - last
	cam._unhandled_input(e)


## A double tap at `at` and then a drag along `route`, the second finger staying down; releases at the end unless told not to.
func double_tap_draw(at: Vector2, route: Array, release := true) -> void:
	touch(0, at, true)
	touch(0, at, false)
	touch(0, at + Vector2(6, 4), true)
	var last := at + Vector2(6, 4)
	for p: Vector2 in route:
		drag(0, p, last)
		last = p
	if release:
		touch(0, last, false)


func _screen(m: Mob) -> Vector2:
	return cam.world_to_screen(m.position + Vector2(0, -22.0))


func test_lasso() -> void:
	for m in map.mobs.duplicate():
		if m.team == 2:
			m.take_damage(99999.0)
	var tc: Building = map.buildings.filter(func(b: Building) -> bool: return b.kind == "tc")[0]
	var spot := Vector2i(tc.tp) + Vector2i(-10, 8)
	cam.position = Iso.to_world(Vector2(spot))
	var inside: Array[Mob] = []
	for i in 4:
		inside.append(map.make_unit("villager" if i < 2 else "74", 0, Vector2(map.free_cell_near(spot + Vector2i(i % 2, i / 2), 3))))
	var enemy := map.make_unit("74", 1, Vector2(map.free_cell_near(spot + Vector2i(1, 1), 3)))
	var far := map.make_unit("villager", 0, Vector2(map.free_cell_near(spot + Vector2i(14, -12), 3)))
	var centre := Vector2.ZERO
	for m in inside:
		centre += _screen(m)
	centre /= inside.size()
	var radius := 0.0
	for m in inside:
		radius = maxf(radius, _screen(m).distance_to(centre))
	radius += 70.0
	check(_screen(far).distance_to(centre) > radius + 20.0 and _screen(enemy).distance_to(centre) < radius, "the setup: four units in a circle, one far away, an enemy among them")
	var ring: Array = []
	for i in 28:
		var a := TAU * i / 28.0
		ring.append(centre + Vector2(cos(a), sin(a)) * radius)
	# a loop round them
	var cam0 := cam.position
	var pre := far
	ctl.select_units([pre])
	var started := [0, 0]
	cam.lasso_started.connect(func() -> void: started[0] += 1)
	cam.lasso_ended.connect(func(p: PackedVector2Array) -> void: started[1] = p.size())
	var k := 0                                      # the loop starts where the double tap lands: on open ground, where nothing is tapped
	while k < ring.size() and ctl.pick(cam.screen_to_world(ring[k])) != null:
		k += 1
	ring = ring.slice(k) + ring.slice(0, k)
	double_tap_draw(ring[0], ring.slice(1) + [ring[0]])
	check(started[0] == 1 and started[1] >= 20, "a double tap that stays down starts a lasso and reports the loop (%d points)" % started[1])
	var picked := ctl.sel_units.duplicate()
	check(picked.size() == 4 and inside.all(func(m: Mob) -> bool: return picked.has(m)), "the four units inside the loop are selected (%d)" % picked.size())
	check(not picked.has(enemy) and not picked.has(far), "not the enemy among them and not the far villager")
	check(cam.position == cam0, "the map did not scroll while the loop was drawn")
	await get_tree().create_timer(0.5).timeout
	check(pre.order == "idle" if pre is Soldier else pre.path.is_empty(), "the first tap of the double tap did not send the earlier selection away")
	# a straight diagonal drag: the rectangle
	ctl.clear_selection()
	var tl := centre - Vector2(radius, radius)
	var br := centre + Vector2(radius, radius)
	var route: Array = []
	for i in 12:
		route.append(tl.lerp(br, (i + 1) / 12.0))
	double_tap_draw(tl - Vector2(100, 0), [tl] + route)
	check(ctl.sel_units.size() == 4 and not ctl.sel_units.has(enemy), "a diagonal drag selects the rectangle, like the mouse on a PC (%d)" % ctl.sel_units.size())
	# a double tap that does not draw is two ordinary taps
	ctl.clear_selection()
	var taps := [0]
	cam.tapped.connect(func(_w: Vector2) -> void: taps[0] += 1)
	touch(0, centre + Vector2(200, 100), true)
	touch(0, centre + Vector2(200, 100), false)
	touch(0, centre + Vector2(203, 100), true)
	touch(0, centre + Vector2(203, 100), false)
	check(taps[0] == 2 and not cam._lasso and not cam._lasso_armed, "a double tap without a drag is two taps (%d)" % taps[0])
	await get_tree().create_timer(0.45).timeout
	# a second finger cancels it
	ctl.clear_selection()
	touch(0, centre, true)
	touch(0, centre, false)
	touch(0, centre + Vector2(5, 5), true)
	drag(0, centre + Vector2(60, 5), centre + Vector2(5, 5))
	touch(1, centre + Vector2(300, 300), true)
	check(not cam._lasso and ctl.sel_units.is_empty(), "a second finger cancels the lasso")
	touch(1, centre + Vector2(300, 300), false)
	touch(0, centre + Vector2(60, 5), false)
	# too slow for a double tap: no lasso
	touch(0, centre, true)
	touch(0, centre, false)
	await get_tree().create_timer(0.45).timeout
	touch(0, centre + Vector2(4, 4), true)
	check(not cam._lasso, "a second touch after the double tap window is an ordinary touch")
	touch(0, centre + Vector2(4, 4), false)
	await get_tree().create_timer(0.45).timeout
	# not while a building is being placed
	ctl.placing = "house"
	touch(0, centre, true)
	touch(0, centre, false)
	touch(0, centre + Vector2(3, 3), true)
	check(not cam._lasso, "no lasso while a building is being placed")
	touch(0, centre + Vector2(3, 3), false)
	ctl.placing = ""
	await get_tree().create_timer(0.45).timeout
	# an ordinary tap on the ground still moves the selection, a moment later
	ctl.select_units([inside[2]])
	var gc := map.free_cell_near(spot + Vector2i(7, 7), 6)
	while map.res_by_cell.has(gc) or map.is_occupied(gc) or map.find_path(inside[2].tp, gc).is_empty() or ctl.pick(Iso.to_world(Vector2(gc))) != null:
		gc += Vector2i(1, 0)
	var ground := Iso.to_world(Vector2(gc))
	ctl.on_tap(ground)
	check(inside[2].path.is_empty() or inside[2].order != "move", "the move order waits a moment (for the lasso)")
	await get_tree().create_timer(0.6).timeout
	check(inside[2].order == "move" or not inside[2].path.is_empty(), "and then goes ahead")
	# the overlay
	check(main.hud.lasso != null and main.hud.lasso.points.is_empty(), "the lasso picture is cleared afterwards")
