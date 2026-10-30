extends Node
## godot --headless --path godot_game res://tests/extract.tscn
##   GAME = install folder, OUT = folder to write into, STAGE = base | units, ONLY = from:to task range of the unit stage

func _ready() -> void:
	var game := OS.get_environment("GAME") if OS.get_environment("GAME") != "" else "/home/j3rry/AOE"
	var out := OS.get_environment("OUT")
	DirAccess.make_dir_recursive_absolute(out)
	var t := Time.get_ticks_msec()
	var say := func(s: String) -> void: print("[%d s] %s" % [(Time.get_ticks_msec() - t) / 1000, s])
	if OS.get_environment("STAGE") == "units":
		var ref := OS.get_environment("REF")      # a folder holding data/rules.json and data/graphics.json
		var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ref + "/data/rules.json"))
		var gfx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ref + "/data/graphics.json"))
		var ux := UnitExtract.new(game, out, rules, gfx)
		var from := 0
		var to := ux.tasks.size()
		if OS.get_environment("ONLY") != "":
			from = int(OS.get_environment("ONLY").split(":")[0])
			to = mini(to, int(OS.get_environment("ONLY").split(":")[1]))
		say.call("%d tasks" % ux.tasks.size())
		for i in range(from, to):
			ux.run_task(i)
			if i % 25 == 0:
				say.call("%d: %s" % [i, ux.describe(i)])
		FileAccess.open(out + "/units.json", FileAccess.WRITE).store_string(JSON.stringify(ux.man))
	elif OS.get_environment("STAGE") == "terrain":
		var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("REF") + "/data/rules.json"))
		var man := TerrainExtract.new(game, out, rules, say).run()
		FileAccess.open(out + "/terrain.json", FileAccess.WRITE).store_string(JSON.stringify(man))
	elif OS.get_environment("STAGE") == "sound":
		var d := DatReader.new().read(Inflate.raw(FileAccess.get_file_as_bytes(game + "/Data/empires2_x1_p1.dat"), 5649567))
		print("sounds written: ", SoundExtract.run(game, out, d, say))
	else:
		var man := BaseSprites.new(game, out, say).run()
		FileAccess.open(out + "/manifest.json", FileAccess.WRITE).store_string(JSON.stringify(man))
	say.call("done")
	print("RESULT: ALL PASS")
	get_tree().quit()
