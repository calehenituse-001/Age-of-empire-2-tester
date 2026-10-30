extends Node
## Civilizations test:  godot --headless --path godot_game res://tests/civs.tscn

const UNIQUE := ["Longbowman", "Throwing Axeman", "Huskarl", "Teutonic Knight", "Samurai", "Chu Ko Nu", "Cataphract", "War Elephant",
	"Mameluke", "Janissary", "Berserk", "Mangudai", "Woad Raider", "Conquistador", "Jaguar Warrior", "Plumed Archer", "Tarkan", "War Wagon"]
var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	check(Rules.raw.civ_info.size() == 18, "18 civilizations")
	for c in range(1, 19):
		var nm := Defs.civ_name(c)
		var t := TechState.new(c)
		t.building_done(70)
		t.building_done(68)
		t.building_done(12)
		t.research(101)
		t.building_done(87)
		t.building_done(84)
		t.research(102)
		t.building_done(82)                    # a Castle stands: its unique unit is unlocked
		var cast: Array = []
		var missing: Array = []
		for id: int in t.train_list(82) + t.train_list(12) + t.train_list(87) + t.train_list(101) + t.train_list(49) + t.train_list(104):
			if id in Defs.NO_TRAIN:
				continue
			cast.append(Rules.name_of(id))
			if not Assets.man.anims.has("u%d_idle_blue" % id) or not Assets.man.anims.has("u%d_walk_blue" % id):
				missing.append(Rules.name_of(id))
		var castle_units: Array = []
		for id: int in t.train_list(82):
			if not id in Defs.NO_TRAIN:
				castle_units.append(Rules.name_of(id))
		check(UNIQUE[c - 1] in castle_units, "%s: the Castle trains the %s (%s)" % [nm, UNIQUE[c - 1], ", ".join(castle_units)])
		check(missing.is_empty(), "%s: every unit it can train has sprites%s" % [nm, "" if missing.is_empty() else " (missing: %s)" % str(missing)])
		var style := int(Rules.raw.civ_info[c - 1].style)
		t.research(103)
		var look := Assets.look_key(t.current(70), style)
		var tc := Assets.look_key(t.current(109), style)
		check(look != "" and tc != "", "%s: houses and Town Center have pictures in style %d (%s, %s)" % [nm, style, look, tc])
		check(t.build_list().size() >= 8, "%s: %d buildings to build" % [nm, t.build_list().size()])
	# the starting differences
	check(Defs.CIV_START[6].villagers == 3 and Defs.CIV_START[17].no_houses, "start modifiers: Chinese +3 villagers, Huns need no houses")
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit(fails)
