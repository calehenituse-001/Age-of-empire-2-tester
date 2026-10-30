class_name Iso
## Isometric helpers. Tile coordinates are fractional cells with whole numbers at cell centres;
## a tile is 96x48 px, +x runs down-right on screen and +y down-left (what TileMapLayer's diamond-down layout uses).

const HW := 48.0
const HH := 24.0


static func to_world(t: Vector2) -> Vector2:
	return Vector2((t.x - t.y) * HW, (t.x + t.y) * HH)


static func to_tile(w: Vector2) -> Vector2:
	var s := w.y / HH
	var d := w.x / HW
	return Vector2((s + d) * 0.5, (s - d) * 0.5)


static func to_cell(w: Vector2) -> Vector2i:
	var t := to_tile(w)
	return Vector2i(roundi(t.x), roundi(t.y))


## Sprite direction 0..7 for a step in tile space: 0=S, 1=SW, 2=W, 3=NW, 4=N, 5=NE, 6=E, 7=SE (screen directions).
static func dir8(dx: float, dy: float) -> int:
	var theta := atan2((dx - dy) * HW, (dx + dy) * HH)
	return posmod(roundi(-theta / (PI / 4.0)), 8)
