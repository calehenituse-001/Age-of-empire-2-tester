class_name FoeBuilding
extends Building
## A building of the rival's base. It builds itself (the rival's builders are not on the map), trains what the Rival orders,
## shoots at the player's units (Town Center, towers, castle) and falls to the player's soldiers. It uses the same pictures as
## the player's buildings, recoloured red, and the data's stats without the player's research.

const TC_BY_AGE := [109, 71, 141, 142]
const TOWER_BY_AGE := [79, 79, 234, 235]        # Watch Tower, Guard Tower (Castle Age), Keep (Imperial Age)
const RED := preload("res://assets/red_team.gdshader")

static var _mat: ShaderMaterial

var age := 0
var _unattended := 0.0      # seconds since a villager last built on it (only matters when the rival has no villager left)


static func red_material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = RED
	return _mat


func setup(m: GameMap, k: String, o: Vector2i, finished: bool) -> void:
	map = m
	kind = k
	team = 1
	set_process(false)
	def = Defs.BUILDINGS[k]
	origin = o
	bsize = int(def.size)
	tp = _centre()
	position = Iso.to_world(tp)
	max_hp = float(def.hp) if k == "farm" else float(stats().hp)
	work_needed = float(def.time)
	food = float(def.get("food", 0))
	range_t = float(stats().range) if def.get("shoots", false) else 0.0
	if k != "farm":
		texture = Assets.tex(_img().file)
		centered = false
		material = red_material()
	if finished:
		_finish(false)
	else:
		hp = max_hp * 0.1
		_make_site()
		_make_foundation()
		if _found:
			_found.material = _mat
		_make_progress()
		_update_visual()


## The unit id this building is now (the Town Center changes with the rival's age).
func uid_now() -> int:
	if kind == "tc":
		return TC_BY_AGE[age]
	return TOWER_BY_AGE[age] if kind == "tower" else int(def.uid)


func stats() -> Dictionary:
	if map.rival and map.rival.tech:
		return map.rival.tech.stats(uid_now())
	return Combat.base_stats(uid_now())


func look_key() -> String:
	if kind == "gate":
		return super.look_key()
	return Assets.look_key(uid_now(), map.rival.style if map.rival else 0)


func title() -> String:
	return "Enemy " + String(def.name)


func tower_shots() -> int:
	return int(Defs.TOWER_SHOTS.get(uid_now(), 1)) + garrison_arrows()


## The rival reached a new age: a stronger and better looking Town Center.
func set_age(a: int) -> void:
	if a == age:
		return
	var ratio := hp / max_hp
	age = a
	max_hp = float(stats().hp)
	hp = max_hp * ratio
	if kind == "tc" or kind == "tower":
		range_t = float(stats().range)
		texture = Assets.tex(_img().file)
		_update_visual()


## The rival researched something: new hit points and range (keeping the damage taken).
func refresh_stats() -> void:
	if kind == "farm":
		return
	var ratio := hp / max_hp
	max_hp = float(stats().hp)
	hp = max_hp * ratio
	if def.get("shoots", false):
		range_t = float(stats().range)


## A villager builds on it this frame.
func help_build(dt: float) -> void:
	_unattended = 0.0
	add_work(dt)


func _finish(_announce: bool) -> void:
	done = true
	work = work_needed
	hp = max_hp
	for n: Node in [_found, _prog, _site]:
		if n:
			n.queue_free()
	_found = null
	_prog = null
	_site = null
	if def.has("uid") and map.rival and map.rival.tech:
		map.rival.tech.building_done(int(def.uid))       # a finished building counts for the technologies that need it
	_update_visual()


func tick(dt: float) -> void:
	if not alive:
		return
	if _fire:
		_fire.advance(dt)
	if not done:
		_workers_last = _workers_now
		_workers_now = 0
		_unattended += dt
		if _unattended > 25.0 and map.rival and map.rival.villagers.is_empty():      # with no villager left nothing would ever be built
			_workers_now = 1
			add_work(dt * 0.5)
		return
	if not queue.is_empty():
		qt += dt
		if qt >= map.rival.train_time(queue[0]):
			qt = 0.0
			map.rival.spawn(queue.pop_front(), self)
	_garrison_tick(dt)
	_gate_tick(dt)
	if res_tech >= 0:
		res_t += dt
		if res_t >= map.rival.tech.time_of(res_tech) / Rules.GAME_SPEED:
			var id := res_tech
			res_tech = -1
			res_t = 0.0
			map.rival.finish_research(id)
	if def.get("shoots", false):
		_tick_tower(dt)


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
		if m.team == 0 and m.alive and not m.naval:
			var d: float = m.tp.distance_to(tp)
			if d < range_t:
				near.append([d, m])
	if near.is_empty():
		return
	near.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	_cd = float(st.reload) / Rules.GAME_SPEED
	for i in tower_shots():
		_shots.append({"target": near[i % near.size()][1], "delay": 0.14 * i})


func take_damage(amount: float, attacker: Object = null) -> void:
	if not alive:
		return
	if is_instance_valid(attacker) and map.rival:
		map.rival.on_attacked(attacker)
	hp -= amount
	if hp <= 0.0:
		alive = false
		set_selected(false)
		if _fire:
			_fire.queue_free()
			_fire = null
		map.on_foe_destroyed(self)
		var tw := create_tween()
		tw.tween_property(self, "modulate:a", 0.0, 0.8)
		tw.tween_callback(queue_free)
		return
	_update_fire()
	_show_bar()
