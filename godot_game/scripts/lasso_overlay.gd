class_name LassoOverlay
extends Control
## The loop drawn with a finger to select a group: a gold line with a faint fill, closed back to where it began. Lives on the HUD layer in screen coordinates.

var points := PackedVector2Array()
var scale_ui := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func set_points(p: PackedVector2Array) -> void:
	points = p
	queue_redraw()


func _draw() -> void:
	if points.size() < 2:
		return
	var gold := Color(1.0, 0.86, 0.35)
	if points.size() >= 3:
		if not Geometry2D.triangulate_polygon(points).is_empty():
			draw_colored_polygon(points, Color(gold, 0.13))
	draw_polyline(points, Color(0.1, 0.07, 0.0, 0.75), 9.0 * scale_ui)
	draw_polyline(points, gold, 5.0 * scale_ui)
	draw_dashed_line(points[points.size() - 1], points[0], Color(gold, 0.7), 3.0 * scale_ui, 14.0 * scale_ui)
	draw_circle(points[0], 9.0 * scale_ui, gold)
