class_name ConvertAura
extends Node2D
## What a unit looks like while a monk is converting it: a golden ring on the ground that fills up, and a halo that brightens.
## Added as a child of the unit being converted, so it goes with it.

var progress := 0.0
var t := 0.0


func _ready() -> void:
	z_index = 40


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	var gold := Color(1.0, 0.85, 0.3)
	var pulse := 0.6 + 0.25 * sin(t * 6.0)
	var ring := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		ring.append(Vector2(cos(a) * 24.0, sin(a) * 12.0))
	draw_polyline(ring, Color(gold, 0.3 * pulse), 3.0)
	var arc := PackedVector2Array()
	var n := maxi(2, int(progress * 24.0) + 1)
	for i in n:
		var a := -PI / 2.0 + TAU * progress * i / float(n - 1)
		arc.append(Vector2(cos(a) * 24.0, sin(a) * 12.0))
	draw_polyline(arc, Color(gold, pulse), 4.0)
	var halo := PackedVector2Array()
	for i in 17:
		var a := TAU * i / 16.0
		halo.append(Vector2(0, -62.0 - 4.0 * sin(t * 4.0)) + Vector2(cos(a) * 13.0, sin(a) * 5.0))
	draw_polyline(halo, Color(gold, 0.25 + 0.7 * progress), 3.0)
