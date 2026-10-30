class_name RtsCamera
extends Camera2D
## Touch camera: one finger drags, two fingers pinch-zoom (and pan), a short still touch is a tap. A double tap whose second touch stays
## down and draws is a lasso: the map stands still and the loop is reported (`lasso_*`) to select the units inside it.
## Mouse input is turned into touch events by the project settings, so desktop testing works the same;
## the wheel also zooms.

signal tapped(world_pos: Vector2)
signal lasso_started                # the second touch of a double tap is down: a move order the first tap gave must be held back
signal lasso_drawing                # and it has begun to draw
signal lasso_changed(points: PackedVector2Array)
signal lasso_ended(points: PackedVector2Array)

const MIN_ZOOM := 0.35
const MAX_ZOOM := 2.5
const TAP_SLOP := 14.0
const TAP_TIME_MS := 350
const DOUBLE_MS := 300             # the second touch of a double tap comes this soon after the first one is lifted
const DOUBLE_DIST := 90.0          # and this close to it (screen pixels)

var bounds := Rect2()
## Optional callable(screen_pos) -> bool; touches that start on UI are ignored by the camera.
var ui_blocks: Callable = Callable()
## Optional callable() -> bool: whether a lasso may start now (not while a building is being placed).
var lasso_ok: Callable = Callable()

var _touch: Dictionary = {}       # finger index -> current screen position
var _start_pos := Vector2.ZERO
var _start_ms := 0
var _moved := false
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO
var _ignored: Dictionary = {}     # fingers that started on UI
var _last_tap_ms := -100000
var _last_tap_pos := Vector2.ZERO
var _lasso := false
var _lasso_armed := false          # the second touch of a double tap is down but has not moved yet: it may still be an ordinary tap
var _lasso_pts := PackedVector2Array()


func screen_to_world(p: Vector2) -> Vector2:
	return position + (p - get_viewport_rect().size * 0.5) / zoom.x


func world_to_screen(w: Vector2) -> Vector2:
	return (w - position) * zoom.x + get_viewport_rect().size * 0.5


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		_on_touch(e)
	elif e is InputEventScreenDrag:
		_on_drag(e)
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(e.position, 1.15)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(e.position, 1.0 / 1.15)


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		if ui_blocks.is_valid() and ui_blocks.call(e.position):
			_ignored[e.index] = true
			return
		_touch[e.index] = e.position
		if _touch.size() == 1:
			_start_pos = e.position
			_start_ms = Time.get_ticks_msec()
			_moved = false
			if _start_ms - _last_tap_ms < DOUBLE_MS and e.position.distance_to(_last_tap_pos) < DOUBLE_DIST \
					and (not lasso_ok.is_valid() or lasso_ok.call()):
				_lasso_armed = true                 # a double tap that stays down and moves: draw the loop, the map stands still
				_last_tap_ms = -100000
				lasso_started.emit()
		elif _touch.size() == 2:
			_lasso_armed = false
			if _lasso:
				_end_lasso(true)
			_moved = true
			_begin_pinch()
	else:
		if _ignored.erase(e.index):
			return
		if _lasso:
			_touch.erase(e.index)
			_end_lasso(false)
			return
		_lasso_armed = false                    # (it did not move: the second tap of a double tap is an ordinary tap)
		if _touch.size() == 1 and not _moved and Time.get_ticks_msec() - _start_ms < TAP_TIME_MS:
			_last_tap_ms = Time.get_ticks_msec()
			_last_tap_pos = e.position
			tapped.emit(screen_to_world(e.position))
		_touch.erase(e.index)
		if _touch.size() == 2:
			_begin_pinch()


func _on_drag(e: InputEventScreenDrag) -> void:
	if _ignored.has(e.index) or not _touch.has(e.index):
		return
	_touch[e.index] = e.position
	if _lasso_armed and _touch.size() == 1:
		if e.position.distance_to(_start_pos) <= TAP_SLOP:
			return                              # still the same spot: no panning either
		_lasso_armed = false
		_lasso = true
		_moved = true
		_lasso_pts = PackedVector2Array([_start_pos])
		lasso_drawing.emit()
	if _lasso:
		if _touch.size() == 1 and (_lasso_pts.is_empty() or e.position.distance_to(_lasso_pts[_lasso_pts.size() - 1]) > 6.0):
			_lasso_pts.append(e.position)
			lasso_changed.emit(_lasso_pts)
		return
	if _touch.size() == 1:
		if not _moved and e.position.distance_to(_start_pos) > TAP_SLOP:
			_moved = true
		if _moved:
			position -= e.relative / zoom.x
			_clamp()
	elif _touch.size() == 2:
		var pts: Array = _touch.values()
		var dist: float = pts[0].distance_to(pts[1])
		var mid: Vector2 = (pts[0] + pts[1]) * 0.5
		if _pinch_dist > 1.0:
			_zoom_at(mid, dist / _pinch_dist)
		position -= (mid - _pinch_mid) / zoom.x
		_pinch_dist = dist
		_pinch_mid = mid
		_clamp()


func _end_lasso(cancelled: bool) -> void:
	var pts := PackedVector2Array() if cancelled else _lasso_pts
	_lasso = false
	_lasso_pts = PackedVector2Array()
	lasso_changed.emit(PackedVector2Array())
	lasso_ended.emit(pts)


## Centres the view on a world position (used by the minimap).
func look_at_world(w: Vector2) -> void:
	position = w
	_clamp()


func _begin_pinch() -> void:
	var pts: Array = _touch.values()
	_pinch_dist = pts[0].distance_to(pts[1])
	_pinch_mid = (pts[0] + pts[1]) * 0.5


func _zoom_at(screen: Vector2, factor: float) -> void:
	var before := screen_to_world(screen)
	var z := clampf(zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(z, z)
	position = before - (screen - get_viewport_rect().size * 0.5) / z
	_clamp()


func _clamp() -> void:
	if bounds.size != Vector2.ZERO:
		position = position.clamp(bounds.position, bounds.end)
