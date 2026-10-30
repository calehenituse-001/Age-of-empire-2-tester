extends Node
## godot --headless --path godot_game res://tests/rulesbuild.tscn   (GAME = install folder, OUT = folder to write rules.json and graphics.json into)


func _ready() -> void:
	var game := OS.get_environment("GAME") if OS.get_environment("GAME") != "" else "/home/j3rry/AOE"
	var t := Time.get_ticks_msec()
	var d := DatReader.new().read(Inflate.raw(FileAccess.get_file_as_bytes(game + "/Data/empires2_x1_p1.dat"), 5649567))
	var s := PeStrings.read_all(game)
	print("dat + %d strings in %d ms" % [s.size(), Time.get_ticks_msec() - t])
	t = Time.get_ticks_msec()
	var out := RulesBuilder.new().build(d, s)
	print("built in %d ms" % (Time.get_ticks_msec() - t))
	var dir := OS.get_environment("OUT")
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
		FileAccess.open(dir + "/rules.json", FileAccess.WRITE).store_string(JSON.stringify(out.rules))
		FileAccess.open(dir + "/graphics.json", FileAccess.WRITE).store_string(JSON.stringify(out.graphics))
	print("RESULT: ", "ALL PASS" if out.rules.units.size() > 100 else "FAILED")
	get_tree().quit()
