extends Node
var failures := 0
var checks := 0

class ProbeMap extends GameMap:
	var spawned := 0
	var finished_id := -1
	func unit_info(_kind: String) -> Dictionary:
		return {"name": "fixture", "time": 20.0, "cost": {"food": 50}, "uid": 74}
	func spawn_unit(_kind: String, _from: Building) -> Mob:
		spawned += 1
		return null
	func finish_research(id: int) -> void:
		finished_id = id

class ProbeBuilding extends Building:
	func _update_visual() -> void: pass
	func _make_site() -> void: pass
	func _make_foundation() -> void: pass
	func _make_progress() -> void: pass
	func train_list() -> Array: return ["74"]

class ProbeFoe extends FoeBuilding:
	func _update_visual() -> void: pass

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var c := CheatPolicy.new()
	c.configure({})
	c.offline = true
	check(not c.values.values().has(true), "all flags default OFF")
	for resource in ["food", "wood", "gold", "stone"]:
		c.configure({resource: true})
		var stock := {resource: 10}
		check(c.can_afford(stock, {resource: 500}), resource + " human affordability")
		var receipt := c.spend(stock, {resource: 500})
		check(int(stock[resource]) == 10 and int(receipt[resource]) == 0, resource + " retains real balance")
		check(not c.can_afford(stock, {resource: 500}, 1), resource + " enemy normal")
		check(not c.can_afford(stock, {resource: 500}, 2), resource + " other owner normal")
		c.values[resource] = false
		check(not c.can_afford(stock, {resource: 500}), resource + " OFF restores costs")
	c.configure({"food": true, "resource_multiplier": true, "resource_factor": 25})
	c.safe_mode = true
	check(not c.enabled("food"), "Safe Mode blocks cheats")
	c.safe_mode = false
	c.offline = false
	check(not c.enabled("food"), "network sessions blocked")
	c.offline = true
	c.session_check = func() -> bool: return false
	check(not c.enabled("food"), "live multiplayer guard rechecked")
	c.session_check = Callable()
	check(c.income(4) == 100 and c.income(4, 1) == 4, "income multiplier is owner scoped")
	c.configure({"food": "true", "resource_factor": 999, "population_limit": 999999})
	check(not c.enabled("food") and c.values.resource_factor == 2 and c.values.population_limit == 1000, "malformed config validated")
	Rules.units.clear()
	Rules.techs.clear()
	Rules.effects.clear()
	Rules.civs = [{"tech_tree": -1}, {"tech_tree": -1}]
	var map := ProbeMap.new()
	map.stock = {"food": 0, "wood": 0, "gold": 0, "stone": 0}
	AppRuntime.cheats.configure({"free_build": true, "wood": true})
	check(map.can_afford({"wood": 200, "stone": 100}, "build"), "construction cost hook")
	check(not map.can_afford({"gold": 100}, "research"), "research cost is independent")
	check(map.pay({"wood": 200, "stone": 100}, "build") == {"wood": 0, "stone": 0}, "actual payment receipt")
	var enemy := Rival.new()
	enemy.stock = {"food": 100, "wood": 100, "gold": 100, "stone": 100}
	enemy._pay({"wood": 50})
	check(enemy.stock.wood == 50, "real rival transaction untouched")
	var b := ProbeBuilding.new()
	b.map = map
	b.kind = "house"
	b.def = {"name": "fixture", "pop": 5, "cost": {"wood": 200}}
	b.work_needed = 100
	b.max_hp = 100
	b.hp = 10
	map.buildings.append(b)
	var foe := ProbeFoe.new()
	foe.map = map
	foe.def = b.def.duplicate(true)
	foe.work_needed = 100
	foe.max_hp = 100
	foe.team = 1
	AppRuntime.cheats.configure({"build_multiplier": true, "build_factor": 10})
	b.add_work(1)
	foe.add_work(1)
	check(b.work == 10 and foe.work == 1, "real building progress excludes AI")
	AppRuntime.cheats.configure({"instant_build": true})
	b.add_work(0)
	check(not b.done, "paused construction remains paused")
	b.add_work(0.01)
	check(b.done and b.hp == 100, "instant construction finishes real building")
	b.cost_tracked = true
	b.paid_cost = {"wood": 0}
	AppRuntime.cheats.configure({})
	check(int(b.refund_cost().wood) == 0, "free construction cannot create refund windfall")
	AppRuntime.cheats.configure({"instant_train": true, "food": true})
	check(map.try_train(b, "74") == "", "real human training queue accepts free resource")
	b.tick(0.01)
	check(map.spawned == 1 and b.queue.is_empty() and b.paid_queue.is_empty(), "instant training consumes queued unit and receipt")
	AppRuntime.cheats.configure({"train_multiplier": true, "train_factor": 5, "food": true})
	map.try_train(b, "74")
	b.tick(1)
	check(b.qt == 5, "training multiplier hook")
	b.queue.clear()
	b.paid_queue.clear()
	Rules.techs[10001] = {"time": 60, "effect": 10001, "cost": [], "req": [], "nreq": 0}
	Rules.effects[10001] = [[3, 74, 75, 0, 0]]
	b.res_tech = 10001
	b.res_t = 0
	AppRuntime.cheats.configure({"instant_research": true})
	b._tick_research(0.01)
	check(b.res_tech == 10001, "instant research independent of unit upgrade")
	AppRuntime.cheats.configure({"instant_upgrade": true})
	b._tick_research(0.01)
	check(map.finished_id == 10001 and b.res_tech == -1, "instant unit upgrade applies real technology")
	Rules.effects[10001] = []
	b.res_tech = 10001
	AppRuntime.cheats.configure({"instant_research": true})
	b._tick_research(0.01)
	check(b.res_tech == -1, "instant normal research hook")
	AppRuntime.cheats.configure({"population_override": true, "population_limit": 500})
	map.recalc_pop()
	check(map.pop_cap == 500, "independent population override")
	AppRuntime.cheats.configure({})
	map.recalc_pop()
	check(map.pop_cap == 5, "population returns to building-derived limit")
	var at30 := 0.0
	var at60 := 0.0
	for i in 30: at30 = c.advance("train", at30, 100, 1.0 / 30)
	for i in 60: at60 = c.advance("train", at60, 100, 1.0 / 60)
	check(is_equal_approx(at30, at60), "progress depends on elapsed time rather than frame count")
	_test_mod(map)
	map.buildings.clear()
	b.free()
	foe.free()
	enemy.free()
	map.free()
	print("LAUNCHER_TESTS checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _test_mod(map: ProbeMap) -> void:
	var dir := OS.get_environment("AOE_TEST_MODS")
	var registry := ModRegistry.new()
	var prepared := registry.prepare(dir, ["npc.modern-era"])
	check(prepared, "real sample package loads: " + registry.error)
	if not prepared:
		return
	check(registry.buildings.size() == 1 and registry.textures.size() == 1, "building and sprite declared")
	var original := {"id": 562, "name": "base", "hp": 100, "type": 80, "loc": 118, "enabled": true, "time": 20, "radius": [1, 1], "atk": [], "arm": [], "cost": [[1, 100]], "research_id": -1}
	Rules.units = {562: original.duplicate(true)}
	Rules.techs.clear()
	Rules.effects.clear()
	check(registry.apply_rules(Rules), "registry adapter registers new building")
	check(Rules.units[562] == original, "original definition remains unchanged")
	check(Rules.units.has(900001) and int(Rules.units[900001].hp) == 900, "new ID and stats exist in real registry")
	check(Defs.BUILDINGS.modern_supply_depot.pop == 10, "population behavior registered")
	map.tech = TechState.new(1)
	check(900001 in map.tech.build_list(), "new content participates in player technology state")
	check(Defs.lock_reason(map.tech, "modern_supply_depot") == "", "new building is constructible")
	var depot := ProbeBuilding.new()
	depot.map = map
	depot.kind = "modern_supply_depot"
	depot.def = Defs.BUILDINGS.modern_supply_depot
	depot.work_needed = 40
	depot.max_hp = 900
	map.buildings.append(depot)
	depot.add_work(40)
	check(depot.done and depot.hp == 900, "sample completes actual construction")
	check(depot.is_dropoff("wood") and depot.is_dropoff("food"), "sample accepts resource delivery")
	check(map.pop_cap == 15, "sample affects actual population capacity")
	check(registry.fingerprint.begins_with("mods-"), "content-hashed mod save profile")
	var old := AppRuntime.mods
	AppRuntime.mods = registry
	_test_save(map)
	AppRuntime.mods = old
	var vanilla := ModRegistry.new()
	check(vanilla.prepare(dir, []) and vanilla.fingerprint == "vanilla", "disabled selection returns to vanilla profile")
	check(not vanilla.prepare(dir, ["../escape"]), "runtime rejects traversal")
	map.buildings.erase(depot)
	depot.free()

func _test_save(map: ProbeMap) -> void:
	var main := Main.new()
	main.map = map
	main.cam = RtsCamera.new()
	map.director = Director.new()
	var path := AppRuntime.save_path("test.json")
	check(SaveGame.write(path, main), "atomic modded save writes")
	var saved := SaveGame.read(path)
	check(not saved.is_empty(), "same mod fingerprint can read save")
	check(saved.get("buildings", []).any(func(b: Dictionary) -> bool: return b.k == "modern_supply_depot"), "save includes genuine sample building")
	check(SaveGame.write(path, main) and FileAccess.file_exists(path + ".previous"), "previous save backup retained")
	var registry := AppRuntime.mods
	AppRuntime.mods = ModRegistry.new()
	check(SaveGame.read(path).is_empty(), "vanilla rejects modded save")
	AppRuntime.mods = registry
	map.director.free()
	map.director = null
	main.cam.free()
	main.free()
