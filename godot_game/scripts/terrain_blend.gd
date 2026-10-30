class_name TerrainBlend
extends RefCounted
## Draws the ground the way the original does. Every tile of a terrain is a 97x49 diamond from a 10x10 pattern;
## where two terrains meet, the one with the higher priority is laid over its neighbour's tile through an alpha
## mask from blendomatic.dat (which mask depends on which of the 8 surrounding tiles are such neighbours, and the
## blend mode on which two kinds of terrain meet). Tiles without such a neighbour come straight from the pattern;
## the blended ones are built once and packed into one more atlas.

const GRASS := 0            # the three grasses: plain, "Grass 2" and "Grass 3" (the meadow patches)
const GRASS2 := 12
const GRASS3 := 9
const WATER := 1
const BEACH := 2
const SHALLOWS := 4

# the 8 neighbours around a tile, numbered like the original: 0 up, 1 up-right, 2 right ... (map offsets)
const NB: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]
# blend mode of the tile in a row, of the neighbour drawn over it in a column
const LOOK := [[2, 3, 2, 1, 1, 6, 5, 4], [3, 3, 3, 1, 1, 6, 5, 4], [2, 3, 2, 1, 1, 6, 1, 4], [1, 1, 1, 0, 7, 6, 5, 4],
	[1, 1, 1, 7, 7, 6, 5, 4], [6, 6, 6, 6, 6, 6, 5, 4], [5, 5, 1, 5, 5, 5, 5, 4], [4, 3, 4, 4, 4, 4, 4, 4]]
# which mask for which set of influencing edge neighbours (bits 1, 3, 5, 7)
const ADJ := {0b00001000: 0, 0b00000010: 4, 0b00100000: 8, 0b10000000: 12, 0b00100010: 20, 0b10001000: 21, 0b10100000: 22,
	0b10000010: 23, 0b00101000: 24, 0b00001010: 25, 0b00101010: 26, 0b10101000: 27, 0b10100010: 28, 0b10001010: 29, 0b10101010: 30}
const VARIANT_FRAMES: Array[int] = [0, 27, 41, 66]      # blended tiles use these patterns only (keeps the atlas small); same list as tools/extract_terrain.py
const COLS := 48

static var last_atlas: Image          # the blended tiles of the last map (for tests and debugging)


static func is_grass(t: int) -> bool:
	return t == GRASS or t == GRASS2 or t == GRASS3


## Which neighbouring terrains lay over this tile, with the masks to use, lowest priority first.
static func influences(grid: PackedByteArray, n: int, x: int, y: int) -> Array:
	var me := int(grid[y * n + x])
	var mt: Dictionary = Assets.terr.tiles[str(me)]
	var found := {}
	for i in 8:
		var c := Vector2i(x, y) + NB[i]
		if c.x < 0 or c.y < 0 or c.x >= n or c.y >= n:
			continue
		var o := int(grid[c.y * n + c.x])
		if o == me or int(Assets.terr.tiles[str(o)].prio) <= int(mt.prio):
			continue
		if i % 2 == 0:
			# a corner neighbour only counts when neither edge neighbour beside it already is that terrain
			var skip := false
			for j in [(i + 7) % 8, (i + 1) % 8]:
				var q := Vector2i(x, y) + NB[j]
				if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n and int(grid[q.y * n + q.x]) == o:
					skip = true
			if skip:
				continue
		found[o] = int(found.get(o, 0)) | (1 << i)
	var out: Array = []
	for o: int in found:
		var binf: int = found[o]
		var masks: Array[int] = []
		var edge := binf & 0b10101010
		if edge != 0 and ADJ.has(edge):
			var k: int = ADJ[edge]
			masks.append(k + (x & 3) if k < 4 else k)
		for pair in [[2, 16], [4, 17], [0, 18], [6, 19]]:
			if binf & (1 << pair[0]):
				masks.append(pair[1])
		out.append({"t": o, "masks": masks, "mode": int(LOOK[int(mt.mode)][int(Assets.terr.tiles[str(o)].mode)])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(Assets.terr.tiles[str(a.t)].prio) < int(Assets.terr.tiles[str(b.t)].prio))
	return out


## The tile of terrain `tid` (pattern `variant`) with every influence laid over it, lowest priority first.
static func compose(tid: int, variant: int, infl: Array) -> Image:
	var img := Assets.terrain_tile(tid, VARIANT_FRAMES[variant])
	var shape := img.duplicate() as Image
	for e: Dictionary in infl:
		for k: int in e.masks:
			var ov := Assets.overlay_tile(int(e.t), int(e.mode), k, variant)
			if ov != null:
				img.blend_rect(ov, Rect2i(0, 0, 97, 49), Vector2i.ZERO)
	# keep only what lies inside the tile's own diamond (overlay pixels on its border would show as seams)
	var out := Image.create(97, 49, false, Image.FORMAT_RGBA8)
	out.blend_rect_mask(img, shape, Rect2i(0, 0, 97, 49), Vector2i.ZERO)
	return out


static func _uniform(grid: PackedByteArray, n: int, x: int, y: int) -> bool:
	var me := grid[y * n + x]
	for d in NB:
		var c := Vector2i(x, y) + d
		if c.x >= 0 and c.y >= 0 and c.x < n and c.y < n and grid[c.y * n + c.x] != me:
			return false
	return true


static func _source(tex: Texture2D, cols: int, rows: int, pad: int, count: int) -> TileSetAtlasSource:
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(97, 49)
	src.margins = Vector2i(pad, pad)
	src.separation = Vector2i(2 * pad, 2 * pad)
	for i in count:
		src.create_tile(Vector2i(i % cols, i / cols))
	return src


## Fills `layer` with the ground described by `grid` (a terrain id per cell, n x n) and returns how many blended tiles it made.
static func apply(layer: TileMapLayer, grid: PackedByteArray, n: int) -> int:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(96, 48)
	layer.tile_set = ts
	var base_src := {}
	for tid in range(0, 64):
		if (str(tid) in Assets.terr.tiles and grid.has(tid)) or tid == GRASS:
			var t: Dictionary = Assets.terr.tiles[str(tid)]
			base_src[tid] = ts.add_source(_source(Assets.tex(t.file), 10, 10, int(t.pad), 100))
	var keys := {}
	var order: Array = []
	var pending: Array = []        # [cell, index into order]
	for y in n:
		for x in n:
			var tid := int(grid[y * n + x])
			var infl: Array = [] if _uniform(grid, n, x, y) else influences(grid, n, x, y)
			if infl.is_empty():
				layer.set_cell(Vector2i(x, y), base_src[tid], Vector2i(x % 10, y % 10))
				continue
			var variant := (x + 2 * y) % VARIANT_FRAMES.size()
			var key := "%d:%d:%s" % [tid, variant, JSON.stringify(infl)]
			if not keys.has(key):
				keys[key] = order.size()
				order.append([tid, variant, infl])
			pending.append([Vector2i(x, y), keys[key]])
	if not order.is_empty():
		var rows := (order.size() + COLS - 1) / COLS
		var atlas := Image.create(COLS * 99, rows * 51, false, Image.FORMAT_RGBA8)
		for i in order.size():
			atlas.blit_rect(compose(order[i][0], order[i][1], order[i][2]), Rect2i(0, 0, 97, 49), Vector2i((i % COLS) * 99 + 1, (i / COLS) * 51 + 1))
		last_atlas = atlas
		var bsrc := ts.add_source(_source(ImageTexture.create_from_image(atlas), COLS, rows, 1, order.size()))
		for p: Array in pending:
			var i: int = p[1]
			layer.set_cell(p[0], bsrc, Vector2i(i % COLS, i / COLS))
	return order.size()
