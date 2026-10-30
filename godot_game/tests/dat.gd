extends Node
## godot --headless --path godot_game res://tests/dat.tscn   (GAME = the install folder; OUT = file to write the parsed dat to)


func _ready() -> void:
	var game := OS.get_environment("GAME") if OS.get_environment("GAME") != "" else "/home/j3rry/AOE"
	var t := Time.get_ticks_msec()
	var raw := Inflate.raw(FileAccess.get_file_as_bytes(game + "/Data/empires2_x1_p1.dat"), 5649567)
	print("inflate %d ms" % (Time.get_ticks_msec() - t))
	t = Time.get_ticks_msec()
	var r := DatReader.new()
	r._trace = OS.get_environment("TRACE") != ""
	var d := r.read(raw)
	print("parse %d ms, keys %s" % [Time.get_ticks_msec() - t, d.keys()])
	var out := OS.get_environment("OUT")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(d))
	print("RESULT: ", "ALL PASS" if d.has("civs") else "FAILED")
	get_tree().quit()
