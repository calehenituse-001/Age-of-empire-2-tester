class_name TargetMarker
extends Node2D
## Red bobbing arrow and crosshair ring on an enemy or animal that soldiers were ordered to attack.
## (The original's converging red arrows, graphic MOVETO, are in assets/aoe/a_marker_target.png, unused.)

const LIFE := 3.0

var t := 0.0


func _process(delta: float) -> void:
	t += delta
	if t >= LIFE:
		queue_free()
		return
	modulate.a = (1.0 if int(t * 6.0) % 2 == 0 else 0.45) * (1.0 if t < LIFE - 0.5 else (LIFE - t) / 0.5)
	queue_redraw()


func _draw() -> void:
	var red := Color(1.0, 0.16, 0.12)
	var ring := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		ring.append(Vector2(cos(a) * 30.0, sin(a) * 15.0))
	draw_polyline(ring, red, 5.0)
	for d: Vector2 in [Vector2(-1, 0), Vector2(1, 0)]:
		draw_line(d * 22.0, d * 40.0, red, 5.0)
	var tip := Vector2(0, -78.0 - absf(sin(t * 7.0)) * 12.0)
	var pts := PackedVector2Array([tip, tip + Vector2(-20, -26), tip + Vector2(-8, -26), tip + Vector2(-8, -60),
		tip + Vector2(8, -60), tip + Vector2(8, -26), tip + Vector2(20, -26)])
	draw_colored_polygon(pts, red)
	var o := PackedVector2Array(pts)
	o.append(pts[0])
	draw_polyline(o, Color(0.3, 0.0, 0.0), 3.0)
