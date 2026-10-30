class_name Director
extends Node
## Spawns the threats: wild animals roaming the map, and enemy raids on a fixed timer that the difficulty
## mode sets (see Defs.DIFFICULTY). Raids grow every wave, by wave number, not by how well the player does.

var map: GameMap
var wave := 0
var next_raid := 300.0
var _wild_t := 10.0

const COMPASS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]


func _ready() -> void:
	next_raid = float(diff().first)


func diff() -> Dictionary:
	return Defs.DIFFICULTY[map.difficulty]


## The difficulty was changed during the game: move the next raid accordingly.
func on_difficulty_changed() -> void:
	var d := diff()
	if wave == 0:
		next_raid = maxf(1.0, float(d.first) - map.game_time)
	else:
		next_raid = minf(next_raid, float(d.interval))


func wild_cap() -> int:
	return maxi(3, roundi(clampi(map.size * map.size / 1100, 8, 70) * float(diff().wild)))


func tick(dt: float) -> void:
	if not map.attacks_paused and map.opponent == "raids":
		next_raid -= dt
		if next_raid <= 0.0:
			raid()
			next_raid = float(diff().interval)
	_wild_t -= dt
	if _wild_t <= 0.0:
		_wild_t = 20.0
		if _wild_count() < wild_cap():
			spawn_wild_pack()


func _wild_count() -> int:
	var n := 0
	for m in map.mobs:
		if m.team == 2:
			n += 1
	return n


func populate_wild(n: int) -> void:
	for i in n:
		spawn_wild_pack()


## A pack of wolves or a pair of boars, away from the player's buildings unless `near` says where.
func spawn_wild_pack(near := Vector2i(-1, -1)) -> void:
	var c := near if near.x >= 0 else _far_cell(22.0)
	if c.x < 0:
		return
	var roll := map.rng.randf()
	var kind := "wolf" if roll < 0.4 else ("boar" if roll < 0.62 else "deer")
	var count := map.rng.randi_range(2, 4) if kind == "deer" else (map.rng.randi_range(1, 3) if kind == "wolf" else map.rng.randi_range(1, 2))
	for i in count:
		var p := map.free_cell_near(c + Vector2i(map.rng.randi_range(-2, 2), map.rng.randi_range(-2, 2)), 4, false, true)
		map.make_animal(kind, Vector2(p))


func _far_cell(min_dist: float) -> Vector2i:
	for i in 40:
		var c := Vector2i(map.rng.randi_range(2, map.size - 3), map.rng.randi_range(2, map.size - 3))
		if map.blocked(c, false, true):
			continue
		var ok := true
		for b in map.buildings:
			if Vector2(c).distance_to(b.tp) < min_dist:
				ok = false
				break
		if ok:
			return c
	return Vector2i(-1, -1)


func raid() -> void:
	wave += 1
	Sfx.play("raid")
	var anchor := map.nearest_building(Vector2(map.size / 2.0, map.size / 2.0))
	var centre := anchor.tp if anchor else Vector2(map.size / 2.0, map.size / 2.0)
	var min_d := minf(45.0, map.size * 0.35)
	var spot := Vector2i(-1, -1)
	for i in 60:
		var side := map.rng.randi_range(0, 3)
		var t := map.rng.randi_range(4, map.size - 5)
		var c := [Vector2i(t, 4), Vector2i(t, map.size - 5), Vector2i(4, t), Vector2i(map.size - 5, t)][side] as Vector2i
		if Vector2(c).distance_to(centre) >= min_d and not map.is_solid(c) and anchor \
				and not map.adjacent_path(Vector2(c), anchor.rect()).is_empty():
			spot = c
			break
	if spot.x < 0:
		spot = map.free_cell_near(Vector2i(4, 4), 6)
	var dd := diff()
	var total := mini(int(dd.base) + int(float(dd.per_wave) * wave), int(dd.max))
	for i in total:
		var kind := _pick_kind()
		var p := map.free_cell_near(spot + Vector2i(map.rng.randi_range(-3, 3), map.rng.randi_range(-3, 3)), 5)
		var m := map.make_unit(kind, 1, Vector2(p))
		m.hp *= float(dd.hp)
		m.max_hp *= float(dd.hp)
		m.dmg_mult = float(dd.atk)
	_naval_raid(dd)
	var d := Vector2(spot) - centre
	var comp := posmod(roundi(atan2((d.x - d.y) * Iso.HW, -(d.x + d.y) * Iso.HH) / (PI / 4.0)), 8)
	map.message.emit("Raid! %d enemy soldiers are coming from the %s." % [total, COMPASS[comp]])


## Every second wave once the difficulty allows it, warships come out of the large lake nearest the player's buildings.
func _naval_raid(dd: Dictionary) -> void:
	var tiers: Dictionary = dd.get("naval", {})
	var pool: Array[String] = []
	var first := 99
	for kind: String in tiers:
		first = mini(first, int(tiers[kind]))
		if wave >= int(tiers[kind]):
			pool.append(kind)
	if pool.is_empty() or (wave - first) % 2 != 0:
		return
	var spot := map.naval_spawn()
	if spot.x < 0:
		return
	var count := mini(1 + (wave - first) / 3 + 1, 6)
	for i in count:
		var c := map.free_water_near(spot + Vector2i(map.rng.randi_range(-3, 3), map.rng.randi_range(-3, 3)), 5)
		var m := map.make_unit(pool[map.rng.randi() % pool.size()], 1, Vector2(c))
		m.hp *= float(dd.hp)
		m.max_hp *= float(dd.hp)
		m.dmg_mult = float(dd.atk)
	map.message.emit("Enemy warships are sailing in from the lake!")


func _pick_kind() -> String:
	var tiers: Dictionary = diff().tiers
	var pool: Array[String] = []
	for kind: String in tiers:
		if wave >= int(tiers[kind]):
			# the basic soldier is the most common, each stronger kind adds a smaller share
			for i in (3 if kind == "74" else (1 if kind == "35" else 2)):
				pool.append(kind)
	return pool[map.rng.randi() % pool.size()]
