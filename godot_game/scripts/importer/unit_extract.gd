class_name UnitExtract
extends RefCounted
## Sprites for units and buildings, driven by the imported rules (RulesBuilder output): no hand-picked SLP numbers. A port of
## tools/extract_units.py. Work is split in small tasks (one unit, one building) so that an import can be paused and resumed.
##  - units: idle, walk, attack, die and the corpse as angles x frames sheets (the SLP stores 5 angles, the rest are mirrors);
##    `red` sheets exist for the units an enemy may field.
##  - buildings: the idle graphic plus its delta pieces (recursively, with their offsets) composited on one hotspot and drawn by
##    layer; the Town Center uses its head unit's assembly; every age's look is its own unit id.

const RED := 32
const BUILDING_SHADOW := [0, 206]
const UNIT_ANIMS := [["idle", "idle"], ["walk", "move"], ["attack", "attack"], ["die", "die"]]
const SKIP_NAMES := ["Relic", "Yurt", "Pavilion", "Bridge", "Genitour", "Ornlu", "Horse", "Sea ", "Wolf", "Boar", "Deer"]
const EXTRA_UNITS := [53, 65, 69, 450, 451, 455, 456, 457, 458, 285, 286]
const NAVAL_WAR := [21, 250, 420, 442, 527, 528, 529, 532, 533, 539, 691, 831, 832]
const ENEMY_CLASSES := [0, 6, 12, 18, 22, 23, 36, 44, 47, 50, 54]

var out := ""
var rules: Dictionary
var G: Dictionary
var U: Dictionary
var drs: Drs
var pal: PackedByteArray
var lut_plain: PackedInt32Array
var lut_red: PackedInt32Array
var lut_shade: PackedInt32Array
var style_gfx: Dictionary
var style := 0
var by_age: Array = [{}]
var age_of: Dictionary = {}
var man := {"anims": {}, "buildings": {}, "units": {}, "construction": {}, "cons_of": {}}
var tasks: Array = []                       # [kind, ...] in the order they run


func _init(game: String, out_dir: String, rules_: Dictionary, graphics: Dictionary) -> void:
	out = out_dir
	rules = rules_
	G = graphics
	U = rules.units
	var data := game.path_join("Data")
	drs = Drs.open(data.path_join("graphics.drs"))
	var interfac := Drs.open(data.path_join("interfac.drs"))
	pal = Slp.read_pal(interfac.get_file("bina", 50500).get_string_from_ascii())
	lut_plain = Slp.lut(pal)
	lut_red = Slp.lut(pal, RED)
	lut_shade = Slp.lut(pal, 0, BUILDING_SHADOW)
	style_gfx = rules.style_gfx
	# what every unit and building has become at each age (Feudal, Castle, Imperial are techs 101..103)
	var E: Dictionary = rules.effects
	for t in [101, 102, 103]:
		var cur: Dictionary = (by_age[by_age.size() - 1] as Dictionary).duplicate()
		for e: Array in E.get(str(int(rules.techs[str(t)].effect)), []):
			if int(e[0]) == 3:
				cur[int(e[1])] = int(e[2])
		by_age.append(cur)
	var targets := {}
	for m: Dictionary in by_age:
		for v: int in m.values():
			targets[v] = true
	for uid: String in U:
		var u: Dictionary = U[uid]
		if int(u.type) == 80 and not (u.get("annex", []) as Array).is_empty() and not targets.has(int(uid)):
			for k in 4:
				var c := chain(int(uid), k)
				if not age_of.has(c):
					age_of[c] = k
	_plan()


## Which graphics a task needs: the list of everything to do, in order.
func _plan() -> void:
	var units := {}
	var style_blds := {}
	for c: Dictionary in rules.civ_info:
		var cb := catalog(int(c.id))
		for i: int in cb[0]:
			units[i] = true
		var st: int = c.style
		if not style_blds.has(st):
			style_blds[st] = {}
		for i: int in cb[1]:
			style_blds[st][i] = true
	var ulist: Array = units.keys()
	ulist.sort()
	for i: int in EXTRA_UNITS:
		if U.has(str(i)):
			ulist.append(i)
	for uid: int in ulist:
		tasks.append(["unit", uid])
	var all_b := {}
	for st: int in style_blds:
		for i: int in style_blds[st]:
			all_b[i] = true
	var blist: Array = all_b.keys()
	blist.sort()
	for uid: int in blist:
		tasks.append(["cons", uid])
	var styles: Array = style_blds.keys()
	styles.sort()
	for st: int in styles:
		var l: Array = style_blds[st].keys()
		l.sort()
		for uid: int in l:
			tasks.append(["bld", st, uid])


func describe(i: int) -> String:
	var t: Array = tasks[i]
	match t[0]:
		"unit":
			return "Unit: " + str(U[str(t[1])].name)
		"cons":
			return "Building site: " + str(U[str(t[1])].name)
	return "Building: " + str(U[str(t[2])].name)


func run_task(i: int) -> void:
	var t: Array = tasks[i]
	match t[0]:
		"unit":
			var u: Dictionary = U[str(t[1])]
			var red := not (u.atk as Array).is_empty() and (int(u["class"]) in ENEMY_CLASSES or int(t[1]) in NAVAL_WAR)
			unit(int(t[1]), red)
		"cons":
			construction(int(t[1]))
		"bld":
			style = int(t[1])
			building(int(t[2]))


func chain(uid: int, age: int) -> int:
	var seen := 0
	while by_age[age].has(uid) and seen < 8:
		uid = by_age[age][uid]
		seen += 1
	return uid


func _gfx(uid: int) -> Dictionary:
	var sg: Dictionary = style_gfx.get(str(style), {})
	var g: Variant = sg.get(str(uid))
	if g != null and not (g as Dictionary).is_empty():
		return g
	return U[str(uid)].gfx


func _has_slp(gid: int) -> bool:
	var g: Variant = G.get(str(gid))
	return g != null and drs.has("slp", int(g.slp))


func _slp(gid: int, lut: PackedInt32Array, max_frames := -1) -> Array:
	var g: Variant = G.get(str(gid))
	if g == null or not drs.has("slp", int(g.slp)):
		return []
	return Slp.decode(drs.get_file("slp", int(g.slp)), lut, max_frames)


## A static graphic as pieces {layer, gid, x, y}: its own picture and, recursively, every delta graphic placed by its offset.
## Nested deltas repeat pieces (a part lists its neighbours again), so a piece is kept once per place.
func _expand(gid: int, dx := 0, dy := 0, out_list: Array = [], seen: Dictionary = {}) -> Array:
	var g: Variant = G.get(str(gid))
	var key := "%d:%d:%d" % [gid, dx, dy]
	if g == null or seen.has(key):
		return out_list
	seen[key] = true
	if _has_slp(gid):
		out_list.append({"layer": int(g.layer), "gid": gid, "x": dx, "y": dy, "slp": int(g.slp)})
	for d: Dictionary in g.deltas:
		if int(d.graphic_id) >= 0:
			_expand(int(d.graphic_id), dx + int(d.offset_x), dy + int(d.offset_y), out_list, seen)
	return out_list


static func _by_layer(list: Array) -> Array:
	for i in list.size():
		list[i]["i"] = i
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.layer < b.layer or (a.layer == b.layer and a.i < b.i))
	return list


## One building's picture, drawn by layer (ground, then shadows, then the structure), list order within a layer. The Town Center is
## made of a hall and two wings; the game keeps the finished assembly in its head unit, whose delta offsets place the parts.
func _pieces(uid: int, dx0 := 0, dy0 := 0) -> Array:
	var u: Dictionary = U[str(uid)]
	var head := int(u.get("head", -1))
	var age: Variant = age_of.get(uid)
	if not (u.get("annex", []) as Array).is_empty() and head >= 0 and age != null:
		var gid := int(_gfx(chain(head, int(age))).idle)
		var o := _expand(gid, dx0, dy0)
		if not o.is_empty():
			return _by_layer(o)
	return _by_layer(_expand(int(_gfx(uid).idle), dx0, dy0))


func _uses_head(uid: int) -> bool:
	var u: Dictionary = U[str(uid)]
	return not (u.get("annex", []) as Array).is_empty() and int(u.get("head", -1)) >= 0 and age_of.get(uid) != null


## All pieces of a building: layer, graphic, x, y. A building whose head unit holds the assembly (Town Center) needs no annexes added.
func _parts(uid: int) -> Array:
	var pieces := _pieces(uid)
	if not _uses_head(uid):
		var age: Variant = age_of.get(uid)
		for ann: Array in U[str(uid)].get("annex", []):
			var part := chain(int(ann[0]), int(age) if age != null else 0)
			pieces.append_array(_pieces(part, 0, 0))
		pieces = _by_layer(pieces)
	return pieces


func _piece_ids(uid: int, st: int) -> Array:
	var keep := style
	style = st
	var ids := []
	for p: Dictionary in _parts(uid):
		ids.append([p.layer, p.x, p.y, p.slp])
	style = keep
	return ids


## A graphic without a picture of its own (a ship's) is drawn from its delta graphics: every delta contributes the same angle and
## frame, placed by its offset and hotspot. 16-angle graphics store 9 angles (the rest are mirrors); we keep every second one so that
## we have the 5 rows the game turns into 8 directions.
func _composite(gid: int, lut: PackedInt32Array, with_main: bool) -> Variant:
	var g: Dictionary = G.get(str(gid), {})
	if g.is_empty() or (g.deltas as Array).is_empty():
		return null
	var parts := []
	if with_main:             # siege engines: the graphic's own picture is only one layer (the moving parts)
		var fr := _slp(gid, lut)
		if not fr.is_empty() and int(g.frames) >= 1 and fr.size() >= int(g.frames):
			parts.append([{"offset_x": 0, "offset_y": 0}, g, fr])
	for d: Dictionary in g.deltas:
		if int(d.graphic_id) < 0:
			continue
		var gd: Dictionary = G.get(str(int(d.graphic_id)), {})
		var fr := _slp(int(d.graphic_id), lut)
		if not gd.is_empty() and not fr.is_empty() and int(gd.frames) >= 1 and fr.size() >= int(gd.frames):
			parts.append([d, gd, fr])
	if parts.is_empty():
		return null
	var fpa := int(g.frames)
	for p: Array in parts:
		fpa = maxi(fpa, int(p[1].frames))
	var rows := 5
	var made := []
	for r in rows:
		for k in fpa:
			var layers := []
			for p: Array in parts:
				var gd: Dictionary = p[1]
				var fr: Array = p[2]
				var stored := fr.size() / int(gd.frames)
				var src := r * (stored - 1) / (rows - 1)
				layers.append([fr[src * int(gd.frames) + (k % int(gd.frames))], int(p[0].offset_x), int(p[0].offset_y)])
			var x0 := 0
			var y0 := 0
			var x1 := 0
			var y1 := 0
			for i in layers.size():
				var f: Dictionary = layers[i][0]
				var ax: int = layers[i][1] - f.hx
				var ay: int = layers[i][2] - f.hy
				x0 = ax if i == 0 else mini(x0, ax)
				y0 = ay if i == 0 else mini(y0, ay)
				x1 = ax + f.w if i == 0 else maxi(x1, ax + f.w)
				y1 = ay + f.h if i == 0 else maxi(y1, ay + f.h)
			var im := Sheets.blank(maxi(x1 - x0, 1), maxi(y1 - y0, 1))
			for l: Array in layers:
				var f: Dictionary = l[0]
				Sheets.over(im, f.img, l[1] - f.hx - x0, l[2] - f.hy - y0)
			made.append({"img": im, "hx": -x0, "hy": -y0})
	return [made, fpa, rows]


func unit(uid: int, red: bool) -> void:
	var u: Dictionary = U[str(uid)]
	var entry := {"name": u.name, "anims": {}, "angles": 8}
	var gfx: Dictionary = u.gfx
	var dead: Variant = U.get(str(int(u.dead)))
	var corpse := int(dead.gfx.idle) if dead != null else -1
	var jobs := []
	for a: Array in UNIT_ANIMS:
		jobs.append([a[0], int(gfx[a[1]])])
	jobs.append(["corpse", corpse])
	var colours := [["blue", lut_plain]]
	if red:
		colours.append(["red", lut_red])
	for c: Array in colours:
		for job: Array in jobs:
			var name: String = job[0]
			var gid: int = job[1]
			var frames := _slp(gid, c[1])
			var g: Variant = G.get(str(gid))
			var key := "u%d_%s_%s" % [uid, name, c[0]]
			var layered := not frames.is_empty() and int(u["class"]) in [13, 55] and name != "corpse"
			if (frames.is_empty() or layered) and g != null and not (g.deltas as Array).is_empty():
				var comp: Variant = _composite(gid, c[1], layered)
				if comp != null:
					var info := Sheets.animation_images(comp[0], comp[2], comp[1], out.path_join(key + ".png"))
					info["file"] = key + ".png"
					info["dur"] = g.speed if float(g.speed) > 0.0 else 0.1
					info["total_angles"] = g.angles
					man.anims[key] = info
					if not entry.anims.has(name):
						entry.anims[name] = key.rsplit("_", true, 1)[0]
					entry["angles"] = g.angles
				continue
			if frames.is_empty() or g == null or int(g.frames) < 1 or frames.size() < int(g.frames):
				continue
			var stored := frames.size() / int(g.frames)
			frames = frames.slice(0, stored * int(g.frames))        # a few SLPs carry spare frames at the end
			var info := Sheets.animation(frames, stored, out.path_join(key + ".png"))
			info["file"] = key + ".png"
			info["dur"] = g.speed if float(g.speed) > 0.0 else 0.1
			info["total_angles"] = g.angles
			man.anims[key] = info
			if not entry.anims.has(name):
				entry.anims[name] = key.rsplit("_", true, 1)[0]
			entry["angles"] = g.angles
	man.units[str(uid)] = entry


## The building site picture the data names for this building: three stages (stakes, frame, scaffold) of one SLP. Most buildings
## share the generic CNST1..CNST8 by size; the Dock and Fish Trap have their own. Walls and gates keep the game's own pieces.
func construction(uid: int) -> void:
	var gid := int(U[str(uid)].get("construction_gfx", -1))
	var g: Variant = G.get(str(gid))
	var fr: Array = _slp(gid, lut_shade) if g != null else []
	if fr.is_empty() or int(g.frames) != 1 or fr.size() != 3 or not (g.deltas as Array).is_empty():
		return
	if not man.construction.has(str(gid)):
		var total := 0
		var hmax := 0
		for f: Dictionary in fr:
			total += f.w + 2
			hmax = maxi(hmax, f.h)
		var sheet := Sheets.blank(total, hmax + 2)
		var x := 0
		var items := []
		for f: Dictionary in fr:
			Sheets.paste(sheet, f.img, x + 1, 1)
			items.append({"x": x + 1, "y": 1, "w": f.w, "h": f.h, "hx": f.hx, "hy": f.hy})
			x += f.w + 2
		Sheets.save(sheet, out.path_join("cons_%d.png" % gid))
		man.construction[str(gid)] = {"file": "cons_%d.png" % gid, "items": items}
	man.cons_of[str(uid)] = gid


func building(uid: int) -> void:
	var u: Dictionary = U[str(uid)]
	if style != 0 and _piece_ids(uid, style) == _piece_ids(uid, 0):
		return                  # the same picture as the Britons' set: the game falls back to it
	var key := "bld_%d_%d" % [style, uid] if style != 0 else "bld_%d" % uid
	var pieces: Array = _parts(uid)
	if pieces.is_empty():
		return
	var frames := []
	var x0 := 0
	var y0 := 0
	var x1 := 0
	var y1 := 0
	for i in pieces.size():
		var p: Dictionary = pieces[i]
		var f: Dictionary = _slp(p.gid, lut_shade, 1)[0]
		frames.append(f)
		var ax: int = p.x - f.hx
		var ay: int = p.y - f.hy
		x0 = ax if i == 0 else mini(x0, ax)
		y0 = ay if i == 0 else mini(y0, ay)
		x1 = ax + f.w if i == 0 else maxi(x1, ax + f.w)
		y1 = ay + f.h if i == 0 else maxi(y1, ay + f.h)
	var img := Sheets.blank(x1 - x0, y1 - y0)
	for i in pieces.size():
		var f: Dictionary = frames[i]
		Sheets.over(img, f.img, pieces[i].x - f.hx - x0, pieces[i].y - f.hy - y0)
	Sheets.save(img, out.path_join(key + ".png"))
	man.buildings[key.substr(4)] = {"file": key + ".png", "w": x1 - x0, "h": y1 - y0, "hx": -x0, "hy": -y0, "name": u.name, "style": style}


## Units and buildings the civ can ever have: what is enabled, trained or built, and everything it turns into.
func catalog(civ: int) -> Array:
	var E: Dictionary = rules.effects
	var T: Dictionary = rules.techs
	var tree := int(rules.civs[civ].tech_tree)
	var dis_t := {}
	var dis_u := {}
	for e: Array in E.get(str(tree), []):
		if int(e[0]) == 102:
			dis_t[int(e[4])] = true
		if int(e[0]) == 2 and int(e[2]) == 0:
			dis_u[int(e[1])] = true
	var reach := []
	for t: Dictionary in T.values():
		if not dis_t.has(int(t.id)) and int(t.civ) in [-1, civ] and int(t.effect) >= 0:
			reach.append(t)
	var have := {}
	for k: String in U:
		var u: Dictionary = U[k]
		if u.enabled or (int(u.type) == 80 and int(u.loc) == 118):
			have[int(k)] = true
	for t: Dictionary in reach:
		for e: Array in E.get(str(int(t.effect)), []):
			if int(e[0]) == 2 and int(e[2]) == 1:
				have[int(e[1])] = true
	for t: Dictionary in reach:             # what gets upgraded is part of the set too (the Town Center itself has no enabler)
		for e: Array in E.get(str(int(t.effect)), []):
			if int(e[0]) == 3 and U.has(str(int(e[1]))) and int(U[str(int(e[1]))].type) == 80:
				have[int(e[1])] = true
	for k: int in dis_u:
		have.erase(k)
	var changed := true
	while changed:
		changed = false
		for t: Dictionary in reach:
			for e: Array in E.get(str(int(t.effect)), []):
				if int(e[0]) == 3 and have.has(int(e[1])) and not have.has(int(e[2])):
					have[int(e[2])] = true
					changed = true
	var ids: Array = have.keys()
	ids.sort()
	var units := []
	var blds := []
	for i: int in ids:
		if not U.has(str(i)):
			continue
		var name := str(U[str(i)].name)
		if name == "":
			continue
		var skip := false
		for s: String in SKIP_NAMES:
			if s in name:
				skip = true
		if skip:
			continue
		if int(U[str(i)].type) == 70:
			units.append(i)
		elif int(U[str(i)].type) == 80:
			blds.append(i)
	return [units, blds]
