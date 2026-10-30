class_name BaseSprites
extends RefCounted
## The hand-picked sprites: terrain tiles for the farm fields, the first buildings, walls, markers, trees, resources, villagers,
## soldiers and animals, written as PNG atlases plus manifest.json. A port of tools/extract_aoe_godot.py (sounds are in SoundExtract).

const RED := 32                         # player-colour palette offset that gives red (blue is 0)
const BUILDING_SHADOW := [0, 206]       # palette indices buildings use for their baked-in shadow

# name: [[slp id male, female], seconds per frame]
const VILLAGER_ANIMS := {
	"walk": [[1484, 1392], 0.07], "stand": [[1479, 1388], 0.25], "carry_wood": [[1536, 1883], 0.07],
	"carry_ore": [[1552, 1879], 0.07], "carry_food": [[2592, 4602], 0.07], "chop": [[1545, 1884], 0.10],
	"mine": [[1560, 1880], 0.10], "forage": [[2589, 2573], 0.20], "farm": [[1512, 1876], 0.13],
	"build": [[1496, 1874], 0.07], "die": [[1476, 1385], 0.10],
}
const FIGHTERS := {
	"militia": {"walk": [1048, 0.09], "attack": [1038, 0.16], "stand": [1044, 0.25], "die": [1041, 0.10]},
	"archer": {"walk": [12, 0.07], "attack": [2, 0.07], "stand": [8, 0.20], "die": [5, 0.10]},
	"twohand": {"walk": [1185, 0.09], "attack": [1175, 0.12], "stand": [1181, 0.25], "die": [1178, 0.10]},
	"crossbow": {"walk": [1654, 0.07], "attack": [1644, 0.10], "stand": [1650, 0.20], "die": [1647, 0.10]},
	"spearman": {"walk": [997, 0.07], "attack": [987, 0.10], "stand": [993, 0.25], "die": [990, 0.10]},
	"knight": {"walk": [673, 0.11], "attack": [663, 0.135], "stand": [669, 0.20], "die": [666, 0.185]},
}
const RED_FIGHTERS := ["militia", "archer", "twohand", "crossbow"]
const BLUE_FIGHTERS := ["militia", "archer", "twohand", "crossbow", "spearman", "knight"]
const ANIMALS := {
	"wolf": {"walk": [1640, 0.09], "run": [1636, 0.07], "attack": [1629, 0.09], "stand": [1635, 0.10], "die": [1632, 0.10]},
	"boar": {"walk": [2559, 0.10], "run": [3577, 0.09], "attack": [2555, 0.10], "stand": [2557, 0.12], "die": [2556, 0.10]},
}
const BUILDINGS := {
	"tc": [3596, 3595, 4612, 4611, 3594, 4610, 891], "tc2": [3605, 3601, 4621, 4617, 3597, 4613, 900],
	"tc3": [3617, 3613, 4633, 4629, 3609, 4625, 912], "tc4": [3473, 3469, 4645, 4641, 3465, 4637, 924],
	"tc_plaza1": [889], "tc_plaza2": [892], "tc_plaza3": [904], "tc_plaza4": [916, 920],
	"house": [2232], "barracks": [130], "mill": [738], "lumber_camp": [3504], "mining_camp": [3492],
	"tower": [2652], "tower2": [2664], "tower3": [2538], "tower4": [2546], "rubble1": [928], "rubble2": [929], "rubble3": [930],
}
const WALL_SLP := 2098
const TREE_SETS := [["foak_nn", "pal_2", [0, 1, 2, 4, 9, 10, 11, 12, 13], "oak"], ["fpin_nn", "pal_4", [1, 2, 3, 4, 7], "pine"]]

var game := ""
var out := ""
var graphics: Drs
var interfac: Drs
var terrain: Drs
var pal: PackedByteArray
var man := {"terrain": {}, "buildings": {}, "resources": {}, "anims": {}}
var step: Callable                       # called with (text) before each part, may block (pause)


func _init(game_dir: String, out_dir: String, step_cb: Callable) -> void:
	game = game_dir
	out = out_dir
	step = step_cb


func _slp(sid: int, lut: PackedInt32Array) -> Array:
	return Slp.decode(graphics.get_file("slp", sid), lut)


func run() -> Dictionary:
	var data := game.path_join("Data")
	graphics = Drs.open(data.path_join("graphics.drs"))
	interfac = Drs.open(data.path_join("interfac.drs"))
	terrain = Drs.open(data.path_join("terrain.drs"))
	pal = Slp.read_pal(interfac.get_file("bina", 50500).get_string_from_ascii())
	var plain := Slp.lut(pal)
	var shade := Slp.lut(pal, 0, BUILDING_SHADOW)
	var red := Slp.lut(pal, RED)

	step.call("Terrain tiles")
	for t: Array in [["grass", 15008, 10], ["dirt", 15000, 10], ["farm_fresh", 15021, 3], ["farm_grown", 15023, 3]]:
		var frames := Slp.decode(terrain.get_file("slp", t[1]), plain)
		man.terrain[t[0]] = _terrain_sheet(frames, t[2], out.path_join("terrain_%s.png" % t[0]))

	step.call("Buildings")
	for name: String in BUILDINGS:
		var parts := []
		for sid: int in BUILDINGS[name]:
			parts.append(_slp(sid, shade)[0])
		var x0 := 0
		var y0 := 0
		var x1 := 0
		var y1 := 0
		for i in parts.size():
			var f: Dictionary = parts[i]
			x0 = -f.hx if i == 0 else mini(x0, -f.hx)
			y0 = -f.hy if i == 0 else mini(y0, -f.hy)
			x1 = -f.hx + f.w if i == 0 else maxi(x1, -f.hx + f.w)
			y1 = -f.hy + f.h if i == 0 else maxi(y1, -f.hy + f.h)
		var w := x1 - x0
		var h := y1 - y0
		var img := Sheets.blank(w, h)
		for f: Dictionary in parts:
			Sheets.over(img, f.img, -f.hx - x0, -f.hy - y0)
		Sheets.save(img, out.path_join("b_%s.png" % name))
		man.buildings[name] = {"file": "b_%s.png" % name, "w": w, "h": h, "hx": -x0, "hy": -y0}

	step.call("Walls and markers")
	man["walls"] = {"file": "b_wall.png", "items": Sheets.strip(_slp(WALL_SLP, shade), out.path_join("b_wall.png"))}
	man["markers"] = _markers()

	step.call("Fire and construction sites")
	for f: Array in [["fire_s", 362], ["fire_m", 363], ["fire_l", 364]]:
		var info := Sheets.animation(_slp(f[1], plain), 1, out.path_join("a_%s.png" % f[0]))
		info["file"] = "a_%s.png" % f[0]
		info["dur"] = 0.05
		man.anims[f[0]] = info
	man["foundations"] = {}
	var n := 1
	for sid: int in [236, 237, 238, 239]:
		man.foundations[str(n)] = {"file": "found_%d.png" % n, "items": Sheets.strip(_slp(sid, shade), out.path_join("found_%d.png" % n))}
		n += 1

	step.call("Trees, stone, gold and berries")
	var tree_frames := []
	var kinds := []
	for ts: Array in TREE_SETS:
		var tpal := Slp.read_pal(FileAccess.get_file_as_string(data.path_join(ts[1] + ".pal")))
		var frames := Slp.decode(FileAccess.get_file_as_bytes(data.path_join("Slp").path_join(ts[0] + ".slp")), Slp.lut(tpal))
		for k: int in ts[2]:
			tree_frames.append(frames[k])
			kinds.append(ts[3])
	var items := Sheets.strip(tree_frames, out.path_join("r_trees.png"))
	for i in items.size():
		items[i]["kind"] = kinds[i]
	man.resources["trees"] = {"file": "r_trees.png", "items": items}
	for r: Array in [["stone", 1034], ["berries", 2560]]:
		man.resources[r[0]] = {"file": "r_%s.png" % r[0], "items": Sheets.strip(_slp(r[1], plain), out.path_join("r_%s.png" % r[0]))}
	man.resources["gold"] = _gold(_slp(1034, plain), _slp(2561, plain))

	step.call("Villagers")
	for gi in 2:
		var gender := "m" if gi == 0 else "f"
		for name: String in VILLAGER_ANIMS:
			var a: Array = VILLAGER_ANIMS[name]
			var info := Sheets.animation(_slp(a[0][gi], plain), 5, out.path_join("a_v%s_%s.png" % [gender, name]))
			info["file"] = "a_v%s_%s.png" % [gender, name]
			info["dur"] = a[1]
			man.anims["v%s_%s" % [gender, name]] = info

	step.call("Soldiers")
	for kind: String in FIGHTERS:
		for c: Array in [["blue", plain, BLUE_FIGHTERS], ["red", red, RED_FIGHTERS]]:
			if not (kind in c[2]):
				continue
			for name: String in FIGHTERS[kind]:
				var a: Array = FIGHTERS[kind][name]
				var key := "%s_%s_%s" % [kind, c[0], name]
				var info := Sheets.animation(_slp(a[0], c[1]), 5, out.path_join("a_%s.png" % key))
				info["file"] = "a_%s.png" % key
				info["dur"] = a[1]
				man.anims[key] = info

	step.call("Animals")
	for kind: String in ANIMALS:
		for name: String in ANIMALS[kind]:
			var a: Array = ANIMALS[kind][name]
			var key := "%s_%s" % [kind, name]
			var info := Sheets.animation(_slp(a[0], plain), 5, out.path_join("a_%s.png" % key))
			info["file"] = "a_%s.png" % key
			info["dur"] = a[1]
			man.anims[key] = info
	return man


func _terrain_sheet(frames: Array, cols: int, path: String) -> Dictionary:
	var tw: int = frames[0].w
	var th: int = frames[0].h
	var cw := tw + 2 * Sheets.PAD
	var ch := th + 2 * Sheets.PAD
	var rows := (frames.size() + cols - 1) / cols
	var sheet := Sheets.blank(cols * cw, rows * ch)
	for i in frames.size():
		Sheets.paste(sheet, frames[i].img, (i % cols) * cw + Sheets.PAD, (i / cols) * ch + Sheets.PAD)
	Sheets.save(sheet, path)
	return {"file": path.get_file(), "cols": cols, "frames": frames.size(), "tw": tw, "th": th, "cw": cw, "ch": ch, "pad": Sheets.PAD}


## The marks shown where units are sent: `move` is the four arrows closing in on a spot (graphic MOVETO; the game's picture is red,
## saved with red and green swapped), `target` keeps the red original, `cursor` is the mouse cursor's arrow over ripples.
func _markers() -> Dictionary:
	var swapped := pal.duplicate()
	for i in 256:
		var r := swapped[i * 3]
		swapped[i * 3] = swapped[i * 3 + 1]
		swapped[i * 3 + 1] = r
	var moves := []
	for f: Dictionary in _slp(3405, Slp.lut(pal)):
		if f.w > 1:
			moves.append(f)
	var moves_sw := []
	for f: Dictionary in _slp(3405, Slp.lut(swapped)):
		if f.w > 1:
			moves_sw.append(f)
	var move := Sheets.strip(moves_sw, out.path_join("a_marker_move.png"))
	var target := Sheets.strip(moves, out.path_join("a_marker_target.png"))
	var cur: Array = Slp.decode(interfac.get_file("slp", 51000), Slp.lut(pal))
	var cursor := Sheets.strip([cur[17]], out.path_join("a_marker_cursor.png"))
	return {"move": {"file": "a_marker_move.png", "items": move, "spf": 0.125}, "target": {"file": "a_marker_target.png", "items": target, "spf": 0.125},
		"cursor": {"file": "a_marker_cursor.png", "items": cursor}}


## The game draws gold as bare nuggets; give them a golden rock body so a mine reads at a glance.
func _gold(stone_frames: Array, fleck_frames: Array) -> Dictionary:
	var made := []
	for k in mini(stone_frames.size(), fleck_frames.size()):
		var stone: Dictionary = stone_frames[k]
		var fleck: Dictionary = fleck_frames[k]
		var body: Image = stone.img.duplicate()
		var d := body.get_data()
		for i in range(0, d.size(), 4):
			var a := d[i + 3]
			if a != 0:
				var lum := (d[i] + d[i + 1] + d[i + 2]) / 3.0 / 255.0
				d[i] = int(70 + 175 * lum)
				d[i + 1] = int(48 + 150 * lum)
				d[i + 2] = int(8 + 40 * lum)
		body = Image.create_from_data(body.get_width(), body.get_height(), false, Image.FORMAT_RGBA8, d)
		var nug: Image = fleck.img
		var w := maxi(body.get_width(), nug.get_width()) + 6
		var h := maxi(body.get_height(), nug.get_height()) + 8
		var im := Sheets.blank(w, h)
		var bx := (w - body.get_width()) / 2
		var by := h - body.get_height() - 2
		Sheets.over(im, body, bx, by)
		var nx := bx + floori((body.get_width() - nug.get_width()) / 2.0)
		var ny := by + body.get_height() - nug.get_height() - 2
		Sheets.over(im, nug, nx, ny)
		made.append({"img": im, "hx": bx + stone.hx, "hy": by + stone.hy})
	var total := 0
	var hmax := 0
	for m: Dictionary in made:
		total += m.img.get_width() + 2 * Sheets.PAD
		hmax = maxi(hmax, m.img.get_height())
	hmax += 2 * Sheets.PAD
	var sheet := Sheets.blank(total, hmax)
	var items := []
	var x := 0
	for m: Dictionary in made:
		Sheets.paste(sheet, m.img, x + Sheets.PAD, Sheets.PAD)
		items.append({"x": x + Sheets.PAD, "y": Sheets.PAD, "w": m.img.get_width(), "h": m.img.get_height(), "hx": m.hx, "hy": m.hy})
		x += m.img.get_width() + 2 * Sheets.PAD
	Sheets.save(sheet, out.path_join("r_gold.png"))
	return {"file": "r_gold.png", "items": items}
