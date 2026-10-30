extends Node
## Loads the sprites extracted by tools/extract_aoe_godot.py (assets/aoe/manifest.json) and hands out
## textures, the terrain tile set and animation data.

var man: Dictionary = {}
var terrain_set: TileSet
var terrain_source: Dictionary = {}   # terrain name -> tile set source id
var _tex: Dictionary = {}
var _weak_tex: Dictionary = {}
var _tex_order: Array[String] = []
var _tex_bytes := 0
var _anim_order: Array[String] = []
var _anims: Dictionary = {}
var terr: Dictionary = {}              # terrain.json: tile sheets by terrain id and the blend mask sheet
var _terr_img: Dictionary = {}
var _blend_img: Image
var _masks: Dictionary = {}


func _ready() -> void:
	load_all()


## Reads the tables of the extracted game; does nothing while there is no game data yet (portable version before its import).
func load_all() -> void:
	# Do not retain a manifest or terrain references from a failed/old import.
	# Boot can reload Assets after an unsuccessful data activation.
	man.clear()
	terr.clear()
	terrain_source.clear()
	terrain_set = null
	_tex.clear()
	_weak_tex.clear()
	_tex_order.clear()
	_tex_bytes = 0
	_anim_order.clear()
	_anims.clear()
	_masks.clear()
	_terr_img.clear()
	_blend_img = null
	if not GameData.ready():
		return
	man = GameData.json("manifest.json")
	# sprites extracted from the data by tools/extract_units.py: buildings as "bld_<unit id>", animations as "u<id>_<anim>_<colour>"
	if GameData.exists("units.json"):
		var u: Dictionary = GameData.json("units.json")
		for k: String in u.buildings:
			man.buildings["bld_" + k] = u.buildings[k]
		man.anims.merge(u.anims)
		man["units"] = u.units
		man["construction"] = u.get("construction", {})
		man["cons_of"] = u.get("cons_of", {})
	if GameData.exists("terrain.json"):
		terr = GameData.json("terrain.json")
	AppRuntime.mods.apply_assets(self)
	_build_terrain_set()


## The construction site pictures (three stages: file plus rectangles) of a building: the ones the data names for its unit id
## (the Dock has its own), else the generic stakes for its footprint.
func site(unit_id: int, bsize: int) -> Dictionary:
	var gid: String = str(man.get("cons_of", {}).get(str(unit_id), ""))
	if gid != "" and man.construction.has(gid):
		return man.construction[gid]
	return man.foundations[str(bsize)]


func tex(file: String) -> Texture2D:
	var t: Texture2D = _tex.get(file)
	if t == null and _weak_tex.has(file):
		t = _weak_tex[file].get_ref()
	if t == null:
		t = GameData.texture(file)
	if t != null:
		if not _tex.has(file):
			_tex_bytes += t.get_width() * t.get_height() * 4
			_tex[file] = t
			_weak_tex[file] = weakref(t)
		_tex_order.erase(file)
		_tex_order.append(file)
		while _tex_bytes > AppRuntime.cache_budget() and _tex_order.size() > 1:
			var old: String = _tex_order.pop_front()
			var previous: Texture2D = _tex[old]
			_tex_bytes -= previous.get_width() * previous.get_height() * 4
			_tex.erase(old)
	return t


@warning_ignore("integer_division")
func _build_terrain_set() -> void:
	terrain_set = TileSet.new()
	terrain_set.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	terrain_set.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	terrain_set.tile_size = Vector2i(96, 48)
	for tname: String in man.terrain:
		var t: Dictionary = man.terrain[tname]
		var src := TileSetAtlasSource.new()
		src.texture = tex(t.file)
		src.texture_region_size = Vector2i(int(t.tw), int(t.th))
		src.margins = Vector2i(int(t.pad), int(t.pad))
		src.separation = Vector2i(2 * int(t.pad), 2 * int(t.pad))
		var cols := int(t.cols)
		for i in int(t.frames):
			src.create_tile(Vector2i(i % cols, i / cols))
		terrain_source[tname] = terrain_set.add_source(src)


## Animation data (frames per angle, frame size table, seconds per frame, atlas texture).
func anim(key: String) -> Dictionary:
	var a: Dictionary = _anims.get(key, {})
	if a.is_empty():
		a = man.anims[key].duplicate()
		a["tex"] = tex(a.file)
		_anims[key] = a
	_anim_order.erase(key)
	_anim_order.append(key)
	while _anim_order.size() > (48 if AppRuntime.reduced_effects() else 128):
		_anims.erase(_anim_order.pop_front())
	return a


## One 97x49 tile of a terrain (frame 0..99 of its 10x10 pattern) as an image.
func terrain_tile(tid: int, frame: int) -> Image:
	var t: Dictionary = terr.tiles[str(tid)]
	if not _terr_img.has(tid):
		_terr_img[tid] = tex(t.file).get_image()
		if _terr_img[tid].get_format() != Image.FORMAT_RGBA8:
			_terr_img[tid].convert(Image.FORMAT_RGBA8)
	var img: Image = _terr_img[tid]
	return img.get_region(Rect2i((frame % 10) * int(t.cw) + int(t.pad), (frame / 10) * int(t.ch) + int(t.pad), int(t.tw), int(t.th)))


## A pre-masked overlay: terrain `tid`'s tile (pattern `variant`) with the blend mask `k` (0..30) of `mode` as its alpha,
## ready to be laid over another tile. Null when that terrain/mode pair was not baked.
func overlay_tile(tid: int, mode: int, k: int, variant: int) -> Image:
	var o: Dictionary = terr.overlay
	var idx := -1
	for i in o.combos.size():
		if int(o.combos[i][0]) == tid and int(o.combos[i][1]) == mode:
			idx = i
	if idx < 0:
		return null
	var key := (idx * 4 + variant) * 32 + k
	if not _masks.has(key):
		if _blend_img == null:
			_blend_img = tex(o.file).get_image()
			if _blend_img.get_format() != Image.FORMAT_RGBA8:
				_blend_img.convert(Image.FORMAT_RGBA8)
		var row: int = idx * o.variants.size() + variant
		_masks[key] = _blend_img.get_region(Rect2i(k * int(o.cw) + int(o.pad), row * int(o.ch) + int(o.pad), int(o.tw), int(o.th)))
	return _masks[key]


## Manifest name of a building's picture for the unit id it has now (age looks follow TechState.current), in the civ's
## architecture style (0 West European, 1 Central European, 2 Eastern, 3 Middle Eastern, 4 Mesoamerican), or "".
func look_key(unit_id: int, style := 0) -> String:
	if style > 0:
		var sk := "bld_%d_%d" % [style, unit_id]
		if man.buildings.has(sk):
			return sk
	var k := "bld_%d" % unit_id
	return k if man.buildings.has(k) else ""


## Points a Sprite2D at a building image; the sprite's position is then the centre of the footprint.
func apply_building(s: Sprite2D, bname: String) -> void:
	var b: Dictionary = man.buildings[bname]
	s.texture = tex(b.file)
	s.centered = false
	s.offset = -Vector2(b.hx, b.hy)


func building_sprite(bname: String) -> Sprite2D:
	var s := Sprite2D.new()
	apply_building(s, bname)
	return s


## Points a Sprite2D at one variant of a resource strip (trees, gold, stone, berries).
func apply_resource(s: Sprite2D, rname: String, variant: int) -> void:
	var r: Dictionary = man.resources[rname]
	var it: Dictionary = r.items[variant]
	s.texture = tex(r.file)
	s.centered = false
	s.region_enabled = true
	s.region_rect = Rect2(it.x, it.y, it.w, it.h)
	s.offset = -Vector2(it.hx, it.hy)


func release_terrain_cpu_cache() -> void:
	_terr_img.clear()
	_masks.clear()
	_blend_img = null
