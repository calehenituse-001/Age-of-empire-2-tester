class_name Unit
extends Sprite2D
## An animated, direction-aware sprite. Position is the unit's feet; `tp` is the same spot in tile coordinates.

var tp := Vector2.ZERO
var key := ""
var loop := true
var done := false

var _anim: Dictionary = {}
var _dir := 0
var _frame := 0
var _t := 0.0


func _init() -> void:
	centered = false
	region_enabled = true


func place(p: Vector2) -> void:
	tp = p
	position = Iso.to_world(p)


func play(anim_key: String, looping := true, force := false) -> void:
	if anim_key == key and looping == loop and not force:
		return
	key = anim_key
	loop = looping
	_anim = Assets.anim(anim_key)
	texture = _anim.tex
	_frame = 0
	_t = 0.0
	done = false
	_apply()


## Seconds one pass through the current animation takes.
func anim_total() -> float:
	return int(_anim.fpa) * float(_anim.dur)


func face(dir8: int) -> void:
	if dir8 != _dir:
		_dir = dir8
		_apply()


func face_towards(dx: float, dy: float) -> void:
	if absf(dx) + absf(dy) > 0.001:
		face(Iso.dir8(dx, dy))


## Per-frame update; subclasses add behaviour on top of the animation.
func tick(dt: float) -> void:
	advance(dt)


func advance(dt: float) -> void:
	var n := int(_anim.fpa)
	if n <= 1 or done:
		return
	_t += dt
	var d := float(_anim.dur)
	var moved := false
	while _t >= d:
		_t -= d
		moved = true
		if _frame + 1 < n:
			_frame += 1
		elif loop:
			_frame = 0
		else:
			done = true
			break
	if moved:
		_apply()


func _apply() -> void:
	var stored := _dir if _dir <= 4 else 8 - _dir
	stored = mini(stored, _anim.frames.size() - 1)      # some animations (a sinking ship) have one angle only
	var f: Array = _anim.frames[stored][_frame]
	region_rect = Rect2(_frame * int(_anim.cw) + int(_anim.pad), stored * int(_anim.ch) + int(_anim.pad), f[0], f[1])
	flip_h = _dir > 4 and _anim.frames.size() > 1
	offset = Vector2(-(f[0] - f[2]) if flip_h else -f[2], -f[3])
