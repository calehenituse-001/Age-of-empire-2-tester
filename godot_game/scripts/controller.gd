class_name Controller
extends Node
## Turns taps into selection, orders and building placement.

signal selection_changed
signal placing_changed

var map: GameMap
var cam: RtsCamera
var sel_units: Array[Mob] = []
var sel_b: Building
var sel_res: ResNode
var placing := ""
var place_origin := Vector2i.ZERO
var place_ok := false
var place_axis := "x"         # gates: the way the 3 cells run

var _ghost: Building
var wall_pts: Array[Vector2i] = []      # wall tool: the corner points tapped so far
var wall_cells: Array[Vector2i] = []
var _wall_ghosts: Array[Building] = []
var _idle_i := 0
var _pending_move := 0        # a move order on the open ground waits a moment: a double tap that turns into a lasso must not send units off


func toast(text: String) -> void:
	map.message.emit(text)


# ------------------------------------------------------------------ selection
func clear_selection() -> void:
	for m in sel_units:
		if is_instance_valid(m):
			m.set_selected(false)
	sel_units.clear()
	if is_instance_valid(sel_b):
		sel_b.set_selected(false)
	sel_b = null
	if is_instance_valid(sel_res):
		sel_res.set_selected(false)
	sel_res = null
	selection_changed.emit()


func select_units(units: Array) -> void:
	clear_selection()
	for m: Mob in units:
		sel_units.append(m)
		m.set_selected(true)
	selection_changed.emit()


func select_building(b: Building) -> void:
	clear_selection()
	sel_b = b
	b.set_selected(true)
	selection_changed.emit()


func prune() -> void:
	var gone := false
	for i in range(sel_units.size() - 1, -1, -1):
		if not is_instance_valid(sel_units[i]) or not sel_units[i].alive or sel_units[i].garrisoned_in != null:
			sel_units.remove_at(i)
			gone = true
	if sel_b != null and (not is_instance_valid(sel_b) or not sel_b.alive):
		sel_b = null
		gone = true
	if sel_res != null and (not is_instance_valid(sel_res) or not sel_res.alive):
		sel_res = null
		gone = true
	if gone:
		selection_changed.emit()


func select_idle_villager() -> void:
	var idle: Array[Mob] = []
	for m in map.mobs:
		if m is Villager and m.is_idle():
			idle.append(m)
	if idle.is_empty():
		toast("No idle villagers")
		return
	_idle_i = (_idle_i + 1) % idle.size()
	select_units([idle[_idle_i]])
	cam.position = idle[_idle_i].position


func select_all_villagers() -> void:
	var v: Array[Mob] = []
	for m in map.mobs:
		if m is Villager:
			v.append(m)
	if v.is_empty():
		toast("You have no villagers")
	else:
		select_units(v)


func select_army() -> void:
	var a: Array[Mob] = []
	for m in map.mobs:
		if m is Soldier and m.team == 0:
			a.append(m)
	if a.is_empty():
		toast("You have no soldiers: build a Barracks")
	else:
		select_units(a)


# ------------------------------------------------------------------ taps
func pick(w: Vector2) -> Object:
	var best: Object = null
	var best_y := -INF
	for m in map.mobs:
		if m.get_rect().grow(8.0).has_point(m.to_local(w)) and m.position.y > best_y:
			best = m
			best_y = m.position.y
	for r in map.relics:
		if r.visible and r.on_ground() and r.get_rect().grow(10.0).has_point(r.to_local(w)) and r.position.y > best_y:
			best = r
			best_y = r.position.y
	if best:
		return best
	var t := Iso.to_tile(w)
	var c := Vector2i(roundi(t.x), roundi(t.y))
	for b in map.buildings:
		var hit := false
		if b.kind == "farm":
			hit = b.rect().has_point(c)
		else:
			hit = b.get_rect().has_point(b.to_local(w)) or b.rect().has_point(c)
		if hit and b.position.y > best_y:
			best = b
			best_y = b.position.y
	for b in map.foes:
		if b.alive and (b.get_rect().has_point(b.to_local(w)) or b.rect().has_point(c)) and b.position.y > best_y:
			best = b
			best_y = b.position.y
	if best:
		return best
	for i in range(-1, 6):
		for j in range(-1, 6):
			var n: ResNode = map.res_by_cell.get(c + Vector2i(i, j))
			if n and n.get_rect().grow(4.0).has_point(n.to_local(w)) and n.position.y > best_y:
				best = n
				best_y = n.position.y
	var fish: ResNode = map.res_by_cell.get(c)
	if fish is FishNode:                  # a school is mostly a ripple: tapping its cell counts
		return fish
	return best


func on_tap(w: Vector2) -> void:
	if placing != "":
		move_ghost(w)
		return
	var hit := pick(w)
	if hit is Relic:
		_relic_tap(hit)
	elif hit is Mob:
		if hit.team == 0:
			select_units([hit])
		else:
			_attack(hit)
	elif hit is Building:
		_building_tap(hit)
	elif hit is ResNode:
		_gather(hit)
	else:
		if sel_units.is_empty():
			_move_to(Iso.to_cell(w))
		else:
			_move_later(Iso.to_cell(w))


const MOVE_DELAY := 0.33        # a little longer than the camera's double tap window


func _move_later(c: Vector2i) -> void:
	_pending_move += 1
	var token := _pending_move
	get_tree().create_timer(MOVE_DELAY).timeout.connect(func() -> void:
		if token == _pending_move:
			_move_to(c))


func cancel_pending_move() -> void:
	_pending_move += 1


## The loop drawn with a finger (screen points): every unit of ours whose body is inside it is selected. A line instead of a loop (a
## diagonal drag, as with the mouse on a PC) selects the rectangle that has the first and the last point as corners.
func select_in_lasso(points: PackedVector2Array) -> void:
	if points.size() < 3 or placing != "":
		return
	var lo := points[0]
	var hi := points[0]
	var area := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		area += a.x * b.y - b.x * a.y
		lo = lo.min(a)
		hi = hi.max(a)
	area = absf(area) * 0.5
	var box := (hi - lo)
	var as_rect := area < 0.18 * maxf(box.x * box.y, 1.0)
	var rect := Rect2(points[0], Vector2.ZERO).expand(points[points.size() - 1])
	var picked: Array[Mob] = []
	for m in map.mobs:
		if m.team != 0 or not m.alive or not m.visible or m.garrisoned_in != null or not (m is Villager or m is Soldier or m is Ship):
			continue
		var p := cam.world_to_screen(m.position + Vector2(0, -22.0))
		if (rect.has_point(p) if as_rect else Geometry2D.is_point_in_polygon(p, points)):
			picked.append(m)
	if picked.is_empty():
		toast("No units there")
		return
	select_units(picked)
	toast("%d unit%s selected" % [picked.size(), "" if picked.size() == 1 else "s"])


## Villagers that have just been given a job are let go of: the next tap elsewhere would send them away from it.
func release(units: Array) -> void:
	var any := false
	for m in units:
		if sel_units.has(m):
			sel_units.erase(m)
			if is_instance_valid(m):
				m.set_selected(false)
			any = true
	if any:
		selection_changed.emit()


## A relic: a monk that is selected goes and picks it up; otherwise a hint.
func _relic_tap(r: Relic) -> void:
	var best: Soldier = null
	var best_d := INF
	for m in sel_units:
		if m is Soldier and m.healer and m.relic == null:
			var d: float = m.tp.distance_to(r.tp)
			if d < best_d:
				best_d = d
				best = m
	if best == null:
		toast("A relic. Send a monk to carry it to your Monastery: it pays gold for as long as it stays there.")
		return
	best.order_pickup(r)
	Chatter.say(best, "relic")
	toast("A monk goes for the relic")


func _attack(target: Mob) -> void:
	var n := 0
	var hunters: Array = []
	for m in sel_units:
		if m is Soldier:
			m.order_attack(target)
			n += 1
		elif m is Villager and target is Animal and target.food() > 0:
			m.order_hunt(target)
			hunters.append(m)
			n += 1
	if not hunters.is_empty():
		Chatter.say_some(hunters, "food")
		release(hunters)
	if n == 0:
		toast("Select soldiers to attack")
	else:
		Chatter.say_some(sel_units.filter(func(u: Mob) -> bool: return u is Soldier), "attack")
		var mk := TargetMarker.new()
		mk.z_index = 50
		target.add_child(mk)


func _gather(r: ResNode) -> void:
	var n := 0
	var workers: Array = []
	for m in sel_units:
		if m is Villager and r.kind != "fish":
			m.order_gather(r)
			workers.append(m)
			n += 1
		elif m is Ship and r is FishNode:
			m.order_fish(r)
			n += 1
	if n > 0:
		r.flash()
		if r.kind != "fish":
			Chatter.say_some(workers, r.kind)
		release(workers)
	elif sel_units.is_empty():
		clear_selection()
		sel_res = r
		r.set_selected(true)
		selection_changed.emit()
	else:
		_move_to(r.cell)


## Soldiers go for the rival's building; with none selected the tap tells what it is.
func _attack_building(b: Building) -> void:
	var n := 0
	for m in sel_units:
		if m is Soldier:
			m.order_attack(b)
			n += 1
	if n == 0:
		toast("%s: %d of %d hit points. Select soldiers to attack it." % [b.title(), int(b.hp), int(b.max_hp)])
		return
	b.flash()
	Chatter.say_some(sel_units.filter(func(u: Mob) -> bool: return u is Soldier), "attack")


func _building_tap(b: Building) -> void:
	if b.team == 1:
		_attack_building(b)
		return
	var vills: Array[Villager] = []
	for m in sel_units:
		if m is Villager:
			vills.append(m)
	if not vills.is_empty() and not b.done:
		for v in vills:
			v.order_build(b)
		b.flash()
		Chatter.say_some(vills, "build")
		release(vills)
		return
	if not vills.is_empty() and b.kind == "farm" and b.food > 0.0 and (b.farmer == null or not is_instance_valid(b.farmer)):
		vills[0].order_farm(b)
		Chatter.say(vills[0], "farm")
		release([vills[0]])
		return
	if not vills.is_empty() and b.done and b.hp < b.max_hp - 0.5:
		for v in vills:
			v.order_repair(b)
		b.flash()
		Chatter.say_some(vills, "repair")
		toast("Repairing %s" % b.def.name)
		release(vills)
		return
	if b.kind == "monastery" and b.done:
		var carriers := sel_units.filter(func(u: Mob) -> bool: return u is Soldier and u.relic != null)
		if not carriers.is_empty():
			for m: Soldier in carriers:
				m.order_deliver(b)
			b.flash()
			toast("The relic goes to the Monastery")
			return
	if not sel_units.is_empty() and b.done and b.garrison_cap() > 0 and _garrison_selected(b):
		return
	select_building(b)


## The selected units go into the building (as many as fit and are allowed in). False when none can: the tap then selects it.
func _garrison_selected(b: Building) -> bool:
	var room := b.garrison_cap() - b.garrison.size()
	for m in map.mobs:
		if m.garrison_target == b:
			room -= 1
	var sent: Array = []
	var could := false
	for m in sel_units:
		if not b.accepts(m):
			continue
		could = true
		if room <= 0:
			break
		if m.order_garrison(b):
			sent.append(m)
			room -= 1
	if sent.is_empty():
		if could:
			toast("%s is full" % b.title())
			return true
		return false
	b.flash()
	toast("%d to the %s (%d / %d)" % [sent.size(), b.title(), b.garrison.size() + sent.size(), b.garrison_cap()])
	return true


## A gate of ours shuts for everybody or opens again for our units.
func toggle_gate_lock() -> void:
	if is_instance_valid(sel_b) and sel_b.kind == "gate":
		map.set_gate_locked(sel_b, not sel_b.locked)
		toast("Gate %s" % ("locked" if sel_b.locked else "unlocked"))
		selection_changed.emit()


## The selected building lets its garrison out.
func unload_selected() -> void:
	if is_instance_valid(sel_b) and not sel_b.garrison.is_empty():
		var n := sel_b.garrison.size()
		sel_b.unload_all()
		toast("%d units out of the %s" % [n, sel_b.title()])
		selection_changed.emit()


func _move_to(c: Vector2i) -> void:
	if sel_units.is_empty():
		clear_selection()
		return
	Chatter.say_some(sel_units, "move", "soldier_move")
	var marker := MoveMarker.new()
	marker.position = Iso.to_world(Vector2(c))
	marker.z_index = 50
	map.entities.add_child(marker)
	var cells := map.spread_cells(c, sel_units.size())
	for i in sel_units.size():
		var dest := cells[mini(i, cells.size() - 1)] if not cells.is_empty() else c
		sel_units[i].order_move(dest)


# ------------------------------------------------------------------ production
func train(ukind: String) -> void:
	if sel_b == null:
		return
	var err := map.try_train(sel_b, ukind)
	if err != "":
		toast(err)


# ------------------------------------------------------------------ placement
func start_place(kind: String) -> void:
	var lock := Defs.lock_reason(map.tech, kind)
	if lock != "":
		toast(lock)
		return
	var cost: Dictionary = Defs.BUILDINGS[kind].cost
	if not map.can_afford(cost):
		toast("Not enough resources (%s)" % Defs.cost_text(cost))
		return
	cancel_place()
	placing = kind
	if kind == "wall":
		wall_pts.clear()
		placing_changed.emit()
		return
	var centre := Iso.to_cell(cam.position)
	_set_origin(centre)
	_ghost = Building.new()
	_ghost.gate_axis = place_axis
	_ghost.setup(map, kind, place_origin, true)
	map.entities.add_child(_ghost)
	_ghost.show_range(true)
	_refresh_ghost()
	placing_changed.emit()


func move_ghost(w: Vector2) -> void:
	if placing == "wall":
		_wall_tap(Iso.to_cell(w))
		return
	_set_origin(Iso.to_cell(w))
	_refresh_ghost()


func _set_origin(centre: Vector2i) -> void:
	if placing == "gate":
		var ax := place_axis                 # it turns to lie along a wall beside it
		if map.walls.has(centre + Vector2i(1, 0)) or map.walls.has(centre - Vector2i(1, 0)):
			ax = "x"
		elif map.walls.has(centre + Vector2i(0, 1)) or map.walls.has(centre - Vector2i(0, 1)):
			ax = "y"
		if ax != place_axis:
			place_axis = ax
			if _ghost:
				_ghost.set_gate_axis(ax)
		var half := Vector2i(1, 0) if ax == "x" else Vector2i(0, 1)
		place_origin = (centre - half).clamp(Vector2i.ZERO, Vector2i(map.size - 1, map.size - 1) - half * 2)
		return
	var s := int(Defs.BUILDINGS[placing].size)
	place_origin = centre - Vector2i((s - 1) / 2, (s - 1) / 2)
	place_origin = place_origin.clamp(Vector2i.ZERO, Vector2i(map.size - s, map.size - s))


## Turns the gate being placed a quarter (x or y).
func rotate_gate() -> void:
	if placing != "gate" or _ghost == null:
		return
	var half := Vector2i(1, 0) if place_axis == "x" else Vector2i(0, 1)
	var centre := place_origin + half
	place_axis = "y" if place_axis == "x" else "x"
	_ghost.set_gate_axis(place_axis)
	half = Vector2i(1, 0) if place_axis == "x" else Vector2i(0, 1)
	place_origin = (centre - half).clamp(Vector2i.ZERO, Vector2i(map.size - 1, map.size - 1) - half * 2)
	_refresh_ghost()
	placing_changed.emit()


func _refresh_ghost() -> void:
	var s := int(Defs.BUILDINGS[placing].size)
	_ghost.origin = place_origin
	_ghost.tp = _ghost._centre() if placing == "gate" else Vector2(place_origin) + Vector2.ONE * ((s - 1) * 0.5)
	_ghost.position = Iso.to_world(_ghost.tp)
	place_ok = map.can_place(placing, place_origin, place_axis)
	_ghost.modulate = Color(0.55, 1.0, 0.55, 0.75) if place_ok else Color(1.0, 0.4, 0.4, 0.75)


func cancel_place() -> void:
	_clear_wall_ghosts()
	wall_pts.clear()
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if placing != "":
		placing = ""
		placing_changed.emit()


func confirm_place() -> void:
	if placing == "":
		return
	if placing == "wall":
		_confirm_wall()
		return
	var kind := placing
	var cost: Dictionary = Defs.BUILDINGS[kind].cost
	if not place_ok:
		toast("Can't build there")
		return
	if not map.can_afford(cost):
		toast("Not enough resources (%s)" % Defs.cost_text(cost))
		return
	var builders := _builders_for(Vector2(place_origin))
	if builders.is_empty():
		toast("You need a villager to build")
		return
	map.pay(cost)
	var origin := place_origin
	var axis := place_axis
	cancel_place()
	if kind == "gate":                  # it replaces the wall pieces on its cells
		for i in 3:
			var w: Building = map.walls.get(origin + (Vector2i(i, 0) if axis == "x" else Vector2i(0, i)))
			if w and w.kind == "wall" and w.team == 0:
				map.on_building_destroyed(w, true)
	var b := map.place_building(kind, origin, false, axis)
	for v in builders:
		v.order_build(b)
	Chatter.say_some(builders, "build")
	release(builders)


func _builders_for(p: Vector2) -> Array[Villager]:
	var out: Array[Villager] = []
	for m in sel_units:
		if m is Villager:
			out.append(m)
	if not out.is_empty():
		return out
	var best: Villager = null
	var best_d := INF
	var best_idle := false
	for m in map.mobs:
		if m is Villager:
			var idle: bool = m.is_idle()
			var d: float = m.tp.distance_to(p)
			if (idle and not best_idle) or (idle == best_idle and d < best_d):
				best = m
				best_d = d
				best_idle = idle
	if best:
		out.append(best)
	return out


# ------------------------------------------------------------------ walls: tap the corners
func place_text() -> String:
	var d: Dictionary = Defs.BUILDINGS[placing]
	if placing == "gate":
		return "Place Gate (%s). It turns to lie along a wall; your units pass, enemies do not. %s" % [Defs.cost_text(d.cost), "Use Turn to rotate it." if place_ok else "Blocked here, tap another spot."]
	if placing != "wall":
		return "Place %s (%s). %s" % [d.name, Defs.cost_text(d.cost), "Tap the map to move it." if place_ok else "Blocked here, tap another spot."]
	if wall_pts.is_empty():
		return "Stone Wall: tap where the wall should start."
	if wall_cells.size() <= 1:
		return "Stone Wall: tap the next point. Walls run straight or diagonal; tap again to turn."
	var n := _wall_valid().size()
	return "Stone Wall: %d pieces, %d stone. Tap to add a turn, tap the last point to undo. Place to build." % [n, n * int(d.cost.stone)]


## Each tap adds a point; the wall runs from the last point in the nearest of 8 directions.
func _wall_tap(c: Vector2i) -> void:
	c = c.clamp(Vector2i.ZERO, Vector2i(map.size - 1, map.size - 1))
	if not wall_pts.is_empty() and c == wall_pts.back():
		wall_pts.pop_back()
	elif wall_pts.is_empty():
		wall_pts.append(c)
	else:
		var e := _snap(wall_pts.back(), c)
		if e != wall_pts.back():
			wall_pts.append(e)
	_wall_rebuild()


@warning_ignore("integer_division")
func _snap(a: Vector2i, c: Vector2i) -> Vector2i:
	var d := c - a
	var ax := absi(d.x)
	var ay := absi(d.y)
	var step: Vector2i
	var n: int
	if ax >= 2 * ay:
		step = Vector2i(signi(d.x), 0)
		n = ax
	elif ay >= 2 * ax:
		step = Vector2i(0, signi(d.y))
		n = ay
	else:
		step = Vector2i(signi(d.x), signi(d.y))
		n = (ax + ay + 1) / 2
	n = mini(n, 60)
	while n > 0 and not map.in_bounds(a + step * n):
		n -= 1
	return a + step * n


func _wall_rebuild() -> void:
	_clear_wall_ghosts()
	for i in wall_pts.size():
		if i == 0:
			wall_cells.append(wall_pts[0])
			continue
		var a := wall_pts[i - 1]
		var d := wall_pts[i] - a
		var step := Vector2i(signi(d.x), signi(d.y))
		for k in range(1, maxi(absi(d.x), absi(d.y)) + 1):
			wall_cells.append(a + step * k)
	var planned := {}
	for cell in wall_cells:
		planned[cell] = true
	for cell in wall_cells:
		if map.walls.has(cell):
			continue          # the piece we are continuing from
		var g := Building.new()
		g.setup(map, "wall", cell, true)
		g.set_piece(map.wall_piece(cell, planned))
		g.position = Iso.to_world(Vector2(cell))
		g.modulate = Color(0.55, 1.0, 0.55, 0.75) if map.can_place("wall", cell) else Color(1.0, 0.4, 0.4, 0.75)
		map.entities.add_child(g)
		_wall_ghosts.append(g)
	place_ok = not _wall_valid().is_empty()


func _wall_valid() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in wall_cells:
		if map.can_place("wall", cell):
			out.append(cell)
	return out


func _clear_wall_ghosts() -> void:
	for g in _wall_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_wall_ghosts.clear()
	wall_cells.clear()


## The Cancel button: first clears a planned wall, then leaves wall mode.
func cancel_pressed() -> void:
	if placing == "wall" and (not wall_cells.is_empty() or wall_pts.size() > 1):
		wall_pts.clear()
		_clear_wall_ghosts()
		placing_changed.emit()
	else:
		cancel_place()


func _confirm_wall() -> void:
	var cells := _wall_valid()
	if cells.is_empty():
		toast("Tap where the wall starts and where it turns first")
		return
	var each := int(Defs.BUILDINGS.wall.cost.stone)
	var n := mini(cells.size(), int(map.stock.stone) / each)
	if n == 0:
		toast("Not enough stone (%d each)" % each)
		return
	var builders := _builders_for(Vector2(cells[0]))
	if builders.is_empty():
		toast("You need a villager to build")
		return
	var total := cells.size()
	cells.resize(n)
	map.pay({"stone": n * each})
	var sites: Array[Building] = []
	for c in cells:
		sites.append(map.place_building("wall", c, false))
	# each builder takes a stretch of the wall and works along it
	var per := ceili(float(n) / builders.size())
	for i in builders.size():
		var chunk: Array[Building] = sites.slice(i * per, mini(n, (i + 1) * per))
		if chunk.is_empty():
			continue
		builders[i].order_build(chunk[0])
		builders[i].build_queue = chunk.slice(1)
	Chatter.say_some(builders, "build")
	release(builders)
	# stay in wall mode so the next stretch can continue from the last point
	var last: Vector2i = wall_pts.back()
	_clear_wall_ghosts()
	wall_pts = [last]
	placing_changed.emit()
	if n < total:
		toast("Only enough stone for %d pieces" % n)


## The Repair button: the nearest villager goes and repairs, then returns to what they were doing.
func repair_selected() -> void:
	var b := sel_b
	if b == null or not b.alive or b.hp >= b.max_hp - 0.5:
		return
	var best: Villager = null
	var best_d := INF
	for m in map.mobs:
		if m is Villager and m.alive:
			var d: float = m.tp.distance_to(b.tp)
			if d < best_d:
				best_d = d
				best = m
	if best == null:
		toast("No villager to send")
		return
	best.order_repair(b, true)
	Chatter.say(best, "repair")
	toast("A villager is on the way to repair the %s" % b.title())


func research(id: int) -> void:
	if sel_b == null:
		return
	var err := map.try_research(sel_b, id)
	if err != "":
		toast(err)
	else:
		toast("Researching %s" % Rules.techs[id].name)
