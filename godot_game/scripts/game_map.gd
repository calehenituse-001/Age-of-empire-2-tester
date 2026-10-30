class_name GameMap
extends Node2D
## The world: terrain (a TileMapLayer, which the engine draws in cached chunks), ground decals, a y-sorted
## layer for everything standing on the map, the pathfinding grid, and the lists of everything alive.

signal message(text: String)
signal building_finished(b: Building)
signal game_over
signal victory
signal attacked(tile: Vector2)     # one of ours was hit by an enemy or an animal (rate limited)
signal tech_changed                # something was researched (the buttons may change)

# the villager variants whose work rate and carrying capacity the original uses for each kind of work
const GATHERER := {"wood": 123, "gold": 579, "stone": 124, "food": 120, "farm": 214, "hunt": 122}

const RES_AMOUNT := {"wood": 100, "food": 200, "gold": 800, "stone": 350}
const RES_STRIP := {"wood": "trees", "food": "berries", "gold": "gold", "stone": "stone"}

var size := 128
var terrain: TileMapLayer
var ground: Node2D
var entities: Node2D
var astar: AStarGrid2D
var bstar: AStarGrid2D              # the rival's view of astar: its own gates are open to it and the player's are shut (and the other way round in astar)
var rng := RandomNumberGenerator.new()

var mobs: Array[Mob] = []           # everything alive and mobile, all teams
var corpses: Array[Mob] = []
var buildings: Array[Building] = []
var projectiles: Array[Projectile] = []
var res_by_cell: Dictionary = {}    # Vector2i -> ResNode
var res_sets: Dictionary = {"wood": {}, "food": {}, "gold": {}, "stone": {}, "fish": {}}
var fish_nodes: Array[FishNode] = []
var carcasses: Array[Carcass] = []   # kind -> {cell: ResNode}
var occ: PackedByteArray            # 0 free, 1 a building or resource stands here, 2 water (terrain)
var tgrid: PackedByteArray          # terrain id per cell (TerrainBlend: grass, beach, shallows, water)
var inland: PackedByteArray         # 1 where the land is three or more cells from any shore or water
var lakes: Array = []               # each large body of deep water as a PackedInt32Array of cell indices (where raiding ships may come from)
var wastar: AStarGrid2D             # routes for ships: open deep water only
var agrid: AStarGrid2D              # routes for wild animals: like walkers, but they keep off water, shallows and beaches
var world_seed := 0
var _price_t := 0.0

var stock := {"wood": 200, "food": 200, "gold": 100, "stone": 100}
var pop := 0
var pop_cap := 0
var attacks_paused := false
var trees_cut := 0
var tombs: Array[Tombstone] = []
var _attack_t := -10.0
var difficulty := "medium"
var opponent := "raids"          # rival: an enemy base that plays; raids: timed raids from the edge of the map
var rival: Rival
var foes: Array[FoeBuilding] = []
var civ := 1                  # which civilization the player is (1 Britons ... 18 Koreans)
var style := 0                # its architecture set
var tech := TechState.new(1)  # what the player has researched; unit stats and unlocks follow from it
var _see_t := 0.0
var relics: Array[Relic] = []   # every relic: on the ground, carried or in a Monastery
var _relic_gold := 0.0
var walls := {}               # cell -> wall Building, so each wall can pick its piece
var paused := false          # menu open: the whole simulation stands still
var game_time := 0.0
var speed := 1.0
var director: Director
var tree_count := 0
var finished := false


func _init() -> void:
	Defs.sync_rules()


## Resources per second one villager gathers (`kind` is wood, food, gold, stone or farm).
func gather_rate(kind: String) -> float:
	return float(tech.stats(int(GATHERER[kind])).work_rate) * Rules.GAME_SPEED


## What a villager carries before walking to a drop-off.
func carry_cap(kind: String) -> int:
	return int(tech.stats(int(GATHERER[kind])).capacity)


## Villager walking speed compared with the start (Wheelbarrow and Hand Cart).
func walk_factor() -> float:
	return float(tech.stats(83).speed) / float(Rules.units[83].speed)


func generate(n: int, seed_: int) -> void:
	size = n
	world_seed = seed_
	rng.seed = seed_
	tech = TechState.new(civ)
	style = int(Rules.raw.civ_info[civ - 1].style)
	occ = PackedByteArray()
	occ.resize(n * n)
	_make_terrain_grid()
	terrain = TileMapLayer.new()
	add_child(terrain)
	TerrainBlend.apply(terrain, tgrid, n)
	ground = Node2D.new()
	add_child(ground)
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	astar = _new_grid(n)
	bstar = _new_grid(n)
	wastar = _new_grid(n)
	agrid = _new_grid(n)
	for i in n * n:
		var c := Vector2i(i % n, i / n)
		match int(tgrid[i]):
			TerrainBlend.WATER:
				astar.set_point_solid(c, true)       # nobody walks on deep water
				bstar.set_point_solid(c, true)
				agrid.set_point_solid(c, true)
				occ[i] = 2
			TerrainBlend.SHALLOWS:
				wastar.set_point_solid(c, true)      # ships keep to deep water; walkers wade through the shallows
				agrid.set_point_solid(c, true)       # wild animals do not
				occ[i] = 2
			TerrainBlend.BEACH:
				wastar.set_point_solid(c, true)
				agrid.set_point_solid(c, true)
			_:
				wastar.set_point_solid(c, true)
	director = Director.new()
	director.map = self
	add_child(director)


func _new_grid(n: int) -> AStarGrid2D:
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, n, n)
	g.cell_size = Vector2.ONE
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()
	return g


## The ground. Lakes come from warped, layered noise so their outlines wander like real shores; rivers follow the zero
## line of another noise and are wide enough to have a deep middle. Specks are smoothed away and every body of water must
## have at least 25 deep cells (room for a dock and some fishing) or it dries up. Deep water gets a shallow rim and
## land beside it a beach. Meadows of the other two grasses form soft patches. The start area stays dry.
func _make_terrain_grid() -> void:
	var n := size
	tgrid.resize(n * n)
	tgrid.fill(TerrainBlend.GRASS)
	var lake := FastNoiseLite.new()
	lake.seed = world_seed
	lake.frequency = 0.017
	lake.fractal_octaves = 4
	var warp := FastNoiseLite.new()
	warp.seed = world_seed + 5
	warp.frequency = 0.03
	var river := FastNoiseLite.new()
	river.seed = world_seed + 31
	river.frequency = 0.009
	river.fractal_octaves = 2
	var ford := FastNoiseLite.new()
	ford.seed = world_seed + 77
	ford.frequency = 0.04
	var wet := PackedByteArray()
	wet.resize(n * n)
	var centre := Vector2(n / 2.0, n / 2.0)
	for y in n:
		for x in n:
			if mini(mini(x, y), mini(n - 1 - x, n - 1 - y)) < 4 or Vector2(x, y).distance_to(centre) < 24.0:
				continue
			var wx := x + warp.get_noise_2d(x, y) * 14.0
			var wy := y + warp.get_noise_2d(x + 97.0, y + 53.0) * 14.0
			var w := lake.get_noise_2d(wx, wy) > 0.30
			if absf(river.get_noise_2d(wx, wy)) < 0.04 and ford.get_noise_2d(x, y) < 0.4:
				w = true
			wet[y * n + x] = 1 if w else 0
	# rounder shores: a cell is water when most of its neighbours are (a few rounds of majority rule)
	for pass_i in 4:
		var nxt := wet.duplicate()
		for y in range(1, n - 1):
			for x in range(1, n - 1):
				if Vector2(x, y).distance_to(centre) < 24.0:
					continue
				var cnt := 0
				for d in TerrainBlend.NB:
					cnt += wet[(y + d.y) * n + x + d.x]
				nxt[y * n + x] = 1 if (cnt >= 3 if wet[y * n + x] == 1 else cnt >= 5) else 0
		wet = nxt
	_drop_small_water(wet)
	for y in n:
		for x in n:
			var near_wet := false
			var near_dry := false
			for d in TerrainBlend.NB:
				var c := Vector2i(x, y) + d
				if c.x < 0 or c.y < 0 or c.x >= n or c.y >= n:
					continue
				if wet[c.y * n + c.x] == 1:
					near_wet = true
				else:
					near_dry = true
			if wet[y * n + x] == 1:
				tgrid[y * n + x] = TerrainBlend.SHALLOWS if near_dry else TerrainBlend.WATER
			elif near_wet:
				tgrid[y * n + x] = TerrainBlend.BEACH
	_find_lakes()
	# meadows: soft patches of the two other grasses
	var patch := FastNoiseLite.new()
	patch.seed = world_seed + 211
	patch.frequency = 0.045
	patch.fractal_octaves = 2
	for i in n * n:
		if int(tgrid[i]) == TerrainBlend.GRASS:
			var v := patch.get_noise_2d(i % n, i / n)
			if v > 0.22:
				tgrid[i] = TerrainBlend.GRASS2
			elif v < -0.26:
				tgrid[i] = TerrainBlend.GRASS3
	# land that is at least three cells from any shore or water: where trees, mines and bushes may stand
	inland = PackedByteArray()
	inland.resize(n * n)
	for y in n:
		for x in n:
			var ok := true
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var c := Vector2i(x + dx, y + dy)
					if c.x >= 0 and c.y >= 0 and c.x < n and c.y < n and not TerrainBlend.is_grass(int(tgrid[c.y * n + c.x])):
						ok = false
						break
				if not ok:
					break
			inland[y * n + x] = 1 if ok else 0


## Bodies of deep water with at least 80 cells (four-neighbour flood fill).
func _find_lakes() -> void:
	lakes.clear()
	var n := size
	var seen := PackedByteArray()
	seen.resize(n * n)
	for start in n * n:
		if int(tgrid[start]) != TerrainBlend.WATER or seen[start] == 1:
			continue
		var comp := PackedInt32Array()
		var stack: Array[int] = [start]
		seen[start] = 1
		while not stack.is_empty():
			var i: int = stack.pop_back()
			comp.append(i)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var c := Vector2i(i % n, i / n) + d
				if c.x >= 0 and c.y >= 0 and c.x < n and c.y < n and int(tgrid[c.y * n + c.x]) == TerrainBlend.WATER and seen[c.y * n + c.x] == 0:
					seen[c.y * n + c.x] = 1
					stack.append(c.y * n + c.x)
		if comp.size() >= 80:
			lakes.append(comp)


## Where raiding warships appear: in the large lake that comes closest to the player's buildings (within 18 tiles), at a cell
## about 30 tiles from them; Vector2i(-1, -1) when no lake is near enough.
func naval_spawn() -> Vector2i:
	var best_lake := -1
	var best_d := 18.0
	for li in lakes.size():
		var lake: PackedInt32Array = lakes[li]
		for k in range(0, lake.size(), 5):
			var c := Vector2(lake[k] % size, lake[k] / size)
			for b in buildings:
				var d := b.tp.distance_to(c)
				if d < best_d:
					best_d = d
					best_lake = li
	if best_lake < 0:
		return Vector2i(-1, -1)
	var pick := Vector2i(-1, -1)
	var pick_err := INF
	var lake2: PackedInt32Array = lakes[best_lake]
	for k in range(0, lake2.size(), 3):
		var c := Vector2(lake2[k] % size, lake2[k] / size)
		var nearest := INF
		for b in buildings:
			nearest = minf(nearest, b.tp.distance_to(c))
		var err := absf(nearest - 30.0) + (60.0 if nearest < 20.0 else 0.0)
		if err < pick_err:
			pick_err = err
			pick = Vector2i(c)
	return pick


## Water that has fewer than 25 deep cells (cells whose eight neighbours are water too) dries up: no puddles, no streams
## too narrow to sail.
func _drop_small_water(wet: PackedByteArray) -> void:
	var n := size
	var seen := PackedByteArray()
	seen.resize(n * n)
	for start in n * n:
		if wet[start] == 0 or seen[start] == 1:
			continue
		var comp: Array[int] = []
		var stack: Array[int] = [start]
		seen[start] = 1
		var deep := 0
		while not stack.is_empty():
			var i: int = stack.pop_back()
			comp.append(i)
			var x := i % n
			var y := i / n
			var inner := x > 0 and y > 0 and x < n - 1 and y < n - 1
			if inner:
				var all_wet := true
				for d in TerrainBlend.NB:
					if wet[(y + d.y) * n + x + d.x] == 0:
						all_wet = false
						break
				if all_wet:
					deep += 1
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var c := Vector2i(x, y) + d
				if c.x >= 0 and c.y >= 0 and c.x < n and c.y < n and wet[c.y * n + c.x] == 1 and seen[c.y * n + c.x] == 0:
					seen[c.y * n + c.x] = 1
					stack.append(c.y * n + c.x)
		if deep < 25:
			for i in comp:
				wet[i] = 0


func terrain_at(c: Vector2i) -> int:
	return int(tgrid[c.y * size + c.x])


func is_water(c: Vector2i) -> bool:
	return in_bounds(c) and terrain_at(c) == TerrainBlend.WATER


## Screen-space bounds of the diamond, for clamping the camera.
func world_rect() -> Rect2:
	return Rect2(-size * Iso.HW, -Iso.HH, 2.0 * size * Iso.HW, size * 2.0 * Iso.HH)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size


func is_solid(c: Vector2i) -> bool:
	return astar.is_point_solid(c)


func _set_solid(c: Vector2i, v: bool) -> void:
	if terrain_at(c) == TerrainBlend.WATER:
		wastar.set_point_solid(c, v)        # on deep water only a building (a dock) blocks ships; walkers never cross it
		return
	astar.set_point_solid(c, v)
	bstar.set_point_solid(c, v)
	var t := terrain_at(c)
	agrid.set_point_solid(c, v or t == TerrainBlend.BEACH or t == TerrainBlend.SHALLOWS)


func is_occupied(c: Vector2i) -> bool:
	return occ[c.y * size + c.x] != 0


func _set_occ(c: Vector2i, v: bool) -> void:
	var t := terrain_at(c)
	occ[c.y * size + c.x] = 1 if v else (2 if t == TerrainBlend.WATER or t == TerrainBlend.SHALLOWS else 0)


# ------------------------------------------------------------------ pathfinding
## Cells from `from` to `to` inclusive, or empty if there is no route.
func find_path(from: Vector2, to: Vector2i, naval := false, wild := false, team := 0) -> Array[Vector2i]:
	var g := wastar if naval else (agrid if wild else (bstar if team == 1 else astar))
	var a := Vector2i(clampi(roundi(from.x), 0, size - 1), clampi(roundi(from.y), 0, size - 1))
	if not in_bounds(to) or g.is_point_solid(to):
		return [] as Array[Vector2i]
	if g.is_point_solid(a):
		a = free_cell_near(a, 4, naval, wild)
	return g.get_id_path(a, to)


func blocked(c: Vector2i, naval: bool, wild := false, team := 0) -> bool:
	return (wastar if naval else (agrid if wild else (bstar if team == 1 else astar))).is_point_solid(c)


## Mines, bushes and trees stand well inland: not on water, shallows or beaches, nor on the grass that blends into them.
func resource_ok(c: Vector2i) -> bool:
	return in_bounds(c) and not is_occupied(c) and inland[c.y * size + c.x] == 1


## A route over deep water to a free water cell touching `rect` (a dock), preferring the closest one.
func adjacent_water_path(from: Vector2, rect: Rect2i) -> Array[Vector2i]:
	var cands: Array[Vector2i] = []
	for x in range(rect.position.x - 1, rect.end.x + 1):
		for y in range(rect.position.y - 1, rect.end.y + 1):
			var c := Vector2i(x, y)
			if rect.has_point(c) or not in_bounds(c) or wastar.is_point_solid(c):
				continue
			cands.append(c)
	cands.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return Vector2(p).distance_squared_to(from) < Vector2(q).distance_squared_to(from))
	for i in mini(4, cands.size()):
		var p := find_path(from, cands[i], true)
		if not p.is_empty():
			return p
	return [] as Array[Vector2i]


## Where a ship can stand to hit something at `target` from `r` tiles away: the open water cell within reach that is nearest to
## `from` (or Vector2i(-1, -1) when the target cannot be reached from the water).
func firing_cell(from: Vector2, target: Vector2, r: float) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	var reach := maxf(r * 0.85, 1.0)
	var t := Vector2i(roundi(target.x), roundi(target.y))
	var n := ceili(reach)
	for x in range(t.x - n, t.x + n + 1):
		for y in range(t.y - n, t.y + n + 1):
			var c := Vector2i(x, y)
			if not in_bounds(c) or wastar.is_point_solid(c) or Vector2(c).distance_to(target) > reach:
				continue
			var d := Vector2(c).distance_to(from)
			if d < best_d:
				best_d = d
				best = c
	return best


## The nearest thing of the player's (building, ship, unit or villager on the shore) that a warship at `p` could shoot from the
## water, within `max_d` tiles, or null.
func naval_target(p: Vector2, r: float, max_d: float) -> Object:
	var cands: Array = []
	for b in buildings:
		if b.alive and b.tp.distance_to(p) < max_d:
			cands.append(b)
	for m in mobs:
		if m.team == 0 and m.alive and m.tp.distance_to(p) < max_d:
			cands.append(m)
	cands.sort_custom(func(a: Object, b: Object) -> bool: return a.tp.distance_to(p) < b.tp.distance_to(p))
	for i in mini(cands.size(), 14):
		if firing_cell(p, cands[i].tp, r + (cands[i].bsize * 0.5 if cands[i] is Building else 0.0)) != Vector2i(-1, -1):
			return cands[i]
	return null


func free_water_near(c: Vector2i, max_r: int) -> Vector2i:
	return free_cell_near(c, max_r, true)


## A route to a free cell touching `rect`, preferring the closest one.
func adjacent_path(from: Vector2, rect: Rect2i, team := 0) -> Array[Vector2i]:
	var cands: Array[Vector2i] = []
	for x in range(rect.position.x - 1, rect.end.x + 1):
		for y in range(rect.position.y - 1, rect.end.y + 1):
			var c := Vector2i(x, y)
			if rect.has_point(c) or not in_bounds(c) or is_solid(c):
				continue
			cands.append(c)
	cands.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return Vector2(p).distance_squared_to(from) < Vector2(q).distance_squared_to(from))
	for i in mini(4, cands.size()):
		var p := find_path(from, cands[i], false, false, team)
		if not p.is_empty():
			return p
	return [] as Array[Vector2i]


## The `n` free cells closest to `c`, for sending a group of units to one spot.
func spread_cells(c: Vector2i, n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := 0
	while out.size() < n and r < 12:
		for x in range(c.x - r, c.x + r + 1):
			for y in range(c.y - r, c.y + r + 1):
				if maxi(absi(x - c.x), absi(y - c.y)) != r:
					continue
				var p := Vector2i(x, y)
				if in_bounds(p) and not is_solid(p) and out.size() < n:
					out.append(p)
		r += 1
	return out


func free_cell_near(c: Vector2i, max_r: int, naval := false, wild := false) -> Vector2i:
	for r in range(0, max_r + 1):
		for x in range(c.x - r, c.x + r + 1):
			for y in range(c.y - r, c.y + r + 1):
				if maxi(absi(x - c.x), absi(y - c.y)) != r:
					continue
				var p := Vector2i(x, y)
				if in_bounds(p) and not blocked(p, naval, wild):
					return p
	return c


# ------------------------------------------------------------------ resources
func spawn_res_node(rname: String, variant: int, c: Vector2i) -> ResNode:
	if rname == "fish":
		return spawn_fish(variant, c)
	var kind := "wood"
	for k: String in RES_STRIP:
		if RES_STRIP[k] == rname:
			kind = k
	var n := ResNode.new()
	Assets.apply_resource(n, rname, variant)
	n.setup(kind, c, int(RES_AMOUNT[kind]))
	n.rname = rname
	n.variant = variant
	n.position = Iso.to_world(Vector2(c))
	entities.add_child(n)
	res_by_cell[c] = n
	res_sets[kind][c] = n
	_set_solid(c, true)
	_set_occ(c, true)
	return n


## A school of fish on a deep-water cell (`unit_id` is the data's fish unit).
func spawn_fish(unit_id: int, c: Vector2i, amount := -1) -> FishNode:
	var f := FishNode.new()
	f.setup_fish(unit_id, c, amount if amount >= 0 else int(Rules.units[unit_id].resource_storage[0][1]))
	f.position = Iso.to_world(Vector2(c))
	entities.add_child(f)
	res_by_cell[c] = f
	res_sets["fish"][c] = f
	fish_nodes.append(f)
	return f


## Fish in the deep water, about one school to every 28 cells, a few great fish among them.
func scatter_fish() -> void:
	var kinds := [53, 455, 456, 457, 458]
	for i in tgrid.size():
		if int(tgrid[i]) != TerrainBlend.WATER or rng.randi() % 28 != 0:
			continue
		var c := Vector2i(i % size, i / size)
		if res_by_cell.has(c):
			continue
		spawn_fish(450 if rng.randi() % 9 == 0 else kinds[rng.randi() % kinds.size()], c)


func remove_fish(f: ResNode) -> void:
	f.alive = false
	res_by_cell.erase(f.cell)
	res_sets["fish"].erase(f.cell)
	fish_nodes.erase(f)
	f.queue_free()


## The closest school of fish within `r` tiles; with `reachable` only one a ship can sail to from `p` (a lake next door does not count).
func nearest_fish(p: Vector2, r: float, reachable := false) -> ResNode:
	var found: Array = []
	for c: Vector2i in res_sets["fish"]:
		var d := p.distance_to(Vector2(c))
		if d < r:
			found.append([d, res_sets["fish"][c]])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	if not reachable:
		return found[0][1] if not found.is_empty() else null
	for i in mini(found.size(), 10):
		var f: ResNode = found[i][1]
		if not find_path(p, f.cell, true).is_empty():
			return f
	return null


func nearest_dock(p: Vector2) -> Building:
	var best: Building = null
	var bd := INF
	for b in buildings:
		if b.kind == "dock" and b.done and b.alive:
			var d := b.tp.distance_to(p)
			if d < bd:
				bd = d
				best = b
	return best


## Food per second one fishing ship gathers (the data's work rate times its fish task), and what its hold takes.
func fish_rate() -> float:
	return float(tech.stats(13).work_rate) * 1.75 * Rules.GAME_SPEED


func fish_capacity() -> int:
	return int(tech.stats(13).capacity)


## Meat where a deer or boar fell (a free cell nearby when something already lies there).
func spawn_carcass(a: Animal) -> void:
	var c := a.cell()
	if res_by_cell.has(c):
		c = free_cell_near(c, 3)
		if res_by_cell.has(c):
			return
	var n := Carcass.new()
	n.setup_carcass(a)
	n.cell = c
	entities.add_child(n)
	res_by_cell[c] = n
	res_sets["food"][c] = n
	carcasses.append(n)


func carcass_near(p: Vector2, r := 3.5) -> Carcass:
	var best: Carcass = null
	var bd := r
	for c in carcasses:
		if c.alive and p.distance_to(Vector2(c.cell)) < bd:
			bd = p.distance_to(Vector2(c.cell))
			best = c
	return best


func remove_res(n: ResNode) -> void:
	if n is Carcass:
		n.alive = false
		res_by_cell.erase(n.cell)
		res_sets["food"].erase(n.cell)
		carcasses.erase(n)
		n.queue_free()
		return
	n.alive = false
	res_by_cell.erase(n.cell)
	res_sets[n.kind].erase(n.cell)
	_set_solid(n.cell, false)
	_set_occ(n.cell, false)
	n.queue_free()
	if n.kind == "wood":
		Sfx.at("tree_fall", n.position)
	_respawn(n.kind)


## Nothing runs out: every mine or bush that is used up reappears elsewhere, and every 10 trees cut
## grow 10 new ones at random places.
func _respawn(kind: String) -> void:
	if kind == "wood":
		trees_cut += 1
		if trees_cut % 10 == 0:
			var items: Array = Assets.man.resources.trees.items
			for i in 10:
				var c := _random_free_cell(false)
				if c.x >= 0:
					spawn_res_node("trees", rng.randi() % items.size(), c)
		return
	var rname: String = RES_STRIP[kind]
	var c := _random_free_cell(true)
	if c.x >= 0:
		var items: Array = Assets.man.resources[rname].items
		spawn_res_node(rname, rng.randi() % items.size(), c)
		message.emit("A new %s was found somewhere on the map" % {"gold": "gold mine", "stone": "stone mine", "food": "berry bush"}[kind])


## A random empty cell away from our buildings; `reachable` also needs a walking route from a Town Center.
func _random_free_cell(reachable: bool) -> Vector2i:
	var tc: Building = null
	for b in buildings:
		if b.kind == "tc" and b.done:
			tc = b
			break
	for attempt in 40:
		var c := Vector2i(rng.randi_range(2, size - 3), rng.randi_range(2, size - 3))
		if not resource_ok(c):
			continue
		var near := false
		for b in buildings:
			if b.tp.distance_to(Vector2(c)) < 5.0:
				near = true
				break
		if near:
			continue
		if reachable and tc != null:
			var ok := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if in_bounds(c + d) and not is_solid(c + d) and not find_path(tc.tp, c + d).is_empty():
					ok = true
					break
			if not ok:
				continue
		return c
	return Vector2i(-1, -1)


## Nearest gatherable of `kind` around `from`, searching outwards in square rings.
func find_resource(kind: String, from: Vector2i, radius: int, exclude: ResNode = null) -> ResNode:
	var set: Dictionary = res_sets[kind]
	if set.is_empty():
		return null
	var far := radius if kind != "wood" else maxi(radius, 40)
	for r in range(0, far + 1):
		var best: ResNode = null
		var best_d := INF
		for x in range(from.x - r, from.x + r + 1):
			for y in range(from.y - r, from.y + r + 1):
				if r > 0 and maxi(absi(x - from.x), absi(y - from.y)) != r:
					continue
				var n: ResNode = set.get(Vector2i(x, y))
				if n and n != exclude:
					var d := Vector2(from).distance_squared_to(Vector2(n.cell))
					if d < best_d:
						best_d = d
						best = n
		if best:
			return best
	if kind != "wood":
		var best: ResNode = null
		var best_d := INF
		for n: ResNode in set.values():
			if n != exclude:
				var d := Vector2(from).distance_squared_to(Vector2(n.cell))
				if d < best_d:
					best_d = d
					best = n
		return best
	return null


func add_resource(kind: String, n: int) -> void:
	stock[kind] += n


func can_afford(cost: Dictionary) -> bool:
	for k: String in cost:
		if stock[k] < int(cost[k]):
			return false
	return true


func pay(cost: Dictionary) -> void:
	for k: String in cost:
		stock[k] -= int(cost[k])


# ------------------------------------------------------------------ buildings
func can_place(kind: String, origin: Vector2i, axis := "x") -> bool:
	if kind == "dock":
		return _can_place_dock(origin)
	if kind == "gate":
		return _can_place_gate(origin, axis)
	var s := int(Defs.BUILDINGS[kind].size)
	for y in s:
		for x in s:
			var c := origin + Vector2i(x, y)
			if not in_bounds(c) or is_occupied(c):
				return false
	return true


## A gate is 3 cells long along x or y; it may stand on free cells and on walls of ours (it replaces them).
func _can_place_gate(origin: Vector2i, axis: String) -> bool:
	for i in 3:
		var c := origin + (Vector2i(i, 0) if axis == "x" else Vector2i(0, i))
		if not in_bounds(c):
			return false
		var w: Building = walls.get(c)
		if is_occupied(c) and not (w != null and w.kind == "wall" and w.team == 0):
			return false
	return true


## A dock stands on the shore: at least three cells of water or shallows and one of beach or land under it, nothing
## else in the way, and open deep water beside it for the ships.
func _can_place_dock(origin: Vector2i) -> bool:
	var s := int(Defs.BUILDINGS.dock.size)
	var wet := 0
	var dry := 0
	for y in s:
		for x in s:
			var c := origin + Vector2i(x, y)
			if not in_bounds(c) or occ[c.y * size + c.x] == 1:
				return false
			match terrain_at(c):
				TerrainBlend.WATER, TerrainBlend.SHALLOWS:
					wet += 1
				_:
					dry += 1
	if wet < 3 or dry < 1:
		return false
	var r := Rect2i(origin, Vector2i(s, s))
	for x in range(origin.x - 1, origin.x + s + 1):
		for y in range(origin.y - 1, origin.y + s + 1):
			var c := Vector2i(x, y)
			if not r.has_point(c) and in_bounds(c) and terrain_at(c) == TerrainBlend.WATER and not wastar.is_point_solid(c):
				return true
	return false


func place_building(kind: String, origin: Vector2i, done: bool, axis := "x") -> Building:
	var b := Building.new()
	b.gate_axis = axis
	b.setup(self, kind, origin, done)
	if kind == "farm":
		ground.add_child(b)
	else:
		entities.add_child(b)
	var r := b.rect()
	for y in r.size.y:
		for x in r.size.x:
			var c := r.position + Vector2i(x, y)
			_set_occ(c, true)
			if kind != "farm":
				_set_solid(c, true)
	if kind != "farm":
		_evict(r)
	buildings.append(b)
	if b.def.get("ages", false):
		b.set_age_level(tech.age() + 1)
	if kind == "tc" and done:
		add_tc_decal(b)
	if kind == "wall":
		walls[origin] = b
		_refresh_walls_around(origin)
	elif kind == "gate":
		_register_gate(b)
	if done:
		recalc_pop()
	return b


## A gate counts as wall for its neighbours; its cells let its own team through (astar for the player, bstar for the rival).
func _register_gate(b: Building) -> void:
	var r := b.rect()
	for y in r.size.y:
		for x in r.size.x:
			walls[r.position + Vector2i(x, y)] = b
	set_gate_cells(b)
	for y in r.size.y:
		for x in r.size.x:
			_refresh_walls_around(r.position + Vector2i(x, y))


func set_gate_cells(b: Building) -> void:
	var r := b.rect()
	for y in r.size.y:
		for x in r.size.x:
			var c := r.position + Vector2i(x, y)
			astar.set_point_solid(c, b.team != 0 or b.locked)
			bstar.set_point_solid(c, b.team != 1 or b.locked)


## Locked gates stay shut for everybody.
func set_gate_locked(b: Building, v: bool) -> void:
	b.locked = v
	set_gate_cells(b)
	b.refresh_gate()


## The nearest wall or gate of the other team: what a soldier breaks when there is no way through.
func nearest_blocker(p: Vector2, my_team: int) -> Building:
	var best: Building = null
	var best_d := 40.0
	for w: Building in walls.values():
		if w.alive and w.team != my_team:
			var d := w.tp.distance_to(p)
			if d < best_d:
				best_d = d
				best = w
	return best


## The rival's base: starts it (a Town Center and its first houses are laid out by the Rival as it plays). False when
## the map has no room far enough from the player.
func start_rival(player_centre: Vector2i) -> bool:
	opponent = "rival"
	rival = Rival.new()
	rival.map = self
	add_child(rival)
	if not rival.start(player_centre):
		rival.queue_free()
		rival = null
		opponent = "raids"
		return false
	return true


func place_foe_building(kind: String, origin: Vector2i, done: bool, axis := "x") -> FoeBuilding:
	var b := FoeBuilding.new()
	b.gate_axis = axis
	b.age = rival.age if rival else 0
	b.setup(self, kind, origin, done)
	(ground if kind == "farm" else entities).add_child(b)
	var r := b.rect()
	for y in r.size.y:
		for x in r.size.x:
			var c := r.position + Vector2i(x, y)
			_set_occ(c, true)
			if kind != "farm":
				_set_solid(c, true)
	if kind != "farm":
		_evict(r)
	foes.append(b)
	if kind == "wall":
		walls[origin] = b
		_refresh_walls_around(origin)
	elif kind == "gate":
		_register_gate(b)
	return b


## A wall piece or gate is gone: its neighbours take the end pieces.
func _forget_wall(b: Building) -> void:
	if b.kind == "wall":
		walls.erase(b.origin)
		_refresh_walls_around(b.origin)
	elif b.kind == "gate":
		var r := b.rect()
		for y in r.size.y:
			for x in r.size.x:
				walls.erase(r.position + Vector2i(x, y))
		for y in r.size.y:
			for x in r.size.x:
				_refresh_walls_around(r.position + Vector2i(x, y))


func on_foe_destroyed(b: FoeBuilding) -> void:
	b.unload_all()
	foes.erase(b)
	_forget_wall(b)
	add_rubble(b)
	Sfx.at("collapse", b.position)
	var r := b.rect()
	for y in r.size.y:
		for x in r.size.x:
			var c := r.position + Vector2i(x, y)
			_set_occ(c, false)
			_set_solid(c, false)
	if b.kind == "tc":
		message.emit("The rival's Town Center has fallen!")
	if not finished and opponent == "rival" and foes.all(func(f: FoeBuilding) -> bool: return f.kind == "wall" or f.kind == "gate"):
		finished = true
		attacks_paused = true
		victory.emit()


# ------------------------------------------------------------------ relics and conversion
func add_relic(p: Vector2) -> Relic:
	var r := Relic.new()
	r.setup(self, p)
	entities.add_child(r)
	relics.append(r)
	return r


## `n` relics on dry open ground, far from the player's town and from each other.
func scatter_relics(n: int, avoid: Vector2i) -> void:
	var placed: Array[Vector2i] = []
	for i in 600:
		if placed.size() >= n:
			break
		var c := Vector2i(rng.randi_range(6, size - 7), rng.randi_range(6, size - 7))
		if not resource_ok(c) or is_solid(c) or Vector2(c).distance_to(Vector2(avoid)) < 24.0:
			continue
		if placed.any(func(o: Vector2i) -> bool: return Vector2(o).distance_to(Vector2(c)) < 14.0):
			continue
		placed.append(c)
		add_relic(Vector2(c))


## Each relic inside a Monastery of ours pays gold.
func _relic_income(dt: float) -> void:
	var stored := 0
	for b in buildings:
		if b.alive and b.done:
			stored += b.relics.size()
	if stored == 0:
		return
	_relic_gold += stored * Relic.GOLD_RATE * Rules.GAME_SPEED * dt
	var whole := int(_relic_gold)
	if whole > 0:
		_relic_gold -= whole
		stock.gold += whole


## A monk converted a unit: it fights for his side from now on. A villager of the rival is replaced by a villager of ours.
func convert_mob(m: Mob, to_team: int) -> Mob:
	for c in m.get_children():
		if c is ConvertAura:
			c.queue_free()
	if m is FoeVillager:
		var ratio := m.hp / m.max_hp
		var v := make_unit("villager", to_team, m.tp)
		v.hp = v.max_hp * ratio
		if rival:
			rival.on_worker_died(m)
		m.alive = false
		m.set_selected(false)
		mobs.erase(m)
		m.queue_free()
		recalc_pop()
		return v
	if m is Soldier:
		m.convert_to(to_team)
	recalc_pop()
	return m


## Trees, mines and bushes within `radius` of a cell are removed (a base needs open ground).
func clear_resources(c: Vector2i, radius: float) -> void:
	for n: ResNode in res_by_cell.values():
		if n.alive and not n is Carcass and Vector2(n.cell).distance_to(Vector2(c)) < radius:
			remove_res(n)


## The rival's building nearest to a point within `r` tiles (the player's soldiers attack these on their own).
func nearest_foe_building(p: Vector2, r: float) -> FoeBuilding:
	var best: FoeBuilding = null
	var best_d := r
	for b in foes:
		if b.alive and b.kind != "wall" and b.kind != "gate":         # walls and gates are only attacked on order
			var d := dist_to(b, p)
			if d < best_d:
				best_d = d
				best = b
	return best


## Which of the five wall pieces fits a cell: a straight run along one of the four directions when
## exactly two neighbours line up, a post at ends, corners and junctions. `extra` holds planned cells.
func wall_piece(c: Vector2i, extra := {}) -> int:
	var axes: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	var straight := [1, 0, 4, 3]
	var total := 0
	var line := -1
	for i in 4:
		var n := 0
		for sgn in [1, -1]:
			var q: Vector2i = c + axes[i] * sgn
			if walls.has(q) or extra.has(q):
				n += 1
		total += n
		if n == 2:
			line = i
	return straight[line] if total == 2 and line >= 0 else 2


func _refresh_walls_around(c: Vector2i) -> void:
	for d: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var w: Building = walls.get(c + d)
		if w:
			w.refresh_wall()


## The Market: only against gold, like the original. Prices start at 100 and move 3 with every 100 traded; the fee is 30%
## (15% once Guilds are researched, which sets resource 78).
var prices := {"food": 100.0, "wood": 100.0, "stone": 100.0, "gold": 100.0}
const BARTER_STEP := 3.0


func barter_fee() -> float:
	return float(tech.res.get(78, 0.30))


## What 100 of `res` fetch in gold right now.
func barter_sell_gain(res: String) -> int:
	return int(100.0 * prices[res] / prices["gold"] * (1.0 - barter_fee()))


## What 100 of `res` cost in gold right now.
func barter_buy_cost(res: String) -> int:
	return ceili(100.0 * prices[res] / prices["gold"] * (1.0 + barter_fee()))


func barter(res: String, sell: bool) -> String:
	if res == "gold" or not stock.has(res):
		return "Gold is the money"
	if sell:
		if int(stock[res]) < 100:
			return "You need 100 %s to sell" % res
		stock.gold += barter_sell_gain(res)
		stock[res] -= 100
		prices[res] = maxf(20.0, prices[res] - BARTER_STEP)
		prices.gold = minf(300.0, prices.gold + BARTER_STEP)
	else:
		var cost := barter_buy_cost(res)
		if int(stock.gold) < cost:
			return "You need %d gold" % cost
		stock.gold -= cost
		stock[res] += 100
		prices[res] = minf(300.0, prices[res] + BARTER_STEP)
		prices.gold = maxf(20.0, prices.gold - BARTER_STEP)
	return ""


## Starts a technology in a building; returns an error text or "".
func try_research(b: Building, id: int) -> String:
	if not b.done or not b.alive:
		return "Not finished yet"
	if b.res_tech >= 0:
		return "%s is busy researching" % b.def.name
	if tech.researched.has(id):
		return "Already researched"
	for o in buildings:
		if o.res_tech == id:
			return "Already being researched"
	if not tech.can_research(id):
		return Defs.tech_lock_reason(tech, id)
	var cost := Defs.name_cost(tech.cost_of(id))
	if not can_afford(cost):
		return "Not enough resources (%s)" % Defs.cost_text(cost)
	pay(cost)
	b.start_research(id)
	return ""


## A building finished a technology.
func finish_research(id: int) -> void:
	var before := tech.age()
	tech.research(id)
	_tech_applied()
	var nm: String = Rules.techs[id].name
	if tech.age() != before:
		message.emit("%s reached! New buildings and technologies are open." % Rules.AGE_NAMES[tech.age()])
	else:
		message.emit("%s researched" % nm)


func _tech_applied() -> void:
	for b in buildings:
		if b.def.get("ages", false):
			b.set_age_level(tech.age() + 1)
		b.refresh_look()
	for m in mobs:
		if m is Villager and m.team == 0:
			m.refresh_stats()
		elif (m is Soldier or m is Ship) and m.team == 0:
			m.on_tech_changed()
	recalc_pop()
	tech_changed.emit()


## The technologies a building offers right now: the ones whose requirements are met, plus the next age at a Town Center.
func tech_cards(b: Building) -> Array:
	if not b.def.has("uid") or not b.done:
		return []
	var out: Array = tech.techs_at(int(b.def.uid), true)
	if b.def.get("ages", false) and tech.age() < 3:
		var next: int = Rules.AGE_TECHS[tech.age()]
		if not out.has(next) and tech.tech_ok(next) and not tech.researched.has(next):
			out.insert(0, next)
	return out


## What a destroyed building leaves on the ground.
func add_rubble(b: Building) -> void:
	if b.kind == "farm":
		return
	var s := Assets.building_sprite("rubble%d" % clampi(b.bsize, 1, 3))
	s.position = b.position
	ground.add_child(s)


## Decal under a building (the Town Center's garden), drawn on the ground layer.
func add_ground_decal(bname: String, origin: Vector2i, bsize: int) -> Sprite2D:
	var s := Assets.building_sprite(bname)
	s.position = Iso.to_world(Vector2(origin) + Vector2.ONE * ((bsize - 1) * 0.5))
	ground.add_child(s)
	return s


func add_tc_decal(b: Building) -> void:
	if b.look_key() != "":
		return       # the original's picture already holds its shadow and garden
	b.attach_decal(add_ground_decal(String(b.lvl().decal), b.origin, b.bsize))


func _evict(r: Rect2i) -> void:
	for m in mobs:
		if r.has_point(m.cell()):
			var c := free_cell_near(m.cell(), 6)
			m.place(Vector2(c))
			m.path.clear()


func on_building_destroyed(b: Building, quiet := false) -> void:
	b.unload_all()
	b.drop_relics()
	buildings.erase(b)
	b.remove_decal()
	_forget_wall(b)
	if not quiet:
		add_rubble(b)
		Sfx.at("collapse", b.position)
	var r := b.rect()
	for y in r.size.y:
		for x in r.size.x:
			var c := r.position + Vector2i(x, y)
			_set_occ(c, false)
			_set_solid(c, false)
	if quiet:
		b.alive = false
		if b.farmer and is_instance_valid(b.farmer):
			b.farmer.farm = null
		b.queue_free()
	else:
		message.emit("Your %s was destroyed!" % b.def.name)
	recalc_pop()
	if not finished and not buildings.any(func(x: Building) -> bool: return x.kind == "tc"):
		finished = true
		game_over.emit()


## Takes a building down and gives its cost back. Returns a message for the player.
func deconstruct(b: Building) -> String:
	var refund := b.refund_cost()
	for r: String in refund:
		stock[r] += int(refund[r])
	var name := b.title()
	b.set_selected(false)
	on_building_destroyed(b, true)
	return "%s deconstructed: +%s" % [name, Defs.cost_text(refund)]


## Called when something of ours takes a hit from an enemy; the interface pings the minimap.
func report_attack(tile: Vector2) -> void:
	if game_time - _attack_t >= 1.5:
		_attack_t = game_time
		attacked.emit(tile)


func finished_count(kind: String) -> int:
	var n := 0
	for b in buildings:
		if b.kind == kind and b.done:
			n += 1
	return n


func recalc_pop() -> void:
	var cap := 0
	for b in buildings:
		if b.done:
			cap += b.pop_value()
	pop_cap = 200 if Defs.CIV_START.get(civ, {}).get("no_houses", false) else mini(cap, 200)
	var used := 0
	for m in mobs:
		if m.team == 0:
			used += 1
	for b in buildings:
		used += b.queue.size() + b.garrison.size()          # units inside still count
	pop = used


## Name, price (resource names) and training time (seconds) of something a building trains. A soldier's kind is its
## unit id as text; the price follows the player's research.
func unit_info(ukind: String) -> Dictionary:
	if ukind == "villager":
		var v: Dictionary = Defs.UNITS.villager
		return {"name": v.name, "cost": Defs.name_cost(tech.stats(83).cost), "time": float(tech.stats(83).time) / Rules.GAME_SPEED, "uid": 83}
	var id := int(ukind)
	var s := tech.stats(id)
	return {"name": s.name, "cost": Defs.name_cost(s.cost), "time": float(s.time) / Rules.GAME_SPEED, "uid": id}


func try_train(b: Building, ukind: String) -> String:
	var u := unit_info(ukind)
	if not b.done:
		return "Not finished yet"
	if b.queue.size() >= 5:
		return "Queue is full"
	if not (ukind in b.train_list()):
		return "%s cannot be trained here yet" % u.name
	recalc_pop()
	if pop >= pop_cap:
		return "Population limit reached: build Houses"
	if not can_afford(u.cost):
		return "Not enough resources (%s)" % Defs.cost_text(u.cost)
	pay(u.cost)
	b.queue.append(ukind)
	return ""


func spawn_unit(ukind: String, from: Building) -> Mob:
	var r := from.rect()
	if Defs.is_ship(ukind):
		var w := _dock_water_cell(r)
		var ship := make_unit(ukind, 0, Vector2(w))
		if ship is Ship:
			var f := nearest_fish(Vector2(w), 60.0, true)
			if f != null:
				(ship as Ship).order_fish(f)
		recalc_pop()
		Sfx.play("unit_ready")
		return ship
	var c := free_cell_near(Vector2i(r.end.x, r.end.y), 6)
	var m := make_unit(ukind, 0, Vector2(c))
	var out := free_cell_near(c + Vector2i(2, 2), 4)
	if m is Villager:
		m.order_move(out)
	elif m is Soldier:
		m.order_move(out)
	recalc_pop()
	Sfx.play("unit_ready" if m is Villager else "soldier_ready")
	return m


## The open water cell next to a dock where a new ship appears.
func _dock_water_cell(r: Rect2i) -> Vector2i:
	for x in range(r.position.x - 1, r.end.x + 1):
		for y in range(r.position.y - 1, r.end.y + 1):
			var c := Vector2i(x, y)
			if not r.has_point(c) and in_bounds(c) and not wastar.is_point_solid(c):
				return c
	return free_water_near(r.position, 8)


func make_unit(ukind: String, team: int, p: Vector2) -> Mob:
	var m: Mob
	if ukind == "villager" and team == 1:
		var fv := FoeVillager.new()
		fv.setup(self, rng.randf() < 0.55)
		m = fv
		if rival:
			rival.villagers.append(fv)
	elif ukind == "villager":
		var v := Villager.new()
		v.setup(self, rng.randf() < 0.55)
		m = v
	elif ukind == "13":
		var sh := Ship.new()
		sh.setup(self, ukind, team)
		m = sh
	else:
		var s := Soldier.new()
		s.setup(self, ukind, team)
		m = s
	m.place(p)
	add_mob(m)
	return m


func make_animal(akind: String, p: Vector2) -> Animal:
	var a := Animal.new()
	a.setup(self, akind)
	a.place_home(p)
	add_mob(a)
	return a


func add_mob(m: Mob) -> void:
	mobs.append(m)
	entities.add_child(m)


func on_mob_died(m: Mob) -> void:
	mobs.erase(m)
	corpses.append(m)
	if m is Animal and m.food() > 0:
		spawn_carcass(m)
	if m.team == 0:
		recalc_pop()


# ------------------------------------------------------------------ queries
func nearest_point(e: Object, p: Vector2) -> Vector2:
	if e is Building:
		var r: Rect2i = e.rect()
		return Vector2(clampf(p.x, r.position.x - 0.5, r.end.x - 0.5), clampf(p.y, r.position.y - 0.5, r.end.y - 0.5))
	return e.tp


func dist_to(e: Object, p: Vector2) -> float:
	return nearest_point(e, p).distance_to(p)


## Closest living non-player unit (raider or animal) within `r` tiles.
func nearest_hostile(p: Vector2, r: float) -> Mob:
	var best: Mob = null
	var best_d := r
	for m in mobs:
		if m.team != 0 and m.is_threat():
			var d := m.tp.distance_to(p)
			if d < best_d:
				best_d = d
				best = m
	return best


func nearest_player_mob(p: Vector2, r: float) -> Mob:
	var best: Mob = null
	var best_d := r
	for m in mobs:
		if m.team == 0:
			var d := m.tp.distance_to(p)
			if d < best_d:
				best_d = d
				best = m
	return best


func nearest_building(p: Vector2) -> Building:
	var best: Building = null
	var best_d := INF
	for b in buildings:
		if b.alive and b.kind != "farm":
			var d := dist_to(b, p)
			if d < best_d:
				best_d = d
				best = b
	return best


## Closest player unit or building (the raiders' targets).
func nearest_player_thing(p: Vector2, r: float) -> Object:
	var best: Object = nearest_player_mob(p, r)
	var best_d: float = (best.tp.distance_to(p) - 1.0) if best else r
	for b in buildings:
		if b.alive and b.kind != "farm":
			var d := dist_to(b, p)
			if d < best_d:
				best_d = d
				best = b
	return best


## Something of ours is under attack: idle soldiers within reach go after the attacker.
func rally_defenders(attacker: Object, at: Vector2) -> void:
	if not is_instance_valid(attacker) or not attacker.alive or attacker.team == 0:
		return
	for m in mobs:
		if m is Soldier and m.team == 0 and m.order == "idle" and not m.valid(m.target) and m.tp.distance_to(at) < 28.0:
			m.target = attacker


func find_dropoff(kind: String, p: Vector2) -> Building:
	var best: Building = null
	var best_d := INF
	for b in buildings:
		if b.alive and b.is_dropoff(kind):
			var d := dist_to(b, p)
			if d < best_d:
				best_d = d
				best = b
	return best


func fire(from: Vector2, target: Object, dmg: float, shooter: Object, blast := 0.0, atk := {}) -> void:
	Sfx.at("arrow", Iso.to_world(from))
	var p := Projectile.new()
	p.launch(from, nearest_point(target, from), dmg, target, shooter, blast, atk)
	entities.add_child(p)
	projectiles.append(p)


# ------------------------------------------------------------------ generation
func scatter_forests(clear_center: Vector2i, clear_radius: float) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.seed
	noise.frequency = 0.04
	noise.fractal_octaves = 3
	var kind_noise := FastNoiseLite.new()
	kind_noise.seed = rng.seed + 7
	kind_noise.frequency = 0.02
	var items: Array = Assets.man.resources.trees.items
	var oaks: Array[int] = []
	var pines: Array[int] = []
	for i in items.size():
		(oaks if items[i].kind == "oak" else pines).append(i)
	for y in size:
		for x in size:
			var c := Vector2i(x, y)
			if Vector2(c).distance_to(Vector2(clear_center)) < clear_radius or not resource_ok(c):
				continue
			var v := noise.get_noise_2d(x, y)
			var chance := 0.012
			if v > 0.16:
				chance = 0.78
			elif v > 0.08:
				chance = 0.22
			if rng.randf() >= chance:
				continue
			var pool := pines if kind_noise.get_noise_2d(x, y) > 0.05 else oaks
			spawn_res_node("trees", pool[rng.randi() % pool.size()], c)
			tree_count += 1


## A stand of trees around `centre`.
func scatter_stand(centre: Vector2i, count: int, spread: float) -> void:
	var items: Array = Assets.man.resources.trees.items
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 12:
		tries += 1
		var c := centre + Vector2i(roundi(rng.randfn(0.0, spread)), roundi(rng.randfn(0.0, spread)))
		if resource_ok(c):
			spawn_res_node("trees", rng.randi() % items.size(), c)
			tree_count += 1
			placed += 1


## A cluster of mines or bushes around `centre`.
func scatter_clump(rname: String, centre: Vector2i, count: int, spread: float) -> void:
	var items: Array = Assets.man.resources[rname].items
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 12:
		tries += 1
		var c := centre + Vector2i(roundi(rng.randfn(0.0, spread)), roundi(rng.randfn(0.0, spread)))
		if resource_ok(c):
			spawn_res_node(rname, rng.randi() % items.size(), c)
			placed += 1


# ------------------------------------------------------------------ simulation
## Buildings turn see-through where one of our units stands behind them.
func _update_see_through() -> void:
	var spots: Array[Rect2] = []
	var ys: Array[float] = []
	for m in mobs:
		if m.team == 0 and m.alive:
			var r := m.get_rect()
			spots.append(Rect2(m.position + r.position, r.size))
			ys.append(m.position.y)
	for b in buildings:
		if not b.alive or b.kind == "farm":
			continue
		var hide := false
		if not spots.is_empty():
			var r := b.get_rect()
			var br := Rect2(b.position + r.position, r.size)
			for i in spots.size():
				if ys[i] < b.position.y and br.intersects(spots[i]):
					hide = true
					break
		b.set_see_through(hide)


## A frame that took long is written to the log (user://logs/godot.log) with where the time went: for finding freezes.
func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_step(delta)
	var ms := (Time.get_ticks_usec() - t0) / 1000
	if ms > 250:
		print("[slow] frame %d ms at %d s (x%.0f): mobs %d, foes %d, buildings %d, rival %d ms" % [ms, int(game_time), speed, mobs.size(), foes.size(), buildings.size(), _rival_ms])


var _rival_ms := 0


func _step(delta: float) -> void:
	var dt := 0.0 if paused else minf(delta, 0.1) * speed
	game_time += dt
	for m in mobs.duplicate():
		if m.alive:
			m.tick(dt)
	for f in fish_nodes:
		f.tick(dt)
	for i in range(carcasses.size() - 1, -1, -1):
		if not carcasses[i].tick(dt):
			remove_res(carcasses[i])
	_price_t += dt
	if _price_t >= 10.0:                # prices drift back towards 100
		_price_t = 0.0
		for r: String in prices:
			prices[r] = move_toward(prices[r], 100.0, 1.0)
	for b in buildings.duplicate():
		b.tick(dt)
	for b in foes.duplicate():
		b.tick(dt)
	_relic_income(dt)
	if rival:
		var r0 := Time.get_ticks_usec()
		rival.tick(dt)
		_rival_ms = (Time.get_ticks_usec() - r0) / 1000
	for i in range(projectiles.size() - 1, -1, -1):
		var p := projectiles[i]
		p.tick(dt)
		if p.done:
			projectiles.remove_at(i)
			p.queue_free()
	for i in range(corpses.size() - 1, -1, -1):
		if not corpses[i].tick_corpse(dt):
			if corpses[i] is Villager or corpses[i] is Soldier:
				Tombstone.spawn(self, corpses[i].position)
			corpses[i].queue_free()
			corpses.remove_at(i)
	for i in range(tombs.size() - 1, -1, -1):
		if not tombs[i].tick(dt):
			tombs[i].queue_free()
			tombs.remove_at(i)
	director.tick(dt)
	_see_t -= delta
	if _see_t <= 0.0:
		_see_t = 0.12
		_update_see_through()
