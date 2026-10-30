class_name Soldier
extends Mob
## Every fighting unit, by the unit id of the original data (`kind` is the id as text, e.g. "74" Militia). Stats come
## from the data: for the player's soldiers through the research state (so Blacksmith techs and unit upgrades apply
## at once), for raiders as the data has them. Player soldiers obey orders and otherwise engage hostiles that come
## close; raiders march on the nearest building and fight what they meet.

var order := "idle"     # idle | move
var uid := 0            # what this unit is now (a Militia becomes a Man-at-Arms when that is researched)
var base_uid := 0       # what it was trained as
var hp_mult := 1.0      # the difficulty's factor on a rival soldier's hit points
var siege := false      # only attacks buildings (rams)
var healer := false     # monks heal instead of fighting
var kamikaze := false   # a Demolition Ship: blows itself up against its target
var foe_mode := "attack"    # the rival's soldiers: "guard" stays at the rally point and defends the base, "attack" marches on the player
var guard_pos := Vector2.ZERO
var _heal_target: Mob = null
var _heal_t := 0.0
var _scan := 0.0
var _patrol := 0.0
var _march := 0.0
var _hurt_say := -10.0
var _colour := "blue"
var relic: Relic = null            # monk: the relic in his arms
var convert_target: Mob = null     # monk: the unit he is converting (or on his way to)
var relic_target: Relic = null     # monk: the relic he walks to
var deliver_to: Building = null    # monk: the Monastery he carries the relic to
var _conv_t := 0.0
var _conv_need := 0.0
var _recharge := 0.0               # monk: seconds until his faith is back and he can convert again
var _aura: ConvertAura = null
var _cscan := 0.0
var _chant_t := 0.0

const CONVERT_MIN := 4.0           # how long a conversion takes (game seconds): between 4 and 10, the data's values for the monk's convert task
const CONVERT_MAX := 10.0
const RECHARGE := 62.0             # a monk needs this long before the next conversion


func setup(m: GameMap, k: String, t: int) -> void:
	map = m
	kind = k
	team = t
	base_uid = int(k)
	var tech := _tech()
	uid = tech.current(base_uid) if tech else base_uid
	_colour = "blue" if t == 0 else "red"
	naval = Defs.is_ship(k)
	_load_stats()
	_scan = randf() * 0.5
	stand()


## The research state this soldier follows: the player's, or the rival's (raiders have none and keep the data's values).
func _tech() -> TechState:
	if team == 0:
		return map.tech
	return map.rival.tech if map.rival and map.rival.tech else null


## The data row this soldier follows right now.
## Soldiers inside a Town Center, Castle or tower add an arrow: infantry (class 6), archers (0), cavalry archers (36), hand cannoneers (44).
func shoots_from_garrison() -> bool:
	return int(stats()["class"]) in [0, 6, 36, 44]


func stats() -> Dictionary:
	var t := _tech()
	return t.stats(uid) if t else Combat.base_stats(uid)


func _load_stats() -> void:
	var s := stats()
	max_hp = float(s.hp)
	hp = max_hp
	speed = float(s.speed) * Rules.GAME_SPEED
	def = {"range": float(s.range), "name": s.name, "blast": float(s.blast)}
	siege = int(s["class"]) == 13 and float(s.range) <= 0.5      # rams: buildings only (a Mangonel is class 13 too, but shoots)
	healer = int(s["class"]) == 18
	kamikaze = float(s.blast) > 0.0 and float(s.range) <= 0.5 and naval


## Research changed: upgrade to the newer unit and pick up better stats.
func on_tech_changed() -> void:
	var t := _tech()
	if t == null:
		return
	var now := t.current(base_uid)
	var changed := now != uid
	uid = now
	var old_max := max_hp
	var s := stats()
	max_hp = float(s.hp) * hp_mult
	hp += max_hp - old_max
	speed = float(s.speed) * Rules.GAME_SPEED
	def.range = float(s.range)
	def.name = s.name
	def.blast = float(s.blast)
	if changed:
		stand()
	_show_bar()


func anim(action: String) -> String:
	var a := "idle" if action == "stand" else action
	var id := 286 if relic != null else uid         # a monk with a relic is a unit of his own (Monk with Relic)
	var k := "u%d_%s_%s" % [id, a, _colour]
	if not Assets.man.anims.has(k):
		k = "u%d_%s_blue" % [id, a]            # no red sheet for this unit: the blue one
	if not Assets.man.anims.has(k):
		k = "u%d_idle_blue" % id
	return k


func atk_dict() -> Dictionary:
	return stats().atk


func armor() -> Dictionary:
	return stats().arm


func reload() -> float:
	return float(stats().reload) / Rules.GAME_SPEED


func atk_range() -> float:
	return maxf(float(def.get("range", 0.0)), 1.2 if naval else 0.9)       # ships touch from the next cell over


func speed_mult() -> float:
	return 1.0


func on_hurt(attacker: Object) -> void:
	if team == 0:
		var now := Time.get_ticks_msec() * 0.001
		if now - _hurt_say > 5.0:
			_hurt_say = now
			Chatter.say(self, "soldier_hurt", 0.45)


func order_move(c: Vector2i) -> void:
	garrison_target = null
	convert_target = null
	relic_target = null
	deliver_to = null
	_end_convert()
	target = null
	_hitting = false
	order = "move"
	if naval and not map.is_water(c):
		c = map.free_water_near(c, 8)       # a ship sent inland stops at the nearest open water
	if not go_to(c):
		order = "idle"


func order_attack(t: Object) -> void:
	garrison_target = null
	if healer:                      # a monk converts what he is sent against (a building he leaves alone)
		_monk_convert_order(t)
		return
	target = t
	order = "idle"
	path.clear()


func tick(dt: float) -> void:
	if garrison_target and garrison_tick(dt, anim("walk")):
		advance(dt)
		return
	if team != 0 and map.attacks_paused:
		path.clear()
		target = null
		stand()
		advance(dt)
		return
	if team == 0:
		_player_ai(dt)
	else:
		_raider_ai(dt)
	advance(dt)


# ------------------------------------------------------------------ monks: conversion and relics
func _res(id: int) -> bool:
	var t := _tech()
	return t != null and int(t.res.get(id, 0)) >= 1


## What a monk may convert: units of the other side (not wild animals or ships); monks only with Atonement, siege only with Redemption.
func _can_convert(m: Object) -> bool:
	if not valid(m) or not m is Mob or m.team == team or m.team == 2 or m.naval or m.garrisoned_in != null:
		return false
	if m is Soldier:
		if m.healer and not _res(27):
			return false
		if m.siege and not _res(28):
			return false
		return true
	return m is Villager or m is FoeVillager


func _monk_convert_order(t: Object) -> void:
	relic_target = null
	deliver_to = null
	path.clear()
	order = "idle"
	_end_convert()
	convert_target = t if _can_convert(t) else null


func order_pickup(r: Relic) -> void:
	_end_convert()
	convert_target = null
	deliver_to = null
	target = null
	order = "idle"
	path.clear()
	if relic == null and r.on_ground():
		relic_target = r
		go_to(Vector2i(roundi(r.tp.x), roundi(r.tp.y)))


func order_deliver(b: Building) -> void:
	if relic == null:
		return
	convert_target = null
	_end_convert()
	order = "idle"
	deliver_to = b
	go_adjacent(b.rect())


func _end_convert() -> void:
	if is_instance_valid(_aura):
		_aura.queue_free()
	_aura = null
	_conv_t = 0.0
	_conv_need = 0.0


func _recharge_time() -> float:
	var t := RECHARGE / Rules.GAME_SPEED
	var tech := _tech()
	if tech != null and int(tech.res.get(35, 0)) >= 3:      # Illumination: the faith comes back half as fast again
		t /= 1.5
	return t


func status_text() -> String:
	if relic != null:
		return "carrying a relic: tap your Monastery"
	if valid(convert_target):
		return "converting %s %d%%" % [convert_target.def.get("name", "a unit"), int(100.0 * _conv_t / maxf(_conv_need, 0.01))]
	if _recharge > 0.0:
		return "recharging his faith (%d s)" % ceili(_recharge)
	return "ready"


func _monk_ai(dt: float) -> void:
	_recharge = maxf(0.0, _recharge - dt)
	if order == "move":
		follow(dt, anim("walk"))
		if path.is_empty():
			order = "idle"
			stand()
		return
	if relic != null:
		_carry_ai(dt)
		return
	if is_instance_valid(relic_target):
		_pickup_ai(dt)
		return
	if valid(convert_target) or _auto_convert(dt):
		if _convert_ai(dt):
			return
	_heal_ai(dt)


func _pickup_ai(dt: float) -> void:
	var r := relic_target
	if not r.on_ground():
		relic_target = null
		return
	if tp.distance_to(r.tp) <= 1.4:
		r.pick_up(self)
		relic = r
		relic_target = null
		path.clear()
		Sfx.at("relic_up", position)
		map.message.emit("A monk takes the relic: tap your Monastery to have it pay gold")
		Chatter.say(self, "relic")
		stand()
		return
	if path.is_empty():
		go_to(Vector2i(roundi(r.tp.x), roundi(r.tp.y)))
	follow(dt, anim("walk"))


func _carry_ai(dt: float) -> void:
	if not is_instance_valid(deliver_to) or not deliver_to.alive or not deliver_to.done:
		deliver_to = null
		stand()
		return
	if map.dist_to(deliver_to, tp) <= 1.5:
		relic.store(deliver_to)
		relic = null
		deliver_to = null
		path.clear()
		Sfx.play("done")
		map.message.emit("Relic in the Monastery: +%.1f gold per second" % (Relic.GOLD_RATE * Rules.GAME_SPEED))
		Chatter.say(self, "relic")
		stand()
		return
	if path.is_empty() and not go_adjacent(deliver_to.rect()):
		deliver_to = null
		return
	follow(dt, anim("walk"))


## Idle, with his faith back: the nearest enemy within reach gets converted.
func _auto_convert(dt: float) -> bool:
	_cscan -= dt
	if _cscan > 0.0 or _recharge > 0.0:
		return false
	_cscan = 0.6
	var best: Mob = null
	var best_d := atk_range()
	for m in map.mobs:
		if m.team != team and _can_convert(m):
			var d := m.tp.distance_to(tp)
			if d < best_d:
				best_d = d
				best = m
	convert_target = best
	return best != null


## Walks into range, chants for 4 to 10.5 seconds with the unit watched by a ring, then it is his. Out of range the chant starts over.
func _convert_ai(dt: float) -> bool:
	if not _can_convert(convert_target):
		convert_target = null
		_end_convert()
		return false
	if _recharge > 0.0:
		stand()
		return true
	var d := tp.distance_to(convert_target.tp)
	if d > atk_range() - 0.5:
		_end_convert()
		if path.is_empty():
			go_to(convert_target.cell())
		follow(dt, anim("walk"))
		return true
	path.clear()
	face_towards(convert_target.tp.x - tp.x, convert_target.tp.y - tp.y)
	play(anim("attack"))
	if _conv_need <= 0.0:
		_conv_need = randf_range(CONVERT_MIN, CONVERT_MAX) / Rules.GAME_SPEED
	_conv_t += dt
	_chant_t -= dt
	if _chant_t <= 0.0:                # the monk's chant, over and over while he works on the unit
		_chant_t = 1.9
		Sfx.at("chant", position)
	if not is_instance_valid(_aura):
		_aura = ConvertAura.new()
		convert_target.add_child(_aura)
	_aura.progress = clampf(_conv_t / _conv_need, 0.0, 1.0)
	if _conv_t >= _conv_need:
		var t := convert_target
		var name_of: String = String(t.def.get("name", "unit"))
		convert_target = null
		_end_convert()
		map.convert_mob(t, team)
		_recharge = _recharge_time()
		map.message.emit("Converted: %s" % name_of)
		Chatter.say(self, "convert")
		stand()
	return true


## A monk converted this unit: it is the other side's now, with their upgrades and the same share of its health.
func convert_to(t: int) -> void:
	var ratio := hp / maxf(max_hp, 1.0)
	team = t
	_colour = "blue" if t == 0 else "red"
	dmg_mult = 1.0
	hp_mult = 1.0
	target = null
	order = "idle"
	foe_mode = "attack"
	garrison_target = null
	path.clear()
	set_selected(false)
	if _ring:
		_ring.queue_free()
		_ring = null
	uid = _tech().current(base_uid) if _tech() else base_uid
	var s := stats()
	max_hp = float(s.hp)
	hp = max_hp * ratio
	speed = float(s.speed) * Rules.GAME_SPEED
	def.range = float(s.range)
	def.name = s.name
	stand()
	_show_bar()


func die() -> void:
	if relic != null:
		relic.drop(tp)
		relic = null
	_end_convert()
	super.die()


## A monk walks up to the nearest wounded friend and heals them, 2 hit points per game second (the data's heal task).
func _heal_ai(dt: float) -> void:
	if order == "move":
		follow(dt, anim("walk"))
		if path.is_empty():
			order = "idle"
			stand()
		return
	_scan -= dt
	if _scan <= 0.0:
		_scan = 0.5
		if not valid(_heal_target) or _heal_target.hp >= _heal_target.max_hp - 0.5:
			_heal_target = null
			var best := 12.0
			for m in map.mobs:
				if m != self and m.team == 0 and m.alive and m.hp < m.max_hp - 0.5 and m.tp.distance_to(tp) < best:
					best = m.tp.distance_to(tp)
					_heal_target = m
	if not valid(_heal_target):
		stand()
		return
	if _heal_target.tp.distance_to(tp) > minf(6.0, atk_range() - 1.0):
		if path.is_empty():
			go_to(_heal_target.cell())
		follow(dt, anim("walk"))
		return
	path.clear()
	stand()
	_heal_t += dt
	if _heal_t >= 0.5:
		_heal_target.hp = minf(_heal_target.max_hp, _heal_target.hp + 2.0 * Rules.GAME_SPEED * _heal_t)
		_heal_t = 0.0
		_heal_target._show_bar()


func _player_ai(dt: float) -> void:
	if healer:
		_monk_ai(dt)
		return
	if combat(dt, anim("walk")):
		return
	if order == "move":
		follow(dt, anim("walk"))
		if path.is_empty():
			order = "idle"
			stand()
		return
	if not path.is_empty():
		follow(dt, anim("walk"))
		return
	_scan -= dt
	if _scan <= 0.0:
		_scan = 0.5
		target = map.nearest_hostile(tp, atk_range() + 3.0 if naval else 8.0)
		if target == null and not naval:
			target = map.nearest_foe_building(tp, 4.0)       # an enemy building next to us is fair game
	stand()


## A Demolition Ship blows up against its target: everything hostile within the blast radius takes the blow (as its armour
## leaves it), buildings included, and the ship is gone.
func _deliver() -> void:
	if not kamikaze:
		super._deliver()
		return
	if not valid(target):
		return
	var centre := map.nearest_point(target, tp)
	var atk := atk_dict()
	var blast := float(def.blast)
	for m in map.mobs.duplicate():
		if m.alive and m.team != team and m.tp.distance_to(centre) <= blast:
			m.take_damage(Combat.damage(atk, m.armor()) * dmg_mult, self)
	if team != 0:
		for b in map.buildings.duplicate():
			if b.alive and map.dist_to(b, centre) <= blast:
				b.take_damage(Combat.damage(atk, b.armor()) * dmg_mult, self)
	Sfx.at("collapse", position)
	take_damage(max_hp * 10.0)


func _naval_raider_ai(dt: float) -> void:
	_scan -= dt
	if _scan <= 0.0:
		_scan = 1.0
		if not valid(target):
			target = map.naval_target(tp, atk_range(), 70.0)
	if combat(dt, anim("walk")):
		return
	stand()


## The rival's army between attacks: stands at the rally point and fights whatever of the player's comes within reach of it.
func guard(at: Vector2) -> void:
	foe_mode = "guard"
	guard_pos = at


func _guard_ai(dt: float) -> void:
	_scan -= dt
	if _scan <= 0.0:
		_scan = 0.6
		if not valid(target):
			target = map.nearest_player_mob(guard_pos, 15.0)
	if valid(target) and target.tp.distance_to(guard_pos) > 28.0:
		target = null
	if combat(dt, anim("walk")):
		return
	if tp.distance_to(guard_pos) > 5.0 and path.is_empty():
		go_to(map.free_cell_near(Vector2i(guard_pos) + Vector2i(randi_range(-3, 3), randi_range(-3, 3)), 4))      # (not all on one cell)
	if not path.is_empty():
		follow(dt, anim("walk"))
		return
	# at the post: stroll about within the sentry distance (the original's sn-sentry-distance 4), then stand again
	_patrol -= dt
	if _patrol <= 0.0:
		_patrol = randf_range(6.0, 14.0)
		go_to(map.free_cell_near(Vector2i(guard_pos) + Vector2i(randi_range(-3, 3), randi_range(-3, 3)), 3))
	else:
		stand()


func _raider_ai(dt: float) -> void:
	if naval:
		_naval_raider_ai(dt)
		return
	if foe_mode == "guard":
		_guard_ai(dt)
		return
	_scan -= dt
	var hunting_repairer: bool = valid(target) and target is Villager and target.job == "repair"
	if _scan <= 0.0 and not hunting_repairer:
		_scan = 0.5
		var near: Object = map.nearest_building(tp) if siege else map.nearest_player_thing(tp, 7.0)
		if near and (not valid(target) or target is Building):
			target = near
	if combat(dt, anim("walk")):
		return
	# nothing close: keep marching on the nearest building
	_march -= dt
	if path.is_empty() and _march <= 0.0:
		_march = 1.0
		var b := map.nearest_building(tp)
		if b:
			target = b
		elif not siege:
			var u := map.nearest_player_thing(tp, 999.0)
			if u:
				target = u
		if target == null:
			stand()
	if not path.is_empty():
		follow(dt, anim("walk"))      # (a path left from guard duty or a lost target)
	else:
		stand()
