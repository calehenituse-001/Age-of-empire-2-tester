class_name TerrainExtract
extends RefCounted
## The terrain tiles and the blending masks (for shorelines and other terrain edges): terrain/t<id>.png (100 tiles of 97x49 per
## terrain, a 10x10 pattern), terrain/blend.png (9 modes x 31 masks in the alpha channel = how much of the neighbouring terrain
## shows), terrain/overlay.png (pre-masked neighbour tiles) and terrain.json. A port of tools/extract_terrain.py.

const TW := 97
const TH := 49
const PAD := 1
const WANT := {0: "grass", 1: "water", 2: "beach", 3: "dirt3", 4: "shallows", 6: "dirt", 9: "grass3", 10: "forest", 11: "dirt2",
	12: "grass2", 13: "palm", 22: "water2", 23: "water3"}
# blend mode of the tile (row) and of the neighbour laid over it (column); the same table as scripts/terrain_blend.gd
const LOOK := [[2, 3, 2, 1, 1, 6, 5, 4], [3, 3, 3, 1, 1, 6, 5, 4], [2, 3, 2, 1, 1, 6, 1, 4], [1, 1, 1, 0, 7, 6, 5, 4],
	[1, 1, 1, 7, 7, 6, 5, 4], [6, 6, 6, 6, 6, 6, 5, 4], [5, 5, 1, 5, 5, 5, 5, 4], [4, 3, 4, 4, 4, 4, 4, 4]]
const USED := [0, 12, 9, 2, 4, 1]       # the three grasses, beach, shallows, water: the terrains the generated maps use
const VARIANTS := [0, 27, 41, 66]       # tile patterns used for blended tiles (keeps the atlas small)

var game := ""
var out := ""
var rules: Dictionary
var step: Callable


func _init(game_dir: String, out_dir: String, rules_: Dictionary, step_cb: Callable) -> void:
	game = game_dir
	out = out_dir
	rules = rules_
	step = step_cb


func run() -> Dictionary:
	var terr := {}
	for t: Dictionary in rules.terrains:
		terr[int(t.id)] = t
	var data := game.path_join("Data")
	var drs := Drs.open(data.path_join("terrain.drs"))
	var interfac := Drs.open(data.path_join("interfac.drs"))
	var pal := Slp.read_pal(interfac.get_file("bina", 50500).get_string_from_ascii())
	var lut := Slp.lut(pal)
	DirAccess.make_dir_recursive_absolute(out.path_join("terrain"))
	var man := {"tiles": {}, "blend": {}}
	var cw := TW + 2 * PAD
	var ch := TH + 2 * PAD
	step.call("Terrain tiles")
	var sheets := {}
	for tid: int in WANT:
		var t: Dictionary = terr[tid]
		var frames := Slp.decode(drs.get_file("slp", int(t.slp_id)), lut)
		var sheet := Sheets.blank(10 * cw, 10 * ch)
		for i in mini(frames.size(), 100):
			Sheets.paste(sheet, frames[i].img, (i % 10) * cw + PAD, (i / 10) * ch + PAD)
		Sheets.save(sheet, out.path_join("terrain/t%d.png" % tid))
		sheets[tid] = sheet
		man.tiles[str(tid)] = {"file": "terrain/t%d.png" % tid, "name": WANT[tid], "cols": 10, "frames": frames.size(), "tw": TW, "th": TH,
			"cw": cw, "ch": ch, "pad": PAD, "prio": t.blend_priority, "mode": t.blend_mode, "colour": t.map_color_med}
	step.call("Blending masks")
	var modes := _blendomatic(FileAccess.get_file_as_bytes(data.path_join("blendomatic_x1.dat")))
	var blend := Sheets.blank(31 * cw, modes.size() * ch)
	var alpha := []                       # [mode][mask] -> PackedByteArray(97*49) of 0..255, the share of the neighbour that shows
	for m in modes.size():
		var per_mode := []
		for k in 31:
			var rows: Array = modes[m][k]
			var px := PackedByteArray()
			px.resize(TW * TH * 4)
			var a := PackedByteArray()
			a.resize(TW * TH)
			for y in TH:
				for x in TW:
					var v: int = rows[y][x]
					if v >= 0:
						var al := 255 - mini(255, int(roundf(v * 255.0 / 128.0)))
						var o := (y * TW + x) * 4
						px[o] = 255
						px[o + 1] = 255
						px[o + 2] = 255
						px[o + 3] = al
						a[y * TW + x] = al
			per_mode.append(a)
			Sheets.paste(blend, Image.create_from_data(TW, TH, false, Image.FORMAT_RGBA8, px), k * cw + PAD, m * ch + PAD)
		alpha.append(per_mode)
	Sheets.save(blend, out.path_join("terrain/blend.png"))
	man["blend"] = {"file": "terrain/blend.png", "modes": modes.size(), "masks": 31, "tw": TW, "th": TH, "cw": cw, "ch": ch, "pad": PAD}
	step.call("Shoreline overlays")
	# pre-masked overlays: the neighbour's tile with the mask's weight as alpha, for every (terrain, mode) that can be laid over another
	# used terrain. The game lays these over a tile with a plain alpha blend.
	var combos := []
	for me: int in USED:
		for o: int in USED:
			if int(terr[o].blend_priority) > int(terr[me].blend_priority):
				var c := [o, LOOK[int(terr[me].blend_mode)][int(terr[o].blend_mode)]]
				if not (c in combos):
					combos.append(c)
	var atlas := Sheets.blank(31 * cw, combos.size() * VARIANTS.size() * ch)
	for ci in combos.size():
		var o: int = combos[ci][0]
		var mode: int = combos[ci][1]
		for vi in VARIANTS.size():
			var frame: int = VARIANTS[vi]
			var tile: Image = sheets[o].get_region(Rect2i((frame % 10) * cw + PAD, (frame / 10) * ch + PAD, TW, TH))
			var td := tile.get_data()
			for k in 31:
				var m: PackedByteArray = alpha[mode][k]
				var od := td.duplicate()
				for i in TW * TH:
					od[i * 4 + 3] = int(roundf(td[i * 4 + 3] * (m[i] / 255.0)))
				Sheets.paste(atlas, Image.create_from_data(TW, TH, false, Image.FORMAT_RGBA8, od), k * cw + PAD, (ci * VARIANTS.size() + vi) * ch + PAD)
	Sheets.save(atlas, out.path_join("terrain/overlay.png"))
	man["overlay"] = {"file": "terrain/overlay.png", "combos": combos, "variants": VARIANTS, "cw": cw, "ch": ch, "pad": PAD, "tw": TW, "th": TH}
	return man


## 9 blending modes, each 31 alpha masks as 97x49 arrays of weights 0..128 (-1 outside the diamond).
static func _blendomatic(b: PackedByteArray) -> Array:
	var modes := b.decode_u32(0)
	var tiles := b.decode_u32(4)
	var pos := 8
	var out_modes := []
	for _m in modes:
		var px := b.decode_u32(pos)
		pos += 4 + tiles
		pos += px * 4                          # the bit masks (which pixels count), not needed here
		var masks := []
		for _t in tiles:
			var data := b.slice(pos, pos + px)
			pos += px
			var rows := []
			var p := 0
			var half := 49 / 2
			for y in 49:
				var n := 1 + 4 * y if y < half else 97 - 4 * (y - half)
				if y == half:
					n = 97
				var pad := 48 - n / 2
				var row := []
				row.resize(97)
				row.fill(-1)
				for i in n:
					row[pad + i] = data[p + i]
				rows.append(row)
				p += n
			masks.append(rows)
		out_modes.append(masks)
	return out_modes
