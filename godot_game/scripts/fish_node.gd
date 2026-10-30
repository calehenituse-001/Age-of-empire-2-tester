class_name FishNode
extends ResNode
## A school of fish in deep water: fishing ships gather its food. It plays the original's swimming and jumping
## animation and keeps a faint ripple so it can be found between jumps.

var uid := 455
var _anim: Dictionary = {}
var _frame := 0
var _t := 0.0


func setup_fish(unit_id: int, c: Vector2i, amt: int) -> void:
	uid = unit_id
	setup("fish", c, amt)
	rname = "fish"
	variant = unit_id
	_anim = Assets.anim("u%d_idle_blue" % unit_id)
	texture = _anim.tex
	centered = false
	region_enabled = true
	_frame = randi() % int(_anim.fpa)
	_apply()


func label() -> String:
	return "Fish"


func tick(dt: float) -> void:
	_t += dt
	var d := float(_anim.dur)
	var moved := false
	while _t >= d:
		_t -= d
		_frame = (_frame + 1) % int(_anim.fpa)
		moved = true
	if moved:
		_apply()


func _apply() -> void:
	var f: Array = _anim.frames[0][_frame]
	region_rect = Rect2(_frame * int(_anim.cw) + int(_anim.pad), int(_anim.pad), f[0], f[1])
	offset = Vector2(-f[2], -f[3])


func _draw() -> void:
	var pts := PackedVector2Array()
	for i in 21:
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a) * 15.0, sin(a) * 7.5))
	draw_polyline(pts, Color(1, 1, 1, 0.3), 2.0)
