extends Node
## godot --headless --path godot_game res://tests/inflate.tscn  (needs the game's .dat; GAME env var = the install folder)


func _ready() -> void:
	var game := OS.get_environment("GAME") if OS.get_environment("GAME") != "" else "/home/j3rry/AOE"
	var raw := FileAccess.get_file_as_bytes(game + "/Data/empires2_x1_p1.dat")
	var t := Time.get_ticks_msec()
	var out := Inflate.raw(raw)
	print("inflated %d -> %d bytes in %d ms" % [raw.size(), out.size(), Time.get_ticks_msec() - t])
	var ok := out.size() == 5649567 and out.slice(0, 8).get_string_from_ascii() == "VER 5.7"
	print("md5 ", out.slice(0, out.size()).size(), " ", _hash(out))
	print("RESULT: ", "ALL PASS" if ok else "FAILED")
	get_tree().quit()


func _hash(b: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(b)
	return h.finish().hex_encode()
