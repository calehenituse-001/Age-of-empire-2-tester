class_name Minimap
extends Control
## The whole map in one corner: trees, mines and bushes (redrawn slowly in slices so it never hitches), your
## buildings and units, enemies, and the part of the map on screen. Touch or drag on it to move the camera.
## Enemies are red diamonds and your units blue dots, so friend and foe never rely on colour alone.

signal jump_to(world: Vector2)

const TEX := 256
const SLICE := 3500
const COLORS := {"wood": Color(0.05, 0.3, 0.08), "food": Color(0.9, 0.25, 0.2), "gold": Color(1.0, 0.85, 0.2), "stone": Color(0.75, 0.78, 0.82), "fish": Color(0.75, 0.97, 1.0)}
const TERRAIN_COLORS := {1: Color(0.16, 0.38, 0.78), 4: Color(0.42, 0.66, 0.85), 2: Color(0.84, 0.76, 0.52)}

var map: GameMap
var cam: Camera2D

var _img: Image
var _tex: ImageTexture
var _terr_tex: ImageTexture
var _keys: Array = []
var _idx := 0
var _building := false
var _next := 0.5
var _redraw := 0.0
var _pings: Array = []          # [{"p": tile, "t": seconds}]
var _touch := -1


func setup(m: GameMap, c: Camera2D) -> void:
	map = m
	cam = c
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_img = Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	# water, shallows and beaches, drawn once
	var terr := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	var n := 2.0 * map.size
	for i in map.tgrid.size():
		var t := int(map.tgrid[i])
		if TERRAIN_COLORS.has(t):
			var cx := float(i % map.size)
			var cy := float(i / map.size)
			var px := int(((cx - cy) / n + 0.5) * (TEX - 2))
			var py := int(((cx + cy) / n) * (TEX - 2))
			for dx in 2:
				for dy in 2:
					terr.set_pixel(px + dx, py + dy, TERRAIN_COLORS[t])
	_terr_tex = ImageTexture.create_from_image(terr)


func ping(tile: Vector2) -> void:
	_pings.append({"p": tile, "t": 0.0})


## Tile coordinates to a point inside this control.
func _p(t: Vector2) -> Vector2:
	var n := 2.0 * map.size
	return Vector2((t.x - t.y) / n + 0.5, (t.x + t.y) / n) * size


func _tile_at(local: Vector2) -> Vector2:
	var n := 2.0 * map.size
	var a := (local.x / size.x - 0.5) * n
	var b := local.y / size.y * n
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


func _process(dt: float) -> void:
	if map == null:
		return
	_next -= dt
	if _next <= 0.0 and not _building:
		_building = true
		_keys = map.res_by_cell.values()
		_idx = 0
		_img.fill(Color(0, 0, 0, 0))
	if _building:
		var stop := mini(_idx + SLICE, _keys.size())
		var n := 2.0 * map.size
		for i in range(_idx, stop):
			var r: ResNode = _keys[i]
			if not is_instance_valid(r) or not r.alive:
				continue
			var px := int(((r.cell.x - r.cell.y) / n + 0.5) * (TEX - 2))
			var py := int(((r.cell.x + r.cell.y) / n) * (TEX - 2))
			var col: Color = COLORS[r.kind]
			_img.set_pixel(px, py, col)
			_img.set_pixel(px + 1, py, col)
			_img.set_pixel(px, py + 1, col)
			_img.set_pixel(px + 1, py + 1, col)
		_idx = stop
		if _idx >= _keys.size():
			_tex.update(_img)
			_building = false
			_next = 6.0
	for p in _pings:
		p.t += dt
	_pings = _pings.filter(func(p: Dictionary) -> bool: return p.t < 3.0)
	_redraw -= dt
	if _redraw <= 0.0:
		_redraw = 0.2
		queue_redraw()


func _draw() -> void:
	if map == null:
		return
	var diamond := PackedVector2Array([Vector2(0.5, 0.0) * size, Vector2(1.0, 0.5) * size, Vector2(0.5, 1.0) * size, Vector2(0.0, 0.5) * size])
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.03, 0.9))
	draw_colored_polygon(diamond, Color(0.24, 0.45, 0.2))
	draw_texture_rect(_terr_tex, Rect2(Vector2.ZERO, size), false)
	draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
	var line := PackedVector2Array(diamond)
	line.append(diamond[0])
	draw_polyline(line, Color(0.9, 0.75, 0.4), 2.0)
	var dot := maxf(3.0, size.x / 70.0)
	for b in map.buildings:
		if b.alive:
			var q := _p(b.tp)
			draw_rect(Rect2(q - Vector2(dot, dot), Vector2(dot, dot) * 2.0), Color(0.55, 0.8, 1.0))
			draw_rect(Rect2(q - Vector2(dot, dot), Vector2(dot, dot) * 2.0), Color(0, 0, 0, 0.8), false, 1.5)
	for b in map.foes:
		if b.alive and b.kind == "wall":
			draw_rect(Rect2(_p(b.tp) - Vector2(dot, dot) * 0.3, Vector2(dot, dot) * 0.6), Color(0.85, 0.35, 0.3))
		elif b.alive:
			var q := _p(b.tp)
			draw_rect(Rect2(q - Vector2(dot, dot), Vector2(dot, dot) * 2.0), Color(1.0, 0.3, 0.25))
			draw_rect(Rect2(q - Vector2(dot, dot), Vector2(dot, dot) * 2.0), Color(0, 0, 0, 0.8), false, 1.5)
	for r in map.relics:
		if r.on_ground():
			var q := _p(r.tp)
			draw_rect(Rect2(q - Vector2(dot, dot) * 0.6, Vector2(dot, dot) * 1.2), Color(1.0, 0.9, 0.35))
			draw_rect(Rect2(q - Vector2(dot, dot) * 0.6, Vector2(dot, dot) * 1.2), Color(0.25, 0.15, 0.0, 0.9), false, 1.2)
	for m in map.mobs:
		if not m.alive:
			continue
		var q := _p(m.tp)
		if m.team == 0:
			draw_circle(q, dot * 0.8, Color(0.3, 0.6, 1.0))
		elif m.team == 1:
			var d := dot * 1.25
			draw_colored_polygon(PackedVector2Array([q + Vector2(0, -d), q + Vector2(d, 0), q + Vector2(0, d), q + Vector2(-d, 0)]), Color(1.0, 0.15, 0.1))
		else:
			draw_rect(Rect2(q - Vector2(dot, dot) * 0.5, Vector2(dot, dot)), Color(0.95, 0.7, 0.25))
	# the part of the map on screen
	if cam != null:
		var vp := get_viewport().get_visible_rect().size
		var pts := PackedVector2Array()
		for c in [Vector2(0, 0), Vector2(vp.x, 0), vp, Vector2(0, vp.y)]:
			var w: Vector2 = cam.position + (c - vp * 0.5) / cam.zoom.x
			pts.append(_p(Iso.to_tile(w)).clamp(Vector2.ZERO, size))
		var view := PackedVector2Array(pts)
		view.append(pts[0])
		draw_polyline(view, Color(0, 0, 0, 0.8), 5.0)
		draw_polyline(view, Color.WHITE, 2.5)
	for p in _pings:
		var k: float = p.t / 3.0
		var q := _p(p.p)
		var a := (1.0 - k) * (1.0 if int(p.t * 4.0) % 2 == 0 else 0.5)
		draw_arc(q, dot * (1.5 + k * 6.0), 0.0, TAU, 24, Color(1.0, 0.2, 0.15, a), 4.0)


## Touches are read straight from the input (the same way as the sliders), so GUI routing cannot swallow them.
func _input(e: InputEvent) -> void:
	if map == null or not is_visible_in_tree():
		return
	var rect := get_global_rect()
	if e is InputEventScreenTouch:
		if e.pressed and rect.has_point(e.position):
			_touch = e.index
			_move_to(e.position - rect.position)
			get_viewport().set_input_as_handled()
		elif not e.pressed and e.index == _touch:
			_touch = -1
			get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag and e.index == _touch:
		_move_to(e.position - rect.position)
		get_viewport().set_input_as_handled()


func _move_to(local: Vector2) -> void:
	var t := _tile_at(local).clamp(Vector2.ZERO, Vector2(map.size - 1, map.size - 1))
	jump_to.emit(Iso.to_world(t))
