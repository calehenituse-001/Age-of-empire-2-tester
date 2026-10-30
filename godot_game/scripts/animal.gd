class_name Animal
extends Mob
## Wolves and boars. They roam near where they spawned and attack player units that come close
## (or anyone who hurts them), unless attacks are paused.

var home := Vector2.ZERO
var wait := 0.0
var _scan := 0.0


func setup(m: GameMap, k: String) -> void:
	init_mob(m, k, Defs.ANIMALS[k], 2)
	wild = true
	pre = k + "_"
	bar_y = 40.0
	wait = randf_range(0.0, 3.0)
	_scan = randf() * 0.6
	stand()


func food() -> int:
	return int(def.get("food", 0))


## Wolves and boars are threats; a deer is only meat.
func is_threat() -> bool:
	return float(def.atk) > 0.0


## Wolves and boars have their own sprite sets; the deer's come from the data like a unit's.
func anim(action: String) -> String:
	if kind != "deer":
		return pre + action
	var a: String = {"stand": "idle", "run": "walk", "attack": "idle"}.get(action, action)
	return "u65_%s_blue" % a


func place_home(p: Vector2) -> void:
	home = p
	place(p)


func on_hurt(attacker: Object) -> void:
	if not is_threat():
		# prey runs away from whoever hurt it
		if is_instance_valid(attacker) and attacker.alive:
			var away: Vector2 = (tp - attacker.tp).normalized() * 7.0
			var c := Vector2i(roundi(tp.x + away.x), roundi(tp.y + away.y)).clamp(Vector2i.ZERO, Vector2i(map.size - 1, map.size - 1))
			if not map.blocked(c, false, true):
				go_to(c)
		return
	if is_instance_valid(attacker) and attacker.alive and attacker.team == 0 and not valid(target):
		target = attacker


func tick(dt: float) -> void:
	if map.attacks_paused and not valid(target):
		_wander(dt)
		advance(dt)
		return
	if valid(target) and tp.distance_to(home) > 22.0 and map.dist_to(target, tp) > 6.0:
		target = null
	if combat(dt, anim("run")):
		advance(dt)
		return
	_scan -= dt
	if _scan <= 0.0 and not map.attacks_paused:
		_scan = 0.6
		target = map.nearest_player_mob(tp, float(def.aggro))
	_wander(dt)
	advance(dt)


func _wander(dt: float) -> void:
	if not path.is_empty():
		follow(dt, anim("walk"))
		if path.is_empty():
			stand()
			wait = randf_range(2.0, 7.0)
		return
	wait -= dt
	if wait <= 0.0:
		for i in 4:
			var c := Vector2i(roundi(home.x) + randi_range(-6, 6), roundi(home.y) + randi_range(-6, 6))
			if map.in_bounds(c) and not map.blocked(c, false, true) and go_to(c):
				return
		wait = 2.0


func hit_effect() -> String:
	return "wolf" if kind == "wolf" else "hit"


func death_effect() -> String:
	return "wolf" if kind == "wolf" else "hit"
