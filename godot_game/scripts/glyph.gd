class_name Glyph
extends Control
## Small hand-drawn icons for the interface: the four resources, population, and a few actions. Every icon has its
## own silhouette so no information depends on colour alone.

var kind := "wood"
var tint := Color.WHITE

const OUTLINE := Color(0.06, 0.04, 0.02, 0.95)


static func make(k: String, px: float, col := Color.WHITE) -> Glyph:
	var g := Glyph.new()
	g.kind = k
	g.tint = col
	g.custom_minimum_size = Vector2(px, px)
	g.size = Vector2(px, px)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


func _draw() -> void:
	var u := minf(size.x, size.y) / 100.0
	var c := size * 0.5
	match kind:
		"wood":
			# a little pile of round log ends
			for p in [Vector2(30, 70), Vector2(70, 70), Vector2(50, 36)]:
				draw_circle(p * u, 27 * u, OUTLINE)
				draw_circle(p * u, 23 * u, Color(0.62, 0.4, 0.18))
				draw_circle(p * u, 15 * u, Color(0.86, 0.68, 0.4))
				draw_arc(p * u, 8 * u, 0.0, TAU, 16, Color(0.55, 0.36, 0.16), 2.5 * u)
		"food":
			draw_circle(c + Vector2(0, 6 * u), 34 * u, OUTLINE)
			draw_circle(c + Vector2(0, 6 * u), 30 * u, Color(0.84, 0.18, 0.16))
			draw_circle(c + Vector2(-10 * u, -2 * u), 7 * u, Color(1, 0.6, 0.55, 0.8))
			draw_line(c + Vector2(0, -24 * u), c + Vector2(4 * u, -40 * u), Color(0.35, 0.2, 0.08), 5 * u)
			draw_colored_polygon(PackedVector2Array([c + Vector2(6 * u, -34 * u), c + Vector2(30 * u, -44 * u), c + Vector2(22 * u, -22 * u)]), Color(0.3, 0.75, 0.25))
		"gold":
			draw_circle(c, 40 * u, OUTLINE)
			draw_circle(c, 36 * u, Color(0.98, 0.78, 0.15))
			draw_arc(c, 24 * u, 0.0, TAU, 28, Color(0.72, 0.5, 0.05), 5 * u)
			draw_line(c + Vector2(-8 * u, 10 * u), c + Vector2(8 * u, -10 * u), Color(1, 0.95, 0.6), 5 * u)
		"stone":
			var rock := PackedVector2Array([Vector2(12, 74), Vector2(22, 38), Vector2(46, 22), Vector2(74, 30), Vector2(90, 58), Vector2(84, 78)])
			var scaled := PackedVector2Array()
			for p in rock:
				scaled.append(p * u)
			draw_colored_polygon(scaled, Color(0.62, 0.65, 0.68))
			var line := PackedVector2Array(scaled)
			line.append(scaled[0])
			draw_polyline(line, OUTLINE, 3.0 * u)
			draw_colored_polygon(PackedVector2Array([Vector2(24, 40) * u, Vector2(46, 26) * u, Vector2(62, 32) * u, Vector2(40, 50) * u]), Color(0.84, 0.86, 0.9))
		"pop":
			var house := PackedVector2Array([Vector2(50, 12), Vector2(90, 46), Vector2(78, 46), Vector2(78, 86), Vector2(22, 86), Vector2(22, 46), Vector2(10, 46)])
			var hs := PackedVector2Array()
			for p in house:
				hs.append(p * u)
			draw_colored_polygon(hs, Color(0.72, 0.86, 1.0))
			var hl := PackedVector2Array(hs)
			hl.append(hs[0])
			draw_polyline(hl, OUTLINE, 3.0 * u)
			draw_rect(Rect2(42 * u, 58 * u, 16 * u, 28 * u), Color(0.25, 0.35, 0.55))
		"up":
			for i in 2:
				var y := 14.0 + i * 32.0
				var a := PackedVector2Array([Vector2(50, y), Vector2(90, y + 36), Vector2(72, y + 44), Vector2(50, y + 22), Vector2(28, y + 44), Vector2(10, y + 36)])
				var sa := PackedVector2Array()
				for p in a:
					sa.append(p * u)
				draw_colored_polygon(sa, tint)
				var la := PackedVector2Array(sa)
				la.append(sa[0])
				draw_polyline(la, OUTLINE, 2.5 * u)
		"repair":
			draw_line(Vector2(26, 78) * u, Vector2(66, 38) * u, OUTLINE, 17 * u)
			draw_line(Vector2(26, 78) * u, Vector2(66, 38) * u, Color(0.78, 0.6, 0.35), 11 * u)
			draw_circle(Vector2(70, 32) * u, 22 * u, OUTLINE)
			draw_circle(Vector2(70, 32) * u, 17 * u, tint)
			draw_colored_polygon(PackedVector2Array([Vector2(70, 32) * u, Vector2(96, 18) * u, Vector2(96, 46) * u]), Color(0.1, 0.08, 0.06, 0.9))
		"cross":
			draw_line(Vector2(20, 20) * u, Vector2(80, 80) * u, OUTLINE, 18 * u)
			draw_line(Vector2(80, 20) * u, Vector2(20, 80) * u, OUTLINE, 18 * u)
			draw_line(Vector2(20, 20) * u, Vector2(80, 80) * u, tint, 11 * u)
			draw_line(Vector2(80, 20) * u, Vector2(20, 80) * u, tint, 11 * u)
		"shield":
			var sh := PackedVector2Array([Vector2(14, 14), Vector2(86, 14), Vector2(86, 52), Vector2(50, 92), Vector2(14, 52)])
			var ss := PackedVector2Array()
			for p in sh:
				ss.append(p * u)
			draw_colored_polygon(ss, tint)
			var sl := PackedVector2Array(ss)
			sl.append(ss[0])
			draw_polyline(sl, OUTLINE, 4.0 * u)
			draw_line(Vector2(50, 22) * u, Vector2(50, 78) * u, OUTLINE, 6 * u)
			draw_line(Vector2(24, 40) * u, Vector2(76, 40) * u, OUTLINE, 6 * u)
		"villagers":
			for off in [Vector2(-18, 6), Vector2(18, -4)]:
				draw_circle((Vector2(50, 30) + off) * u, 14 * u, OUTLINE)
				draw_circle((Vector2(50, 30) + off) * u, 10.5 * u, tint)
				var bd := PackedVector2Array([(Vector2(28, 86) + off) * u, (Vector2(35, 52) + off) * u, (Vector2(65, 52) + off) * u, (Vector2(72, 86) + off) * u])
				draw_colored_polygon(bd, tint)
				var bdl := PackedVector2Array(bd)
				bdl.append(bd[0])
				draw_polyline(bdl, OUTLINE, 2.5 * u)
		"clear":
			draw_circle(c, 40 * u, OUTLINE)
			draw_circle(c, 35 * u, Color(0.3, 0.24, 0.18))
			draw_line(Vector2(34, 34) * u, Vector2(66, 66) * u, tint, 8 * u)
			draw_line(Vector2(66, 34) * u, Vector2(34, 66) * u, tint, 8 * u)
		"swords":
			draw_line(Vector2(18, 82) * u, Vector2(74, 20) * u, OUTLINE, 14 * u)
			draw_line(Vector2(82, 82) * u, Vector2(26, 20) * u, OUTLINE, 14 * u)
			draw_line(Vector2(18, 82) * u, Vector2(74, 20) * u, tint, 8 * u)
			draw_line(Vector2(82, 82) * u, Vector2(26, 20) * u, tint, 8 * u)
		"villager":
			draw_circle(Vector2(50, 28) * u, 16 * u, OUTLINE)
			draw_circle(Vector2(50, 28) * u, 12 * u, tint)
			var body := PackedVector2Array([Vector2(24, 86) * u, Vector2(32, 50) * u, Vector2(68, 50) * u, Vector2(76, 86) * u])
			draw_colored_polygon(body, tint)
			var bl := PackedVector2Array(body)
			bl.append(body[0])
			draw_polyline(bl, OUTLINE, 3.0 * u)
		"clock":
			draw_circle(c, 40 * u, OUTLINE)
			draw_circle(c, 35 * u, Color(0.95, 0.92, 0.8))
			draw_line(c, c + Vector2(0, -24 * u), OUTLINE, 5 * u)
			draw_line(c, c + Vector2(18 * u, 8 * u), OUTLINE, 5 * u)
		"warn":
			var tri := PackedVector2Array([Vector2(50, 10) * u, Vector2(94, 86) * u, Vector2(6, 86) * u])
			draw_colored_polygon(tri, tint)
			var tl := PackedVector2Array(tri)
			tl.append(tri[0])
			draw_polyline(tl, OUTLINE, 4.0 * u)
			draw_line(Vector2(50, 36) * u, Vector2(50, 62) * u, OUTLINE, 9 * u)
			draw_circle(Vector2(50, 75) * u, 5.5 * u, OUTLINE)
		"check":
			draw_circle(c, 42 * u, OUTLINE)
			draw_circle(c, 37 * u, tint)
			draw_polyline(PackedVector2Array([Vector2(28, 52) * u, Vector2(44, 68) * u, Vector2(74, 34) * u]), OUTLINE, 9 * u)
		"info":
			draw_circle(c, 42 * u, OUTLINE)
			draw_circle(c, 37 * u, tint)
			draw_circle(Vector2(50, 28) * u, 6 * u, OUTLINE)
			draw_line(Vector2(50, 44) * u, Vector2(50, 74) * u, OUTLINE, 10 * u)


func _round_rect(r: Rect2, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = OUTLINE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(r.size.y * 0.4))
	draw_style_box(sb, r)
