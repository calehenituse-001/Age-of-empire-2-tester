class_name Rival
extends Node
## The opponent: a base on the far side of the map that plays by simple rules of its own. Its villagers are real: they fell the
## trees, mine and forage around the base and carry what they gather to its Town Center, camps and mills (the stock is only what
## they deliver); the rival builds those camps where the resources are, farms once the berries run out, houses, production
## buildings and defences, advances through the ages, trains the soldiers the data allows by age (Defs.RIVAL_ROSTER) and sends
## its army at the player in waves. Between waves the army guards the base. The player wins by destroying every building of it.

var map: GameMap
var base := Vector2i(-1, -1)        # centre of the Town Center footprint
var style := 0                      # architecture style of its buildings
var civ := 1                        # the civilization whose technologies and bonuses it has (one with its architecture style)
var tech: TechState                 # what it has researched; the stats of its units, towers and villagers follow from it
var age := 0
var stock := {"wood": 300, "food": 300, "gold": 150, "stone": 150}
var workers: int:
	get:
		return villagers.size()
var wave := 0
var wave_size := 0
var attacking := false
var researching := -1.0             # seconds left of an age research, -1 when none
var started := false
var rally := Vector2.ZERO
var enemy := Vector2.ZERO            # where the player's town is: the towers face it
var villagers: Array[FoeVillager] = []
var gathered := {"wood": 0, "food": 0, "gold": 0, "stone": 0}     # everything its villagers have delivered
var _reserve: Dictionary = {}       # the price of the technology it waits to afford: soldiers are not trained out of it
var pop_extra := 0                  # test hook: counted as extra population

const GATHER_R := 14                # a villager works resources up to this far from a drop-off
const SERVED_R := 9.0               # a resource this close to a drop-off needs no new camp
const CROWD := 3                    # gatherers per resource
const CAMP_MAX := {"lumber_camp": 5, "mining_camp": 4, "mill": 3}
const CAMP_NEED := {"wood": 10, "food": 4, "gold": 2, "stone": 2}      # resources a camp's neighbourhood must still offer
const WALL_R := 17                  # the wall ring: Chebyshev distance from the Town Center centre ("perimeter 2" of the original)
const GATE_HALF := 1                # a gate opening of 3 cells in the middle of each side

var _t := 0.0                       # rival time
var _think := 1.0
var _vill_t := 0.0
var _vill_cd := 0.0                 # a villager takes time to train
var _alarm := 0.0                   # the base was hit lately: everything defends
var _wall_cells: Array[Vector2i] = []
var _wall_started := false
var _wave_start := 0.0              # rival time when the current wave marched
var _bad: Dictionary = {}                # cells of resources a villager could not reach -> rival time to try again
var _bad_sites: Dictionary = {}          # building instance id -> rival time to try building it again
var _walkable: Dictionary = {}             # wall cell -> can a villager get to it
var _camp_cd: Dictionary = {}           # kind -> rival time before the next search for a camp site
var _tower_t := 0.0                 # the original's t-tower timer: towers wait for it while a wall is being built


func d() -> Dictionary:
	return Defs.DIFFICULTY[map.difficulty].rival


## Picks a spot for the base, as far from the player as the map allows and on solid, dry ground, and builds the Town Center.
func start(player_centre: Vector2i) -> bool:
	var best := Vector2i(-1, -1)
	var best_d := 0.0
	var min_d := map.size * 0.38
	for i in 400:
		var margin := mini(WALL_R + 3, map.size / 5)       # room for the wall ring
		var c := Vector2i(map.rng.randi_range(margin, map.size - margin - 1), map.rng.randi_range(margin, map.size - margin - 1))
		var dist := Vector2(c).distance_to(Vector2(player_centre))
		if dist < min_d or dist <= best_d or not _site_ok(c):
			continue
		if map.find_path(Vector2(player_centre + Vector2i(3, 3)), c).is_empty():
			continue
		best = c
		best_d = dist
	if best.x < 0:
		return false
	base = best
	enemy = Vector2(player_centre)
	style = _pick_style()
	civ = _pick_civ()
	tech = TechState.new(civ)
	map.clear_resources(base, 9.0)
	_starting_resources()
	map.place_foe_building("tc", base - Vector2i(2, 2), true)
	started = true
	var toward := Vector2(player_centre) - Vector2(base)
	rally = Vector2(base) + toward.normalized() * 7.0
	rally = Vector2(map.free_cell_near(Vector2i(rally), 6))
	for i in 6:
		_spawn_villager()
	for i in 2:
		var m := map.make_unit("74", 1, Vector2(map.free_cell_near(Vector2i(rally) + Vector2i(i, 0), 5)))
		_arm(m)
	return true


## What every player starts near: berries, gold, stone and a stand of trees, spread to the side of the map the base faces.
func _starting_resources() -> void:
	var sx := 1 if base.x < map.size / 2 else -1
	var sy := 1 if base.y < map.size / 2 else -1
	map.scatter_clump("berries", base + Vector2i(sx * 9, sy * 5), 6, 1.4)
	map.scatter_clump("gold", base + Vector2i(sx * 5, sy * 11), 6, 1.5)
	map.scatter_clump("stone", base + Vector2i(sx * 12, sy * 10), 5, 1.4)
	map.scatter_stand(base + Vector2i(sx * -11, sy * 9), 16, 2.6)


## A villager steps out of the Town Center.
func _spawn_villager() -> void:
	var t := tc()
	if t == null:
		return
	var r := t.rect()
	var c := map.free_cell_near(Vector2i(r.end.x, r.end.y), 6)
	map.make_unit("villager", 1, Vector2(c))


func on_worker_died(v: FoeVillager) -> void:
	villagers.erase(v)


## Difficulty scaling and the guard order for a soldier of the rival.
func _arm(m: Mob) -> void:
	if m is Soldier:
		var dd: Dictionary = Defs.DIFFICULTY[map.difficulty]
		m.hp *= float(dd.hp)
		m.max_hp *= float(dd.hp)
		m.hp_mult = float(dd.hp)
		m.dmg_mult = float(dd.atk)
		m.guard(_post_for_new())


## Solid ground for a base: no water, shallows or beach within a 9 cell radius.
func _site_ok(c: Vector2i) -> bool:
	for y in range(c.y - 9, c.y + 10, 2):
		for x in range(c.x - 9, c.x + 10, 2):
			var p := Vector2i(x, y)
			if not map.in_bounds(p) or map.inland[y * map.size + x] != 1:
				return false
	return true


## A civilization that builds in the rival's style (so its bonuses and technologies fit what the player sees).
func _pick_civ() -> int:
	var fit: Array[int] = []
	for i in Rules.raw.civ_info.size():
		if int(Rules.raw.civ_info[i].style) == style:
			fit.append(i + 1)
	return fit[map.rng.randi() % fit.size()] if not fit.is_empty() else 1


func _pick_style() -> int:
	var mine := map.style
	var s := map.rng.randi_range(0, 4)
	return s if s != mine else (s + 1) % 5


# ------------------------------------------------------------------ queries
func buildings() -> Array:
	return map.foes.filter(func(b: FoeBuilding) -> bool: return b.alive)


func count(kind: String, only_done := false) -> int:
	var n := 0
	for b: FoeBuilding in map.foes:
		if b.alive and b.kind == kind and (b.done or not only_done):
			n += 1
	return n


func soldiers() -> Array:
	return map.mobs.filter(func(m: Mob) -> bool: return m.team == 1 and m.alive and m is Soldier and not m.naval)


func pop() -> int:
	return workers + soldiers().size() + pop_extra


func pop_cap() -> int:
	return mini(200, count("tc", true) * 5 + count("house", true) * 5)


func tc() -> FoeBuilding:
	for b: FoeBuilding in map.foes:
		if b.alive and b.kind == "tc" and b.done:
			return b
	return null


func train_time(ukind: String) -> float:
	return float(tech.stats(int(ukind)).time) / Rules.GAME_SPEED


func _afford(cost: Dictionary) -> bool:
	for r: String in cost:
		if int(stock[r]) < int(cost[r]):
			return false
	return true


func _pay(cost: Dictionary) -> void:
	for r: String in cost:
		stock[r] = int(stock[r]) - int(cost[r])


# ------------------------------------------------------------------ the clock
func tick(dt: float) -> void:
	if not started or map.finished:
		return
	_t += dt
	_alarm = maxf(0.0, _alarm - dt)
	if researching >= 0.0:
		researching -= dt
		if researching <= 0.0:
			_age_reached()
	_think -= dt
	if _think <= 0.0:
		_think = 1.5
		_decide()


func _decide() -> void:
	if map.attacks_paused:
		return
	_advance()
	_research()
	_train_workers()
	_build()
	_camps()
	_farms()
	_dispatch()
	_towers()
	_walls()
	_gates()
	_train_army()
	_rebalance()
	_war()


# ------------------------------------------------------------------ economy and buildings
## When it starts saving for the next age (the difficulty's age time is when it wants to be there).
func _age_time() -> float:
	return float(d().ages[age]) * 0.75


## Time for the next age and not yet paid: stop spending food on villagers and soldiers so that the cost can be saved.
func _saving() -> bool:
	return age < 3 and researching < 0.0 and _t >= _age_time() and tc() != null


func _train_workers() -> void:
	var t := tc()
	if t == null or _saving() or workers >= int(d().workers) or pop() >= pop_cap() or int(stock.food) < 50:
		return
	if _t >= _vill_cd:
		stock.food = int(stock.food) - 50
		_vill_cd = _t + 9.0
		_spawn_villager()


func _unfinished() -> int:
	var n := 0
	for b: FoeBuilding in map.foes:
		if b.alive and not b.done and b.kind != "wall" and b.kind != "gate":
			n += 1
	return n


## The production buildings wait for the economy: a lumber camp and a source of food, or four minutes.
func _eco_ready() -> bool:
	return _t > 240.0 or (count("lumber_camp", true) >= 1 and count("mill", true) + count("farm", true) >= 1)


func _houses_unfinished() -> int:
	var n := 0
	for b: FoeBuilding in map.foes:
		if b.alive and not b.done and b.kind == "house":
			n += 1
	return n


## Population (villagers, soldiers, siege) is about to reach what the houses allow.
func housing_short() -> bool:
	return pop_cap() < 200 and pop() + 6 > pop_cap() + 5 * _houses_unfinished()


func _build() -> void:
	if tc() == null and count("tc") == 0:
		if _afford(Defs.BUILDINGS.tc.cost):
			_place("tc")
		return
	# houses come first and in pairs when the population is far over: a villager is taken off its work to build them
	if housing_short() and _houses_unfinished() < 2 and _place("house"):
		return
	if _unfinished() >= 3:
		return
	if not _eco_ready():
		return
	for step: Array in Defs.RIVAL_PLAN:
		var kind: String = step[0]
		if int(step[1]) > age or count(kind) >= _want(kind, int(step[2])):
			continue
		if _place(kind):
			return


## The plan lists the target count of each building by age; the difficulty caps the production buildings and towers.
func _want(kind: String, planned: int) -> int:
	if Defs.RIVAL_ROSTER.has(kind):
		return mini(planned, int(d().prod))
	return planned


func _place(kind: String) -> bool:
	var def: Dictionary = Defs.BUILDINGS[kind]
	if not _afford(def.cost):
		return false
	var spot := _spot(int(def.size))
	if spot.x < 0:
		spot = _spot(int(def.size), Vector2i(-1, -1), 8, 15)          # the near rings are full: reach out to the wall
	if spot.x < 0:
		return false
	_pay(def.cost)
	map.place_foe_building(kind, spot, false)
	return true


## The original builds inside a "town" radius that grows with the age (15 / 20 / 25-30 tiles, ours scaled to the map).
func _max_r() -> int:
	return 11 + age


## A free place near the base: rings around the Town Center, with a one cell gap so units can walk between buildings.
func _spot(sz: int, around := Vector2i(-1, -1), rmin := 8, rmax := -1) -> Vector2i:
	var c0 := base if around.x < 0 else around
	for r in range(rmin, (_max_r() if rmax < 0 else rmax) + 1):
		var tries: Array[Vector2i] = []
		for x in range(c0.x - r - sz, c0.x + r + 1):
			for y in range(c0.y - r - sz, c0.y + r + 1):
				if maxi(absi(x - c0.x), absi(y - c0.y)) == r:
					tries.append(Vector2i(x, y))
		tries.shuffle()
		for o in tries:
			if _fits(o, sz):
				return o
	return Vector2i(-1, -1)


func _fits(o: Vector2i, sz: int) -> bool:
	for y in range(o.y - 1, o.y + sz + 1):
		for x in range(o.x - 1, o.x + sz + 1):
			var c := Vector2i(x, y)
			if not map.in_bounds(c) or map.is_occupied(c) or map.inland[y * map.size + x] != 1:
				return false
	return true


# ------------------------------------------------------------------ the economy
## Resources per second one rival villager gathers, and what it carries (the data's values; the difficulty scales the rate).
func rate(kind: String) -> float:
	return float(tech.stats(int(GameMap.GATHERER[kind])).work_rate) * Rules.GAME_SPEED * float(d().gather)


func cap(kind: String) -> int:
	return int(tech.stats(int(GameMap.GATHERER[kind])).capacity)


## The nearest finished drop-off of the rival for a load.
func dropoff(kind: String, p: Vector2) -> FoeBuilding:
	var best: FoeBuilding = null
	var best_d := INF
	for b: FoeBuilding in map.foes:
		if b.alive and b.is_dropoff(kind):
			var dd := map.dist_to(b, p)
			if dd < best_d:
				best_d = dd
				best = b
	return best


func mark_unreachable(r: ResNode) -> void:
	_bad[r.cell] = _t + 90.0


func mark_site_bad(b: FoeBuilding) -> void:
	_bad_sites[b.get_instance_id()] = _t + 120.0


## An empty farm is sown again for wood, as the player's is.
func reseed(f: FoeBuilding) -> bool:
	var cost: Dictionary = Defs.BUILDINGS.farm.cost
	if not _afford(cost):
		return false
	_pay(cost)
	f.food = float(Defs.BUILDINGS.farm.food)
	f.queue_redraw()
	return true


func _gatherers(n: ResNode) -> int:
	var k := 0
	for v: FoeVillager in villagers:
		if v.res == n:
			k += 1
	return k


## The wanted share of the workers per resource: a standard split, nudged towards what the stock lacks.
func _shares() -> Dictionary:
	var s := {"food": 0.32, "wood": 0.34, "gold": 0.18, "stone": 0.16}
	if housing_short():
		s.wood = float(s.wood) * 1.4
	if age == 0 and count("barracks", true) == 0:
		s.gold = 0.08
		s.stone = 0.04
	var sum := 0.0
	for k: String in s:
		s[k] = float(s[k]) * clampf(1.4 - float(stock[k]) / 700.0, 0.35, 1.4)
		sum += float(s[k])
	for k: String in s:
		s[k] = float(s[k]) / sum
	return s


## How far each resource is below its wanted share of the gatherers (v itself not counted); positive = needs more people.
func _gaps(v: FoeVillager) -> Dictionary:
	var counts := {"food": 0, "wood": 0, "gold": 0, "stone": 0}
	var total := 0
	for m: FoeVillager in villagers:
		if m != v and (m.job == "gather" or m.job == "farm"):
			counts[m.gather_kind] += 1
			total += 1
	var s := _shares()
	var out := {}
	for k: String in s:
		out[k] = float(s[k]) - (float(counts[k]) / total if total > 0 else 0.0)
	return out


## After a trip: does the villager go on with its resource, or is another one now much more short of hands?
func keeps(v: FoeVillager) -> bool:
	if v.job == "build":
		return false
	if v.job == "farm":
		return true                    # a farm is a post
	var g := _gaps(v)
	var top := -1.0
	for k: String in g:
		top = maxf(top, float(g[k]))
	return float(g[v.gather_kind]) >= top - 0.12


func _builders() -> int:
	var n := 0
	for v: FoeVillager in villagers:
		if v.job == "build" and v.state != FoeVillager.S.IDLE:
			n += 1
	return n


func _site_builders(b: FoeBuilding) -> int:
	var n := 0
	for v: FoeVillager in villagers:
		if v.site == b:
			n += 1
	return n


## What an idle villager does next: build what is waiting (a few at a time, walls with fewer), else gather what the base lacks.
func assign(v: FoeVillager) -> Dictionary:
	var nb := _builders()
	var best: FoeBuilding = null
	var best_d := 45.0
	for b: FoeBuilding in map.foes:
		if not b.alive or b.done or _site_builders(b) >= 3 or float(_bad_sites.get(b.get_instance_id(), 0.0)) > _t:
			continue
		var limit := mini(8, maxi(2, roundi(workers * 0.25)) if b.kind == "wall" else maxi(3, roundi(workers * 0.6)))      # 8 builders at most, as in the original
		if nb >= limit:
			continue
		var dd := map.dist_to(b, v.tp)
		if dd < best_d:
			best_d = dd
			best = b
	if best:
		return {"job": "build", "site": best}
	var g := _gaps(v)
	if v.job == "" and v.gather_kind != "" and g.has(v.gather_kind):
		g[v.gather_kind] = float(g[v.gather_kind]) + 0.1          # stay with what it was doing when it is a close call
	var kinds: Array = g.keys()
	kinds.sort_custom(func(a: String, b: String) -> bool: return g[a] > g[b])
	for k: String in kinds:
		var o := _option(k, v)
		if not o.is_empty():
			return o
	return {}


## The villager a job can be taken from: nearest first, idle ones before gatherers, gatherers before farmers; none that carry a load.
func _free_villager(p: Vector2) -> FoeVillager:
	var best: FoeVillager = null
	var best_s := INF
	for v: FoeVillager in villagers:
		if v.carry_n > 0 or v.job == "build" or v.job == "garrison" or v.garrisoned_in:
			continue
		var sc := v.tp.distance_to(p) + (0.0 if v.job == "" else (20.0 if v.job == "gather" else 40.0))
		if sc < best_s:
			best_s = sc
			best = v
	return best


## Like a player, it sends a villager (taking one off its work if none is idle) to every site nobody is building and to every farm
## nobody works.
func _dispatch() -> void:
	var nb := _builders()
	var sent := 0
	for walls in [false, true]:
		for b: FoeBuilding in map.foes:
			if sent >= 3:
				return
			if not b.alive or b.done or (b.kind == "wall") != walls or _site_builders(b) > 0 or float(_bad_sites.get(b.get_instance_id(), 0.0)) > _t:
				continue
			if nb >= (mini(8, maxi(2, roundi(workers * 0.25))) if walls else 8):
				continue
			var v := _free_villager(b.tp)
			if v:
				v.command({"job": "build", "site": b})
				nb += 1
				sent += 1
	for f: FoeBuilding in map.foes:
		if f.alive and f.done and f.kind == "farm" and not (is_instance_valid(f.farmer) and f.farmer.alive):
			var v2 := _free_villager(f.tp)
			if v2:
				v2.command({"job": "farm", "farm": f})
				return


func _option(kind: String, v: FoeVillager) -> Dictionary:
	if kind == "food":
		var r := _find(kind)
		if not r.is_empty():
			return {"job": "gather", "kind": kind, "res": r.res}
		for f: FoeBuilding in map.foes:
			if f.alive and f.done and f.kind == "farm" and not (is_instance_valid(f.farmer) and f.farmer != v):
				return {"job": "farm", "farm": f}
		return {}
	var r2 := _find(kind)
	if r2.is_empty():
		return {}
	return {"job": "gather", "kind": kind, "res": r2.res}


## The resource of `kind` nearest to one of the rival's drop-offs for it (with room for another gatherer).
func _find(kind: String) -> Dictionary:
	var set: Dictionary = map.res_sets[kind]
	var best: ResNode = null
	var best_d := INF
	for b: FoeBuilding in map.foes:
		if not b.alive or not b.is_dropoff(kind):
			continue
		var cx := int(b.tp.x)
		var cy := int(b.tp.y)
		for x in range(cx - GATHER_R, cx + GATHER_R + 1):
			for y in range(cy - GATHER_R, cy + GATHER_R + 1):
				var n: ResNode = set.get(Vector2i(x, y))
				if n == null or n.hunt:
					continue
				var dd := b.tp.distance_to(Vector2(n.cell))
				if dd < best_d and float(_bad.get(n.cell, 0.0)) <= _t and _gatherers(n) < CROWD:
					best_d = dd
					best = n
	return {} if best == null else {"res": best}


## How many resources of a kind lie close to a drop-off of the rival (a camp counts while it is being built).
func _served(kind: String) -> int:
	var seen := {}
	for b: FoeBuilding in map.foes:
		if not b.alive or not b.def.has("drop") or not kind in b.def.drop:
			continue
		for x in range(int(b.tp.x - SERVED_R), int(b.tp.x + SERVED_R) + 1):
			for y in range(int(b.tp.y - SERVED_R), int(b.tp.y + SERVED_R) + 1):
				var n: ResNode = map.res_sets[kind].get(Vector2i(x, y))
				if n and not n.hunt and b.tp.distance_to(Vector2(n.cell)) <= SERVED_R:
					seen[n.cell] = true
	return seen.size()


func _near_dropoff(c: Vector2i, kind: String) -> bool:
	for b: FoeBuilding in map.foes:
		if b.alive and b.def.has("drop") and kind in b.def.drop and b.tp.distance_to(Vector2(c)) <= SERVED_R:
			return true
	return false


## How far from the base the rival's camps may go: the original's 20, 35 and 50 tiles by age.
func _reach() -> float:
	return minf(20.0 + 15.0 * age, float(map.size) * 0.4)


## The resource a new camp should serve: a cluster near the base that no drop-off covers yet.
func _camp_target(kind: String) -> ResNode:
	var best: ResNode = null
	var best_score := INF
	var set: Dictionary = map.res_sets[kind]
	for n: ResNode in set.values():
		if n.hunt or not n.alive:
			continue
		var dd := Vector2(n.cell).distance_to(Vector2(base))
		if dd > _reach() or _near_dropoff(n.cell, kind) or float(_bad.get(n.cell, 0.0)) > _t:
			continue
		var near := 0
		for x in range(n.cell.x - 3, n.cell.x + 4):
			for y in range(n.cell.y - 3, n.cell.y + 4):
				if set.has(Vector2i(x, y)):
					near += 1
		var score := dd - 1.5 * minf(near, 8.0)
		if score < best_score:
			best_score = score
			best = n
	return best


## A free 2x2 place beside the resource, preferring the side of the base.
func _camp_spot(target: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_s := INF
	for x in range(target.x - 4, target.x + 4):
		for y in range(target.y - 4, target.y + 4):
			var o := Vector2i(x, y)
			if not _fits(o, 2):
				continue
			var centre := Vector2(o) + Vector2(0.5, 0.5)
			var s := centre.distance_to(Vector2(target)) + 0.15 * centre.distance_to(Vector2(base))
			if s < best_s:
				best_s = s
				best = o
	return best


## Lumber camps, mining camps and mills go up beside the resources the drop-offs do not yet reach; one at a time.
func _camps() -> void:
	if tc() == null or _unfinished() >= 3:
		return
	for pair: Array in [["wood", "lumber_camp"], ["food", "mill"], ["gold", "mining_camp"], ["stone", "mining_camp"]]:
		var kind: String = pair[0]
		var cb: String = pair[1]
		if count(cb) >= int(CAMP_MAX[cb]) or _camp_cd.get(kind, 0.0) > _t or _served(kind) >= int(CAMP_NEED[kind]):
			continue
		if kind == "stone" and age == 0 and count("barracks") == 0 and _served("gold") < 1:
			continue
		if not _afford(Defs.BUILDINGS[cb].cost):
			continue
		var target := _camp_target(kind)
		var spot := Vector2i(-1, -1) if target == null else _camp_spot(target.cell)
		if spot.x >= 0 and map.adjacent_path(Vector2(base), Rect2i(spot, Vector2i(2, 2)), 1).is_empty():
			_bad[target.cell] = _t + 600.0           # across water or walled in by trees: no villager could get there
			spot = Vector2i(-1, -1)
		if spot.x < 0:
			_camp_cd[kind] = _t + 30.0
			continue
		_pay(Defs.BUILDINGS[cb].cost)
		map.place_foe_building(cb, spot, false)
		return


## The berries cannot feed everyone (and run out): the rival sows farms beside the Town Center and its mills, one per farmer.
func _farms() -> void:
	if tc() == null or _unfinished() >= 3:
		return
	var hungry := clampf(1.0 - float(stock.food) / 300.0, 0.0, 1.0)         # short of food: more of the villagers farm
	var want := clampi(roundi(workers * (0.3 + 0.15 * hungry)) - _served("food"), 0, 12)
	if count("farm") >= want or int(stock.wood) < 60 + 40:
		return
	var centres: Array[FoeBuilding] = []
	for b: FoeBuilding in map.foes:
		if b.alive and b.done and (b.kind == "tc" or b.kind == "mill"):
			centres.append(b)
	centres.shuffle()
	for b in centres:
		var spot := _spot(3, Vector2i(b.tp), 3, 7)         # the ring around the center is kept free of other buildings for them
		if spot.x < 0:
			spot = _spot(3, Vector2i(b.tp), 8, 10)
		if spot.x >= 0:
			_pay(Defs.BUILDINGS.farm.cost)
			map.place_foe_building("farm", spot, false)
			return


# ------------------------------------------------------------------ walls and towers
## The wall ring around the base with a gate opening in the middle of each side (the original builds gates there; ours are gaps).
func wall_plan() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in range(-WALL_R, WALL_R + 1):
		if absi(i) <= GATE_HALF:
			continue
		for c: Vector2i in [Vector2i(base.x + i, base.y - WALL_R), Vector2i(base.x + i, base.y + WALL_R),
				Vector2i(base.x - WALL_R, base.y + i), Vector2i(base.x + WALL_R, base.y + i)]:
			if not out.has(c):
				out.append(c)
	return out


func _wall_blocked(c: Vector2i) -> bool:
	if not map.in_bounds(c) or map.inland[c.y * map.size + c.x] != 1 or (map.is_occupied(c) and not map.walls.has(c)):
		return true
	if not _walkable.has(c):          # a piece no villager can walk up to is as good as blocked
		_walkable[c] = not map.adjacent_path(Vector2(base), Rect2i(c, Vector2i.ONE), 1).is_empty()
	return not _walkable[c]


## Fraction of the ring that stands or cannot be built (water, trees): 1.0 when the wall is as complete as it will get.
func wall_complete() -> float:
	if _wall_cells.is_empty():
		return 0.0
	var n := 0
	for c in _wall_cells:
		if map.walls.has(c) or _wall_blocked(c):
			n += 1
	return float(n) / _wall_cells.size()


func _walling() -> bool:
	return bool(d().walls) and age >= 1 and tc() != null and wall_complete() < 1.0


## Feudal Age on: once it holds the original's stone threshold (125, later 300) it lays the ring piece by piece, a few at a time.
func _walls() -> void:
	if not bool(d().walls) or age < 1 or tc() == null:
		return
	if _wall_cells.is_empty():
		_wall_cells = wall_plan()
	if not _wall_started and int(stock.stone) < (125 if age == 1 else 300):
		return
	_wall_started = true
	var open := 8 - count("wall") + _walls_done()
	for c in _wall_cells:
		if open <= 0 or int(stock.stone) < 5:
			break
		if map.walls.has(c) or _wall_blocked(c):
			continue
		_pay(Defs.BUILDINGS.wall.cost)
		map.place_foe_building("wall", c, false)
		open -= 1


## The openings in the ring where its gates stand (the original builds up to 4): one in the middle of each side.
func gate_sites() -> Array:
	return [{"o": Vector2i(base.x - GATE_HALF, base.y - WALL_R), "ax": "x"}, {"o": Vector2i(base.x - GATE_HALF, base.y + WALL_R), "ax": "x"},
		{"o": Vector2i(base.x - WALL_R, base.y - GATE_HALF), "ax": "y"}, {"o": Vector2i(base.x + WALL_R, base.y - GATE_HALF), "ax": "y"}]


## Once most of the ring stands it closes the openings with gates, one at a time, front first.
func _gates() -> void:
	if not bool(d().walls) or age < 1 or tc() == null or wall_complete() < 0.7:
		return
	for b: FoeBuilding in map.foes:
		if b.alive and b.kind == "gate" and not b.done:
			return
	var cost: Dictionary = Defs.BUILDINGS.gate.cost
	if not _afford(cost):
		return
	var toward := (enemy - Vector2(base)).normalized()
	var sites := gate_sites()
	sites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (Vector2(a.o) - Vector2(base)).normalized().dot(toward) > (Vector2(b.o) - Vector2(base)).normalized().dot(toward))
	for st: Dictionary in sites:
		if map.walls.has(st.o) or not map.can_place("gate", st.o, st.ax):
			continue
		_pay(cost)
		map.place_foe_building("gate", st.o, false, st.ax)
		return


func _walls_done() -> int:
	var n := 0
	for b: FoeBuilding in map.foes:
		if b.alive and b.kind == "wall" and b.done:
			n += 1
	return n


func tower_target() -> int:
	return roundi(Defs.RIVAL_TOWERS[age] * float(d().tower_mult))


## Towers come when no wall is being built or when the t-tower timer fires (every 60 s, or 300 s when stone is short).
func _towers() -> void:
	_tower_t += 1.5
	if tc() == null or count("tower") >= tower_target():
		return
	var interval := 60.0 if (int(stock.stone) > 500 or wall_complete() >= 1.0) else 300.0
	if _walling() and _tower_t < interval:
		return
	if not _afford(Defs.BUILDINGS.tower.cost):
		return
	var spot := _tower_spot()
	if spot.x < 0:
		return
	_pay(Defs.BUILDINGS.tower.cost)
	map.place_foe_building("tower", spot, false)
	_tower_t = 0.0


## Towers stand inside the wall, spread out: the candidate farthest from the other towers (and the Town Center) wins.
func _tower_spot() -> Vector2i:
	var others: Array[Vector2] = []
	for b: FoeBuilding in map.foes:
		if b.alive and (b.kind == "tower" or b.kind == "tc"):
			others.append(b.tp)
	var toward := (enemy - Vector2(base)).normalized()
	var best := Vector2i(-1, -1)
	var best_s := -INF
	for i in 80:
		var ang := toward.angle() + map.rng.randf_range(-1.3, 1.3)       # the side the player will come from
		var r := map.rng.randf_range(9.0, WALL_R - 3.0)
		var c := Vector2i(Vector2(base) + Vector2.from_angle(ang) * r)
		if not _fits(c, 1):
			continue
		var d := 99.0
		for p in others:
			d = minf(d, p.distance_to(Vector2(c)))
		var sc := minf(d, 10.0) + 8.0 * Vector2.from_angle(ang).dot(toward)
		if d >= 5.0 and sc > best_s:
			best_s = sc
			best = c
	return best


# ------------------------------------------------------------------ defend groups
## The original keeps defend groups at the town and at the gold and stone mines (priorities 1, 2, 3). Ours: the front of the Town
## Center (weight 3) and each finished mining camp (weight 2). With the military over 30 percent of the population the idle ones
## all gather at the center (sn-gather-idle-soldiers-at-center).
func posts() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"pos": rally, "w": 3}]
	for b: FoeBuilding in map.foes:
		if b.alive and b.done and b.kind == "mining_camp":
			var spot := Vector2(map.free_cell_near(Vector2i(b.tp) + Vector2i(2, 2), 4))
			if spot.distance_to(rally) < 5.0:
				spot = Vector2(map.free_cell_near(Vector2i(b.tp) - Vector2i(2, 2), 4))
			if spot.distance_to(rally) >= 5.0:
				out.append({"pos": spot, "w": 2})
	return out


func _post_for_new() -> Vector2:
	var ps := posts()
	if soldiers().size() * 10 > pop() * 3:
		return ps[0].pos
	var best: Dictionary = ps[0]
	var best_load := INF
	var mine := soldiers()
	for p: Dictionary in ps:
		var n := 0
		for m: Soldier in mine:
			if m.foe_mode == "guard" and m.guard_pos.distance_to(p.pos) < 2.0:
				n += 1
		var load_ := float(n) / float(p.w)
		if load_ < best_load:
			best_load = load_
			best = p
	return best.pos


## A post that is gone (its camp fell) sends its guards to the other posts.
func _rebalance() -> void:
	var ps := posts()
	for m: Soldier in soldiers():
		if m.foe_mode != "guard":
			continue
		if not ps.any(func(p: Dictionary) -> bool: return m.guard_pos.distance_to(p.pos) < 2.0):
			m.guard(_post_for_new())


# ------------------------------------------------------------------ technologies
func _being_researched(id: int) -> bool:
	for b: FoeBuilding in map.foes:
		if b.alive and b.res_tech == id:
			return true
	return false


## Every finished building that researches (Town Center, mill, camps, Blacksmith, ranges, stable, workshop, university) starts the
## first technology of its list (Defs.RIVAL_TECHS) it may have and can pay. Economy first; the military ones on the harder
## difficulties and with an army standing. Not while it saves for the next age.
func _research() -> void:
	_reserve = {}
	if _saving() or tc() == null:
		return
	var army := soldiers().size()
	for b: FoeBuilding in map.foes:
		if not b.alive or not b.done or b.res_tech >= 0 or not Defs.RIVAL_TECHS.has(b.kind):
			continue
		var eco: bool = b.kind in Defs.RIVAL_ECO_TECHS
		if not eco and (String(d().techs) != "all" or army < 4):
			continue
		for id: int in Defs.RIVAL_TECHS[b.kind]:
			if not tech.can_research(id) or _being_researched(id):
				continue
			var cost := Defs.name_cost(tech.cost_of(id))
			if _afford(cost):
				_pay(cost)
				b.res_tech = id
				b.res_t = 0.0
			elif _reserve.is_empty():
				_reserve = cost
			break                                  # one at a time per building: wait for the first one it can have


## A building of the rival finished a technology.
func finish_research(id: int) -> void:
	tech.research(id)
	tech_applied()


## Stats and unlocks changed: its units, villagers and buildings take the new values (and the upgraded unit).
func tech_applied() -> void:
	for b: FoeBuilding in map.foes:
		b.refresh_stats()
	for v: FoeVillager in villagers:
		v.refresh_stats()
	for m in map.mobs:
		if m.team == 1 and m is Soldier:
			m.on_tech_changed()


# ------------------------------------------------------------------ ages
func _advance() -> void:
	if researching >= 0.0 or age >= 3 or tc() == null:
		return
	if _t < _age_time():
		return
	var cost: Dictionary = Defs.RIVAL_AGE_COST[age]
	if not _afford(cost):
		return
	_pay(cost)
	researching = Defs.RIVAL_AGE_TIME[age] / Rules.GAME_SPEED


func _age_reached() -> void:
	researching = -1.0
	tech.research(Rules.AGE_TECHS[age])           # opens the age's technologies and units, as for the player
	age += 1
	for b: FoeBuilding in map.foes:
		b.set_age(age)
	tech_applied()
	map.message.emit("The rival has reached the %s." % Rules.AGE_NAMES[age])


# ------------------------------------------------------------------ the army
func _train_army() -> void:
	var room := pop_cap() - pop()
	if room <= 0 or _saving():
		return
	for b: FoeBuilding in map.foes:
		if not b.alive or not b.done or not Defs.RIVAL_ROSTER.has(b.kind) or b.queue.size() >= 2:
			continue
		var options: Array = Defs.RIVAL_ROSTER[b.kind][age]
		if options.is_empty():
			continue
		var kind: String = options[map.rng.randi() % options.size()]
		var cost := Defs.name_cost(Rules.cost_dict(Combat.base_stats(int(kind)).cost))
		# keep what the technology it waits for will cost
		for res: String in _reserve:
			cost[res] = int(cost.get(res, 0)) + int(_reserve[res])
		if not _afford(cost) or room <= b.queue.size():
			continue
		_pay(cost)
		b.queue.append(kind)
		room -= 1


## A trained soldier leaves its building and gathers at the rally point.
func spawn(ukind: String, from: FoeBuilding) -> void:
	var r := from.rect()
	var c := map.free_cell_near(Vector2i(r.end.x, r.end.y), 6)
	var m := map.make_unit(ukind, 1, Vector2(c))
	_arm(m)
	if m is Soldier:
		m.go_to(map.free_cell_near(Vector2i(m.guard_pos) + Vector2i(map.rng.randi_range(-3, 3), map.rng.randi_range(-3, 3)), 5))


func _war() -> void:
	var army := soldiers()
	if attacking:
		var marching := army.filter(func(m: Soldier) -> bool: return m.foe_mode == "attack")
		if marching.size() <= maxi(1, int(wave_size * 0.25)):          # the wave is spent: the next one may gather
			attacking = false
		elif _t - _wave_start > 420.0:                                   # it never ended (stuck or lost): call the rest home
			attacking = false
			for m: Soldier in marching:
				m.target = null
				m.path.clear()
				m.guard(_post_for_new())
		return
	var need := int(d().army) + wave * int(d().step)
	var ready := army.filter(func(m: Soldier) -> bool: return m.foe_mode == "guard")
	if _t >= float(d().first_attack) and ready.size() >= need:
		attack_now()


## Sends everything that guards the base at the player at once (the debug menu uses it).
func attack_now() -> void:
	var ready := soldiers().filter(func(m: Soldier) -> bool: return m.foe_mode == "guard")
	if ready.is_empty():
		map.message.emit("The rival has no army yet.")
		return
	wave += 1
	wave_size = ready.size()
	attacking = true
	_wave_start = _t
	for m: Soldier in ready:
		m.foe_mode = "attack"
		m.target = null
		m.path.clear()
	Sfx.play("raid")
	map.message.emit("Raid! The rival's army of %d is marching on you." % ready.size())


## Something of the base was hit: the guards go after the attacker.
func on_attacked(attacker: Object) -> void:
	if not is_instance_valid(attacker) or attacker.get("team") != 0:
		return
	_alarm = 12.0
	for m: Soldier in soldiers():
		if m.foe_mode == "guard" and not m.valid(m.target):
			m.target = attacker


func is_alarmed() -> bool:
	return _alarm > 0.0


# ------------------------------------------------------------------ save and load
func snapshot() -> Dictionary:
	return {"base": [base.x, base.y], "style": style, "age": age, "stock": stock, "wave": wave,
		"attacking": attacking, "wave_size": wave_size, "researching": researching, "t": _t, "rally": [rally.x, rally.y], "enemy": [enemy.x, enemy.y], "civ": civ, "techs": tech.researched.keys(), "vcd": _vill_cd, "tower_t": _tower_t, "walling": _wall_started}


func restore(e: Dictionary) -> void:
	base = Vector2i(int(e.base[0]), int(e.base[1]))
	style = int(e.style)
	age = int(e.age)
	civ = int(e.get("civ", 1))
	tech = TechState.new(civ)
	tech.restore(e.get("techs", []))
	for r: String in stock:
		stock[r] = float(e.stock.get(r, 0))
	wave = int(e.wave)
	attacking = bool(e.attacking)
	wave_size = int(e.get("wave_size", 0))
	researching = float(e.researching)
	_t = float(e.t)
	rally = Vector2(float(e.rally[0]), float(e.rally[1]))
	enemy = Vector2(float(e.enemy[0]), float(e.enemy[1])) if e.has("enemy") else Vector2(map.size / 2.0, map.size / 2.0)
	_vill_cd = float(e.get("vcd", 0.0))
	_tower_t = float(e.get("tower_t", 0.0))
	_wall_started = bool(e.get("walling", false))
	_wave_start = _t
	started = true
