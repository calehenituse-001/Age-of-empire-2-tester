class_name Building
extends Sprite2D
## A player building: under construction until builders have put in `work_needed` seconds, then it
## produces units, stores resources, shoots arrows (towers) or grows food (farms).

var kind := ""
var def: Dictionary = {}
var map: GameMap
var origin := Vector2i.ZERO
var bsize := 1
var tp := Vector2.ZERO
var team := 0
var alive := true
var hp := 1.0
var max_hp := 1.0
var done := false
var work := 0.0
var work_needed := 1.0
var queue: Array[String] = []
var qt := 0.0
var food := 0.0
var farmer: Object = null
var selected := false

var _cd := 0.0
var _workers_now := 0
var _workers_last := 0
var _ring: Deco
var _bar: Deco
var _site: Polygon2D
var _prog: Deco
var _range: Deco
var _flash: Tween
var _fire: Unit
var _decal: Sprite2D        # the Town Center's ground layer (garden), lives in the map's ground node
var _fire_name := ""
var piece := 2              # walls: which of the five wall pieces to show
var level := 1              # towers: 2 once upgraded to a guard tower
var res_tech := -1          # the technology being researched here (-1 none)
var res_t := 0.0
var range_t := 0.0
var _hidden := false         # construction: nothing risen yet
var _see := false            # a unit of ours stands behind: draw see-through
var _alpha := 1.0
var _say_t := -10.0
var _shots: Array = []      # arrows of a volley still to be loosed: {target, delay}
var _found: Sprite2D
var gate_axis := "x"           # gates: the direction the 3 cells run (set before setup)
var locked := false         # gates: shut for everybody
var gate_open := false      # gates: a unit of the team stands close
var _gate_t := 0.0
var relics: Array[Relic] = []     # Monastery: the relics inside, each pays gold
var garrison: Array[Mob] = []      # the units inside (hidden, off the map's mob list)


func setup(m: GameMap, k: String, o: Vector2i, finished: bool) -> void:
	map = m
	kind = k
	set_process(false)
	def = Defs.BUILDINGS[k]
	origin = o
	bsize = int(def.size)
	tp = _centre()
	position = Iso.to_world(tp)
	max_hp = float(map.tech.stats(map.tech.current(int(def.uid))).hp) if def.has("uid") else float(def.hp)
	work_needed = float(def.time)
	food = float(def.get("food", 0))
	range_t = float(stats().range) if def.get("shoots", false) else 0.0
	if k != "farm":
		texture = Assets.tex(_img().file)
		centered = false
	if finished:
		_finish(false)
	else:
		hp = max_hp * 0.1
		_make_site()
		_make_foundation()
		_make_progress()
		_update_visual()


func rect() -> Rect2i:
	if kind == "gate":
		return Rect2i(origin, Vector2i(3, 1) if gate_axis == "x" else Vector2i(1, 3))
	return Rect2i(origin, Vector2i(bsize, bsize))


## The centre of the footprint in tile coordinates.
func _centre() -> Vector2:
	var r := rect()
	return Vector2(r.position) + Vector2(r.size - Vector2i.ONE) * 0.5


func is_dropoff(res_kind: String) -> bool:
	return done and def.has("drop") and res_kind in def.drop


## Builders call this every frame. Extra hands help with diminishing returns: n builders do n^0.7 builders' work.
func add_work(dt: float) -> void:
	if done:
		return
	_workers_now += 1
	work += dt * pow(float(maxi(_workers_last, 1)), -0.3)
	hp = minf(max_hp, hp + max_hp * 0.9 * dt / work_needed)
	if work >= work_needed:
		_finish(true)
	else:
		_update_visual()


func _finish(announce: bool) -> void:
	done = true
	work = work_needed
	hp = max_hp
	if _site:
		_site.queue_free()
		_site = null
	if _found:
		_found.queue_free()
		_found = null
	if _prog:
		_prog.queue_free()
		_prog = null
	_update_visual()
	if def.has("uid"):
		map.tech.building_done(int(def.uid))
	map.recalc_pop()
	if announce:
		Sfx.play("done")
		if kind == "tc":
			map.add_tc_decal(self)
		map.building_finished.emit(self)


func _make_site() -> void:
	if kind != "farm":
		return
	_site = Polygon2D.new()
	var w := bsize * Iso.HW
	var h := bsize * Iso.HH
	_site.polygon = PackedVector2Array([Vector2(0, -h), Vector2(w, 0), Vector2(0, h), Vector2(-w, 0)])
	_site.color = Color(0.45, 0.32, 0.18, 0.55)
	_site.show_behind_parent = true
	add_child(_site)


## The original's construction site: stakes, planks and stones sized to the footprint.
func _make_foundation() -> void:
	if kind == "farm" or kind == "gate":
		return
	_found = Sprite2D.new()
	_found.centered = false
	_found.show_behind_parent = true
	_found.texture = Assets.tex(_site_pics().file)
	_found.region_enabled = true
	add_child(_found)


func _site_pics() -> Dictionary:
	return Assets.site(int(def.get("uid", -1)), bsize)


func _make_progress() -> void:
	_prog = Deco.make(Deco.Mode.BAR, 17.0 if kind == "wall" else 34.0, 5.0, Color(0.95, 0.78, 0.2))
	_prog.fixed = true
	_prog.position = Vector2(0, -_top())
	add_child(_prog)


func _top() -> float:
	return 90.0 if kind == "farm" else float(_img().hy) + 6.0


## The picture to show right now: file plus the rectangle and hotspot inside it.
func _img() -> Dictionary:
	if kind == "wall":
		var w: Dictionary = Assets.man.walls
		var it: Dictionary = w.items[piece]
		return {"file": w.file, "x": it.x, "y": it.y, "w": it.w, "h": it.h, "hx": it.hx, "hy": it.hy}
	var look := look_key()
	var b: Dictionary = Assets.man.buildings[look if look != "" else kind]
	return {"file": b.file, "x": 0, "y": 0, "w": b.w, "h": b.h, "hx": b.hx, "hy": b.hy}


## The picture from the original data for this building at the player's age ("" when there is none).
func look_key() -> String:
	if kind == "gate":
		return "bld_%d" % (487 if gate_axis == "y" else 490)          # the picture runs along the "/" (y) or "\\" (x) diagonal
	if not def.has("uid") or kind in ["wall", "farm"]:
		return ""
	return Assets.look_key(map.tech.current(int(def.uid)), map.style)


## The age changed: take the new look.
func refresh_look() -> void:
	if def.has("uid"):
		var ratio := hp / max_hp
		max_hp = float(stats().hp)
		hp = max_hp * ratio
		if def.get("shoots", false):
			range_t = float(stats().range)
			if _range:
				_range.queue_free()
				_range = null
			show_range(selected)
	if kind == "farm":
		return
	texture = Assets.tex(_img().file)
	if _bar:
		_bar.position = Vector2(0, -_top())
	_update_visual()


func title() -> String:
	if def.has("levels"):
		return String(lvl().name)
	return Rules.name_of(map.tech.current(int(def.uid))) if def.has("uid") else String(def.name)


func attach_decal(d: Sprite2D) -> void:
	_decal = d


func remove_decal() -> void:
	if is_instance_valid(_decal):
		_decal.queue_free()
	_decal = null


## Everything this building has cost so far: the build price, upgrades up to its level, one being made, and queued units.
func refund_cost() -> Dictionary:
	var total := {}
	var add := func(c: Dictionary) -> void:
		for r: String in c:
			total[r] = int(total.get(r, 0)) + int(c[r])
	add.call(def.cost)
	if res_tech >= 0:
		add.call(Defs.name_cost(map.tech.cost_of(res_tech)))
	for u: String in queue:
		add.call(map.unit_info(u).cost)
	return total


# ------------------------------------------------------------------ garrison
const GARRISON := false         # units hiding in buildings was taken out at the user's request; the code stays but nothing can go in


## How many units fit in (the data's garrison value: Town Center 15, Castle 20, towers 5, military buildings 10), 0 while GARRISON is off.
func garrison_cap() -> int:
	if not GARRISON or not def.has("uid") or kind in ["wall", "farm", "gate"]:
		return 0
	return int(Rules.units[int(def.uid)].garrison)


## Soldiers go into any building that has room (not rams and ships). Villagers never garrison.
func accepts(m: Mob) -> bool:
	if not done or not alive or m.team != team or garrison_cap() <= 0 or m.naval or not m.alive:
		return false
	return m is Soldier and not m.siege


## Allowed in and there is room.
func can_garrison(m: Mob) -> bool:
	return garrison.size() < garrison_cap() and accepts(m)


func garrison_add(m: Mob) -> bool:
	if not can_garrison(m):
		return false
	garrison.append(m)
	m.garrisoned_in = self
	m.garrison_target = null
	m.target = null
	m.path.clear()
	m.set_selected(false)
	m.visible = false
	map.mobs.erase(m)
	map.recalc_pop()
	return true


## The building is gone (or emptied): its relics lie on the ground around it again.
func drop_relics() -> void:
	if relics.is_empty():
		return
	var cells := map.spread_cells(map.free_cell_near(Vector2i(origin) + Vector2i(bsize, bsize / 2), 6), relics.size())
	var i := 0
	for r in relics.duplicate():
		r.drop(Vector2(cells[mini(i, cells.size() - 1)]) if not cells.is_empty() else tp)
		i += 1
	relics.clear()


## One unit steps out beside the building (`at` a free cell near it, from unload_all).
func unload(m: Mob, at := Vector2i(-1, -1)) -> void:
	garrison.erase(m)
	m.garrisoned_in = null
	var c := at if at.x >= 0 else map.free_cell_near(Vector2i(origin) + Vector2i(bsize, bsize / 2), 6)
	m.place(Vector2(c))
	m.visible = true
	if not map.mobs.has(m):
		map.mobs.append(m)
	m.on_unloaded()
	map.recalc_pop()


func unload_all() -> void:
	if garrison.is_empty():
		return
	var cells := map.spread_cells(map.free_cell_near(Vector2i(origin) + Vector2i(bsize, bsize / 2), 6), garrison.size())
	var i := 0
	for m in garrison.duplicate():
		unload(m, cells[mini(i, cells.size() - 1)] if not cells.is_empty() else Vector2i(-1, -1))
		i += 1


## One arrow more per soldier inside that shoots (infantry, archers, cavalry archers, hand cannoneers).
func garrison_arrows() -> int:
	var n := 0
	for m in garrison:
		if m is Soldier and m.shoots_from_garrison():
			n += 1
	return n


## Units inside heal (2 hit points per game second).
func _garrison_tick(dt: float) -> void:
	for m in garrison:
		if m.hp < m.max_hp:
			m.hp = minf(m.max_hp, m.hp + 2.0 * Rules.GAME_SPEED * dt)


## What this building houses (houses grow with their level).
func pop_value() -> int:
	return int(def.get("pop", 0))


## What this building can train now: villagers at the Town Center, soldiers (unit ids as text) elsewhere.
func train_list() -> Array:
	if not def.has("train"):
		return []
	if kind == "tc":
		return ["villager"]
	var out: Array = []
	for id: int in map.tech.train_list(int(def.uid)):
		if id in Defs.NO_TRAIN or (kind == "dock" and not id in Defs.NAVAL):
			continue
		out.append(str(id))
	return out


## The Town Center's look for the age (its name and hit points); other buildings have no levels.
func lvl() -> Dictionary:
	return def.levels[level - 1]


## Walls pick their piece from the neighbours: a run along x or y, or a post at corners and ends.
func refresh_wall() -> void:
	if kind == "wall":
		set_piece(map.wall_piece(origin))


## Which way a gate runs (after turning it in the placement).
func set_gate_axis(a: String) -> void:
	gate_axis = a
	tp = _centre()
	position = Iso.to_world(tp)
	texture = Assets.tex(_img().file)
	_update_visual()


## Open when a unit of the team is close and the gate is not locked: it is drawn half see-through then.
func refresh_gate() -> void:
	var want := false
	if done and not locked:
		for m in map.mobs:
			if m.team == team and m.alive and m.tp.distance_to(tp) < 2.8:
				want = true
				break
	if want != gate_open:
		gate_open = want
		_apply_alpha()


func _gate_tick(dt: float) -> void:
	if kind != "gate" or not done:
		return
	_gate_t -= dt
	if _gate_t <= 0.0:
		_gate_t = 0.25
		refresh_gate()


## Buildings fade while one of our units stands behind them, so that unit can be tapped.
func set_see_through(v: bool) -> void:
	if v != _see:
		_see = v
		set_process(true)


func _process(delta: float) -> void:
	var target := 0.4 if _see else 1.0
	_alpha = move_toward(_alpha, target, delta * 5.0)
	_apply_alpha()
	if is_equal_approx(_alpha, target):
		set_process(false)


func _apply_alpha() -> void:
	self_modulate.a = 0.0 if _hidden else _alpha * (0.5 if gate_open else 1.0)


func set_piece(p: int) -> void:
	if p != piece:
		piece = p
		_update_visual()


func _update_visual() -> void:
	var p := work / work_needed
	if _prog:
		_prog.set_frac(p)
		_prog.visible = kind != "wall" or work > 0.01 or selected   # a long wall would be all bars
	if kind == "farm":
		modulate.a = 1.0 if done else 0.45 + 0.4 * p
		queue_redraw()
		return
	var b := _img()
	if done:
		region_enabled = kind == "wall"
		region_rect = Rect2(b.x, b.y, b.w, b.h)
		offset = -Vector2(b.hx, b.hy)
		_hidden = false
		_apply_alpha()
		return
	# stage 1 and 2 show the foundation; the finished building then rises out of it
	if _found:
		var items: Array = _site_pics().items
		var it: Dictionary = items[0 if p < 0.34 else (1 if p < 0.67 else 2)]
		_found.region_rect = Rect2(it.x, it.y, it.w, it.h)
		_found.offset = -Vector2(it.hx, it.hy)
	var q := clampf((p - 0.34) / 0.66, 0.0, 1.0)
	var h := float(b.h)
	var shown := maxf(h * q, 2.0)
	_hidden = h * q < 2.0
	_apply_alpha()
	region_enabled = true
	region_rect = Rect2(b.x, b.y + h - shown, float(b.w), shown)
	offset = Vector2(-float(b.hx), -float(b.hy) + h - shown)


@warning_ignore("integer_division")
func _draw() -> void:
	if kind != "farm":
		return
	var t: Dictionary = Assets.man.terrain["farm_grown" if food > 0.0 else "farm_fresh"]
	var tx: Texture2D = Assets.tex(t.file)
	var tw := float(t.tw)
	var th := float(t.th)
	for j in bsize:
		for i in bsize:
			var frame := i + j * 3
			var src := Rect2(float(t.pad) + (frame % 3) * float(t.cw), float(t.pad) + (frame / 3) * float(t.ch), tw, th)
			var c := Iso.to_world(Vector2(i, j) - Vector2.ONE * ((bsize - 1) * 0.5))
			draw_texture_rect_region(tx, Rect2(c - Vector2(tw, th) * 0.5, Vector2(tw, th)), src)


func tick(dt: float) -> void:
	_workers_last = _workers_now
	_workers_now = 0
	if _fire:
		_fire.advance(dt)
	if not alive or not done:
		return
	if not queue.is_empty():
		var u := map.unit_info(queue[0])
		qt += dt
		if qt >= float(u.time):
			qt = 0.0
			map.spawn_unit(queue.pop_front(), self)
	if res_tech >= 0:
		_tick_research(dt)
	_garrison_tick(dt)
	_gate_tick(dt)
	if def.get("shoots", false):
		_tick_tower(dt)


## Research here: one technology at a time, with a bar over the building.
func start_research(id: int) -> void:
	res_tech = id
	res_t = 0.0
	if _prog == null:
		_prog = Deco.make(Deco.Mode.BAR, 34.0, 5.0, Color(0.45, 0.7, 1.0))
		_prog.fixed = true
		_prog.position = Vector2(0, -_top() - 10.0)
		add_child(_prog)
	_prog.set_frac(0.0)


func research_time() -> float:
	return map.tech.time_of(res_tech) / Rules.GAME_SPEED


func _tick_research(dt: float) -> void:
	res_t += dt
	var need := research_time()
	if _prog:
		_prog.set_frac(res_t / need)
	if res_t >= need:
		var id := res_tech
		res_tech = -1
		res_t = 0.0
		if _prog:
			_prog.queue_free()
			_prog = null
		Sfx.play("done")
		map.finish_research(id)


## The Town Center takes the look of the player's age.
func set_age_level(n: int) -> void:
	n = clampi(n, 1, def.levels.size())
	if n == level:
		return
	level = n
	var st := lvl()
	texture = Assets.tex(_img().file)
	if _decal and st.has("decal"):
		Assets.apply_building(_decal, String(st.decal))
	if _bar:
		_bar.position = Vector2(0, -_top())
	_update_visual()
	_update_fire()
	_show_bar()


## What this building is now (a Watch Tower becomes a Guard Tower and a Keep through research) and its stats.
func stats() -> Dictionary:
	return map.tech.stats(map.tech.current(int(def.uid)))


## Armour classes for the damage rule (what protects it from blows).
func armor() -> Dictionary:
	return stats().arm if def.has("uid") else {Combat.MELEE: 0.0, Combat.PIERCE: 0.0}


func _tick_tower(dt: float) -> void:
	var st := stats()
	for i in range(_shots.size() - 1, -1, -1):
		_shots[i].delay -= dt
		if _shots[i].delay <= 0.0:
			var t: Object = _shots[i].target
			if is_instance_valid(t) and t.alive:
				map.fire(tp, t, Combat.damage(st.atk, t.armor()), self)
			_shots.remove_at(i)
	_cd -= dt
	if _cd > 0.0:
		return
	var near: Array = []
	for m in map.mobs:
		if m.team != 0 and m.alive and m.is_threat():
			var d := m.tp.distance_to(tp)
			if d < range_t:
				near.append([d, m])
	if near.is_empty():
		return
	near.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	_cd = float(st.reload) / Rules.GAME_SPEED
	var now := Time.get_ticks_msec() * 0.001
	if now - _say_t > 7.0:
		_say_t = now
		Chatter.say(self, "tower", 0.3)
	# one arrow per archer, spread over the nearest enemies; with fewer enemies than archers they double up
	for i in tower_shots():
		_shots.append({"target": near[i % near.size()][1], "delay": 0.14 * i})


func tower_shots() -> int:
	return int(Defs.TOWER_SHOTS.get(map.tech.current(int(def.uid)), 1)) + garrison_arrows()


## Fire over a damaged building, bigger the worse it is; none while healthy.
func _update_fire() -> void:
	var ratio := hp / max_hp
	var want := ""
	if done and alive and kind != "farm" and ratio < 0.66:
		var base: int = {1: 0, 2: 0, 3: 1, 4: 2}[bsize]
		var tier := mini(2, base + (1 if ratio < 0.33 else 0))
		want = ["fire_s", "fire_m", "fire_l"][tier]
	if want == _fire_name:
		return
	_fire_name = want
	if want == "":
		if _fire:
			_fire.queue_free()
			_fire = null
		return
	if _fire == null:
		_fire = Unit.new()
		_fire.position = Vector2(0, -float(_img().h) * 0.3)
		add_child(_fire)
	_fire.play(want)


func take_damage(amount: float, attacker: Object = null) -> void:
	if not alive:
		return
	map.rally_defenders(attacker, tp)
	if is_instance_valid(attacker) and attacker.get("team") != 0:
		map.report_attack(tp)
	hp -= amount
	if hp <= 0.0:
		alive = false
		set_selected(false)
		if _fire:
			_fire.queue_free()
			_fire = null
		map.on_building_destroyed(self)
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.8)
		tw.tween_callback(queue_free)
		return
	_update_fire()
	_show_bar()


func _ensure_ring() -> void:
	if _ring == null:
		_ring = Deco.make(Deco.Mode.DIAMOND, bsize * Iso.HW, bsize * Iso.HH, Color(0.4, 1, 0.4))
		add_child(_ring)
	if _flash:
		_flash.kill()
		_flash = null
	_ring.modulate.a = 1.0


func set_selected(v: bool) -> void:
	selected = v
	if v:
		_ensure_ring()
		_ring.visible = true
	elif _ring and (_flash == null or not _flash.is_valid()):
		_ring.visible = false
	show_range(v)
	_show_bar()


## Order feedback: the outline blinks for a second and goes away again.
func flash() -> void:
	_ensure_ring()
	_ring.visible = true
	_flash = create_tween()
	for i in 2:
		_flash.tween_property(_ring, "modulate:a", 0.2, 0.25)
		_flash.tween_property(_ring, "modulate:a", 1.0, 0.25)
	_flash.tween_callback(func() -> void:
		_flash = null
		if not selected:
			_ring.visible = false)


## Circle on the ground showing how far a tower shoots (while placing or selected).
func show_range(v: bool) -> void:
	if not def.get("shoots", false):
		return
	if _range == null:
		var r := range_t * sqrt(2.0)
		_range = Deco.make(Deco.Mode.ELLIPSE, r * Iso.HW, r * Iso.HH, Color(1.0, 0.85, 0.3))
		_range.fill = 0.10
		_range.show_behind_parent = true
		add_child(_range)
	_range.visible = v


func repair(dt: float) -> void:
	if not done or not alive:
		return
	hp = minf(max_hp, hp + max_hp * dt / (work_needed * 4.0))
	_update_fire()
	_show_bar()


func _show_bar() -> void:
	var show := alive and (selected or hp < max_hp - 0.01) and done
	if show and _bar == null:
		_bar = Deco.make(Deco.Mode.BAR, 17.0 if kind == "wall" else 34.0, 5.0, Color.GREEN)
		_bar.position = Vector2(0, -_top())
		add_child(_bar)
	if _bar:
		_bar.visible = show
		_bar.set_frac(hp / max_hp)
