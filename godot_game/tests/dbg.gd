extends Node
func _ready() -> void:
	var ref := "res://assets/aoe"
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ref + "/data/rules.json"))
	var gfx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ref + "/data/graphics.json"))
	var ux := UnitExtract.new("/home/j3rry/AOE", "/tmp/x", rules, gfx)
	var u: Dictionary = ux.U["71"]
	print(u.gfx, u.get("annex"), u.get("head"), ux.age_of.get(71))
	var ps := ux._parts(71)
	var l := []
	for p in ps:
		l.append([p.layer, p.x, p.y])
	print(ps.size(), l)
	for p in ps:
		var f: Dictionary = ux._slp(p.gid, ux.lut_shade, 1)[0]
		print(p.layer, " ", p.x, " ", p.y, " ", f.w, " ", f.h, " ", f.hx, " ", f.hy, " gid ", p.gid)
	get_tree().quit()
