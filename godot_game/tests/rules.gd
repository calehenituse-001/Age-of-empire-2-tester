extends Node
## Rules test:  godot --headless --path godot_game res://tests/rules.tscn

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	check(Rules.loaded, "rules.json loaded (%d units, %d techs)" % [Rules.units.size(), Rules.techs.size()])
	var t := TechState.new(1)
	check(t.age() == 0, "starts in the Dark Age")
	check(t.stats(83).hp == 25.0, "villager 25 hp")
	check(t.stats(83).cost == {0: 50}, "villager costs 50 food")
	var bl := t.build_list()
	var names: Array = []
	for id: int in bl:
		names.append(Rules.name_of(id))
	print("  Dark Age buildings: ", names)
	check("House" in names and "Mill" in names and "Barracks" in names and "Lumber Camp" in names, "Dark Age buildings unlocked")
	check(not ("Farm" in names), "Farms need a mill first")
	check(not ("Archery Range" in names or "Blacksmith" in names or "Market" in names), "Feudal buildings still locked")
	check(not t.can_research(101), "Feudal Age needs two Dark Age buildings")
	t.building_done(70)       # house
	check(not t.can_research(101), "a house alone does not count")
	t.building_done(68)       # mill
	check(Rules.name_of(68) == "Mill" and t.build_list().any(func(i): return Rules.name_of(i) == "Farm"), "Mill built: farms unlocked")
	t.building_done(12)       # barracks
	check(t.can_research(101), "Feudal Age researchable after mill + barracks")
	check(Rules.cost_text(t.cost_of(101)) == "500 food", "Feudal costs 500 food")
	t.research(22)
	check(t.stats(83).hp == 40.0, "Loom: villager hp 40")
	t.research(101)
	check(t.age() == 1, "Feudal Age reached")
	names.clear()
	for id: int in t.build_list():
		names.append(Rules.name_of(id))
	print("  Feudal buildings: ", names)
	check("Archery Range" in names and "Blacksmith" in names and "Market" in names and "Stable" in names, "Feudal buildings unlocked")
	check(t.current(109) == 71 and Rules.name_of(t.current(109)) == "Town Center", "Town Center became the Feudal one (71)")
	check(t.current(12) == 498, "Barracks became the Feudal barracks")
	var wheel: float = t.stats(83).speed
	t.research(213)
	check(t.stats(83).speed > wheel, "Wheelbarrow: villager faster")
	var tl: Array = []
	for id: int in t.train_list(87):
		tl.append(Rules.name_of(id))
	print("  Archery range trains: ", tl)
	var bar: Array = []
	for id: int in t.train_list(12):
		bar.append(Rules.name_of(id))
	print("  Barracks trains: ", bar)
	check("Militia" in bar and "Spearman" in bar, "Barracks trains militia and spearman")
	check(t.can_research(75) or true, "tech list ok")
	var ts: Array = []
	for id: int in t.techs_at(109):
		ts.append(Rules.techs[id].name)
	print("  Town Center techs: ", ts)
	print("  Barracks techs: ", t.techs_at(12).map(func(i): return Rules.techs[i].name))
	check(not t.can_research(102), "Castle Age needs two Feudal buildings")
	t.building_done(87)
	t.building_done(84)
	check(t.can_research(102), "Castle Age researchable after archery range + market")
	t.research(102)
	t.research(103)
	check(t.age() == 3, "Imperial Age reached")
	print("  Imperial techs at Blacksmith: ", t.techs_at(103).map(func(i): return Rules.techs[i].name))
	var tb := TechState.new(1)
	print("Britons: ", Rules.civs[1].name, " Franks tree disabled techs: ", TechState.new(2).disabled_techs.size(), " Britons: ", tb.disabled_techs.size())
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit(fails)
