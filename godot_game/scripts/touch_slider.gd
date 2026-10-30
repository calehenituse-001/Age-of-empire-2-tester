class_name TouchSlider
extends Control
## A horizontal slider that answers to touch (the stock HSlider ignores touches when mouse emulation is off).

signal value_changed(value: float)
signal drag_ended

var value := 0.5
var dragging := false

var _touch := -1

var _knob := 34.0
var _track := Color(0.25, 0.19, 0.11)
var _fill := Color(0.8, 0.6, 0.25)


func setup(v: float, knob_radius: float) -> void:
	value = clampf(v, 0.0, 1.0)
	_knob = knob_radius
	custom_minimum_size.y = knob_radius * 2.0 + 6.0
	queue_redraw()


## Touches are read straight from the input, so no GUI routing can swallow the drag.
func _input(e: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if e is InputEventScreenTouch:
		if e.pressed and get_global_rect().has_point(e.position):
			dragging = true
			_touch = e.index
			_set_from(e.position.x - get_global_rect().position.x)
			get_viewport().set_input_as_handled()
		elif not e.pressed and dragging and e.index == _touch:
			dragging = false
			drag_ended.emit()
			get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag and dragging and e.index == _touch:
		_set_from(e.position.x - get_global_rect().position.x)
		get_viewport().set_input_as_handled()


## The mouse, for running on a computer.
func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			dragging = true
			_touch = -1
			_set_from(e.position.x)
		elif dragging and _touch == -1:
			dragging = false
			drag_ended.emit()
		accept_event()
	elif e is InputEventMouseMotion and dragging and _touch == -1:
		_set_from(e.position.x)
		accept_event()


func _set_from(x: float) -> void:
	var v := clampf((x - _knob) / maxf(1.0, size.x - 2.0 * _knob), 0.0, 1.0)
	if not is_equal_approx(v, value):
		value = v
		value_changed.emit(value)
		queue_redraw()


func _draw() -> void:
	var cy := size.y * 0.5
	var x0 := _knob
	var x1 := size.x - _knob
	var th := maxf(10.0, _knob * 0.3)
	draw_rect(Rect2(x0 - th * 0.5, cy - th * 0.5, x1 - x0 + th, th), _track)
	draw_rect(Rect2(x0 - th * 0.5, cy - th * 0.5, (x1 - x0) * value + th * 0.5, th), _fill)
	var c := Vector2(x0 + (x1 - x0) * value, cy)
	draw_circle(c, _knob, Color(0.35, 0.22, 0.08))
	draw_circle(c, _knob - 6.0, Color(0.98, 0.9, 0.62))
