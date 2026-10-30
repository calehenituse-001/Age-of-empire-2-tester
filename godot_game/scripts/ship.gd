class_name Ship
extends Mob
## A fishing ship: sails on deep water, fishes a school until its hold is full, carries the food to the nearest
## Dock and goes back. A new ship starts on the nearest fish by itself.

var uid := 13
var job := ""                # "" or "fish"
var fish: ResNode = null
var carry_n := 0
var returning := false
var _acc := 0.0
var _search := 0.0


func setup(m: GameMap, k: String, t: int) -> void:
	map = m
	kind = k
	team = t
	uid = int(k)
	naval = true
	var s := stats()
	max_hp = float(s.hp)
	hp = max_hp
	speed = float(s.speed) * Rules.GAME_SPEED
	def = {"name": s.name, "range": 0.0}
	stand()


func stats() -> Dictionary:
	return map.tech.stats(uid)


func anim(action: String) -> String:
	var a := "idle" if action == "stand" else action
	var k := "u%d_%s_blue" % [uid, a]
	return k if Assets.man.anims.has(k) else "u%d_idle_blue" % uid


func death_effect() -> String:
	return "collapse"


func on_tech_changed() -> void:
	var s := stats()
	hp += float(s.hp) - max_hp
	max_hp = float(s.hp)
	speed = float(s.speed) * Rules.GAME_SPEED


func armor() -> Dictionary:
	return stats().arm


func status_text() -> String:
	if job == "fish":
		return "carrying %d food to the dock" % carry_n if returning else "fishing"
	return "idle" if path.is_empty() else "sailing"


func order_move(c: Vector2i) -> void:
	job = ""
	fish = null
	returning = false
	var dest := c if map.is_water(c) else map.free_water_near(c, 8)
	if not go_to(dest):
		path.clear()


func order_fish(f: ResNode) -> void:
	job = "fish"
	fish = f
	returning = false
	path.clear()


func tick(dt: float) -> void:
	if job == "fish":
		_fish_ai(dt)
	elif not path.is_empty():
		follow(dt, anim("walk"))
		if path.is_empty():
			stand()
	else:
		stand()
	advance(dt)


func _fish_ai(dt: float) -> void:
	if returning:
		var dock := map.nearest_dock(tp)
		if dock == null:
			returning = false
			job = ""
			stand()
			return
		if map.dist_to(dock, tp) <= 1.9:
			map.add_resource("food", carry_n)
			carry_n = 0
			returning = false
			path.clear()
			return
		if path.is_empty():
			var p := map.adjacent_water_path(tp, dock.rect())
			if p.is_empty() or not _take_path(p, p[p.size() - 1]):
				job = ""
				stand()
				return
		follow(dt, anim("walk"))
		return
	if not valid(fish):
		_search -= dt
		if _search > 0.0:
			stand()
			return
		_search = 1.0
		fish = map.nearest_fish(tp, 45.0, true)
		if fish == null:
			if carry_n > 0:
				_begin_return()
			else:
				job = ""
			stand()
			return
	var d := tp.distance_to(Vector2(fish.cell))
	if d > 1.6:
		if path.is_empty():
			if not go_to(fish.cell):
				fish = null
				return
		follow(dt, anim("walk"))
		return
	path.clear()
	stand()
	_acc += map.fish_rate() * dt
	while _acc >= 1.0 and valid(fish):
		_acc -= 1.0
		fish.amount -= 1
		carry_n += 1
		if fish.amount <= 0:
			map.remove_fish(fish)
			fish = null
	if carry_n >= map.fish_capacity() or (fish == null and carry_n > 0):
		_begin_return()


func _begin_return() -> void:
	returning = true
	path.clear()
