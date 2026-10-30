class_name Deco
extends Node2D
## Small overlays drawn by units and buildings: a selection ring, a footprint outline or a health bar.

enum Mode { ELLIPSE, DIAMOND, BAR }

var mode := Mode.ELLIPSE
var half_w := 18.0
var half_h := 9.0
var frac := 1.0
var color := Color(0.35, 1.0, 0.35)
var fixed := false        # bars keep their colour instead of going green to red
var fill := 0.0           # alpha of the translucent fill of an ellipse


static func make(m: Mode, w: float, h: float, col: Color) -> Deco:
	var d := Deco.new()
	d.mode = m
	d.half_w = w
	d.half_h = h
	d.color = col
	return d


func set_frac(f: float) -> void:
	frac = clampf(f, 0.0, 1.0)
	if mode == Mode.BAR and not fixed:
		color = Color(1.0 - frac, 0.2 + 0.8 * frac, 0.15)
	queue_redraw()


func _draw() -> void:
	match mode:
		Mode.ELLIPSE:
			var pts := PackedVector2Array()
			for i in 25:
				var a := TAU * i / 24.0
				pts.append(Vector2(cos(a) * half_w, sin(a) * half_h))
			if fill > 0.0:
				draw_colored_polygon(pts.slice(0, 24), Color(color.r, color.g, color.b, fill))
			draw_polyline(pts, color, 2.5)
		Mode.DIAMOND:
			var pts := PackedVector2Array([Vector2(0, -half_h), Vector2(half_w, 0), Vector2(0, half_h), Vector2(-half_w, 0), Vector2(0, -half_h)])
			draw_colored_polygon(pts.slice(0, 4), Color(color.r, color.g, color.b, 0.16))
			draw_polyline(pts, color, 4.0)
		Mode.BAR:
			draw_rect(Rect2(-half_w - 1, -1, half_w * 2 + 2, half_h + 2), Color(0, 0, 0, 0.8))
			draw_rect(Rect2(-half_w, 0, half_w * 2 * frac, half_h), color)
