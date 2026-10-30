class_name Mob
extends Unit
## Anything that walks and can be hurt: villagers, soldiers (both sides) and wild animals.
## Teams: 0 = player, 1 = raiders, 2 = wild animals.

var map: GameMap
var team := 0
var kind := ""
var dmg_mult := 1.0         # raiders on easier modes hit softer
var def: Dictionary = {}
var alive := true
var hp := 1.0
var max_hp := 1.0
var speed := 1.8
var pre := ""                       # animation name prefix, e.g. "vm_" or "militia_blue_"
var path: Array[Vector2i] = []
var goal := Vector2i(-1, -1)        # where the current path is headed (for re-routing)
var target: Object = null           # what we are attacking
var cd := 0.0                       # attack cooldown left
var selected := false
var bar_y := 56.0
var naval := false                  # sails on deep water (ships) instead of walking
var wild := false                   # wild animals: keep off water, shallows and beaches

var _hitting := false
var _atk_t := 0.0
var _hit_done := false
var _repath := 0.0
var _ring: Deco
var _bar: Deco
var _corpse_t := 0.0
var garrisoned_in: Building = null      # inside this building: hidden, not on the map's list, safe
var garrison_target: Building = null    # walking to this building to go in
var _g_t := 0.0


func init_mob(m: GameMap, k: String, d: Dictionary, t: int) -> void:
	map = m
	kind = k
	def = d
	team = t
	max_hp = float(d.hp)
	hp = max_hp
	speed = float(d.speed)


func cell() -> Vector2i:
	return Vector2i(roundi(tp.x), roundi(tp.y))


func stand() -> void:
	play(anim("stand"))


## Animation key for a named action (stand, walk, attack, die); soldiers name theirs after their unit id.
func anim(action: String) -> String:
	return pre + action


## Class dictionaries for the damage rule (see Combat): what this unit hits with and what protects it.
func atk_dict() -> Dictionary:
	return {Combat.MELEE: float(def.atk), Combat.PIERCE: 0.0}


func armor() -> Dictionary:
	return {Combat.MELEE: 0.0, Combat.PIERCE: 0.0}


## Whether towers and soldiers should shoot at it (a deer is only meat).
func is_threat() -> bool:
	return true


## Seconds between two blows.
func reload() -> float:
	return float(def.cd)


# ------------------------------------------------------------------ garrison
## Sends the unit to a building of its team to go inside (false when it cannot).
func order_garrison(b: Building) -> bool:
	if not b.can_garrison(self):
		return false
	target = null
	_hitting = false
	path.clear()
	garrison_target = b
	if go_adjacent(b.rect()):
		return true
	garrison_target = null
	return false


## Walks to the building and goes in. A subclass calls it first in its tick with its walking animation; true while the unit is busy with it.
func garrison_tick(dt: float, walk_anim: String) -> bool:
	if garrison_target == null:
		return false
	var b := garrison_target
	if not is_instance_valid(b) or not b.alive or not b.done or not b.can_garrison(self):
		garrison_target = null
		return false
	if map.dist_to(b, tp) <= 1.3:
		garrison_target = null
		b.garrison_add(self)
		return true
	if path.is_empty():
		_g_t -= dt
		if _g_t <= 0.0:
			_g_t = 1.0
			if not go_adjacent(b.rect()):
				garrison_target = null
				return false
	follow(dt, walk_anim)
	return true


## The building let the unit out.
func on_unloaded() -> void:
	path.clear()
	stand()


# ------------------------------------------------------------------ movement
func go_to(c: Vector2i) -> bool:
	return _take_path(map.find_path(tp, c, naval, wild, team), c)


func go_adjacent(rect: Rect2i) -> bool:
	var p := map.adjacent_path(tp, rect, team)
	return _take_path(p, p[p.size() - 1] if not p.is_empty() else Vector2i(-1, -1))


func _take_path(p: Array[Vector2i], dest: Vector2i) -> bool:
	if p.is_empty():
		path.clear()
		return false
	path = p
	goal = dest
	# the first cell is the one we stand in; skip it when the next one is closer to us
	if path.size() > 1 and tp.distance_to(Vector2(path[1])) < Vector2(path[0]).distance_to(Vector2(path[1])):
		path.remove_at(0)
	return true


## Walks along `path` for this frame, playing `walk_anim`. When the path becomes empty we have arrived.
func follow(dt: float, walk_anim: String) -> void:
	if path.is_empty():
		return
	var nxt := path[0]
	if map.blocked(nxt, naval, wild, team):
		# something was built on the route: find another way to the same goal
		if not go_to(goal) or path.is_empty():
			path.clear()
			return
		nxt = path[0]
	var d := Vector2(nxt) - tp
	var dist := d.length()
	var step := speed * speed_mult() * dt
	play(walk_anim)
	face_towards(d.x, d.y)
	if dist <= step:
		place(Vector2(nxt))
		path.remove_at(0)
	else:
		place(tp + d / dist * step)


# ------------------------------------------------------------------ combat
func valid(t) -> bool:         # untyped: a target that was freed since (a dead unit's corpse) must not crash the check
	return is_instance_valid(t) and t.alive


func atk_range() -> float:
	return float(def.get("range", 0.9))


## Fights `target` for this frame. Returns false when there is nothing (left) to fight.
func combat(dt: float, chase_anim: String) -> bool:
	if not valid(target):
		target = null
		return false
	cd -= dt
	if _hitting:
		_run_attack(dt)
		return true
	var d := map.dist_to(target, tp)
	if d <= atk_range():
		path.clear()
		var tt := map.nearest_point(target, tp)
		face_towards(tt.x - tp.x, tt.y - tp.y)
		if cd <= 0.0:
			_start_attack()
		else:
			stand()
		return true
	_repath -= dt
	if path.is_empty() or _repath <= 0.0:
		_repath = 0.6
		var ok := false
		if naval:
			# a ship cannot go to its target: it moves to open water within weapon reach of it
			var fc := map.firing_cell(tp, map.nearest_point(target, tp), atk_range())
			ok = fc != Vector2i(-1, -1) and (cell() == fc or go_to(fc))
		elif target is Building:
			ok = go_adjacent(target.rect())
		else:
			ok = go_to(Vector2i(roundi(target.tp.x), roundi(target.tp.y)))
		if not ok:
			target = null
			var blk: Building = map.nearest_blocker(tp, team) if self is Soldier and not naval else null
			if blk:                 # no way through: break the wall or gate that is in the way
				target = blk
			return false
	follow(dt, chase_anim)
	return true


func _start_attack() -> void:
	_hitting = true
	_hit_done = false
	_atk_t = 0.0
	play(anim("attack"), false, true)


func _run_attack(dt: float) -> void:
	_atk_t += dt
	var total := anim_total()
	if not _hit_done and _atk_t >= total * 0.55:
		_hit_done = true
		_deliver()
	if _atk_t >= total:
		_hitting = false
		cd = maxf(0.05, reload() - total)
		stand()


func _deliver() -> void:
	if not valid(target):
		return
	var dmg := Combat.damage(atk_dict(), target.armor()) * dmg_mult
	if atk_range() > 2.0:
		map.fire(tp, target, dmg, self, float(def.get("blast", 0.0)), atk_dict())
	elif map.dist_to(target, tp) <= atk_range() + 0.7:
		target.take_damage(dmg, self)
		Sfx.at("wall_hit" if target is Building else hit_effect(), position)


func take_damage(amount: float, attacker: Object = null) -> void:
	if not alive:
		return
	hp -= amount
	if team == 0 and is_instance_valid(attacker) and attacker.get("team") != 0:
		map.report_attack(tp)
	if hp <= 0.0:
		die()
		return
	_show_bar()
	on_hurt(attacker)


## Hooks for subclasses: which sound a blow or a death makes.
func hit_effect() -> String:
	return "sword"


func death_effect() -> String:
	return "death_m"


## Hook for subclasses: faster or slower than the base speed.
func speed_mult() -> float:
	return 1.0


## Hook for subclasses: react to being hit.
func on_hurt(_attacker: Object) -> void:
	pass


func die() -> void:
	alive = false
	path.clear()
	target = null
	_hitting = false
	set_selected(false)
	Sfx.at(death_effect(), position)
	map.on_mob_died(self)
	play(anim("die"), false, true)


func set_selected(v: bool) -> void:
	selected = v
	if v and _ring == null:
		_ring = Deco.make(Deco.Mode.ELLIPSE, 17.0, 8.5, Color(0.4, 1, 0.4) if team == 0 else Color(1, 0.4, 0.3))
		_ring.show_behind_parent = true
		add_child(_ring)
	if _ring:
		_ring.visible = v
	_show_bar()


func _show_bar() -> void:
	var show := alive and (selected or hp < max_hp - 0.01)
	if show and _bar == null:
		_bar = Deco.make(Deco.Mode.BAR, 14.0, 3.0, Color.GREEN)
		_bar.position = Vector2(0, -bar_y)
		add_child(_bar)
	if _bar:
		_bar.visible = show
		_bar.set_frac(hp / max_hp)


## Corpses just play out their death animation, linger, then fade away.
func tick_corpse(dt: float) -> bool:
	advance(dt)
	_corpse_t += dt
	if _corpse_t > 7.0:
		modulate.a = maxf(0.0, 1.0 - (_corpse_t - 7.0) / 2.0)
	return _corpse_t < 9.0
