class_name MoveMarker
extends Node2D
## Four arrows closing in on the spot units were sent to, as in the original game: they slide in, loop a few times and fade. Drawn from a
## vector picture (assets/marker_arrow.svg, imported at 4x) so that they stay sharp on any screen; the original's sprites were small pixel art.
## The arrows are laid out on the ground and the whole marker is squashed to the game's 2:1 view.

const LIFE := 2.4
const CYCLE := 0.8
const LENGTH := 20.0                    # ground units from tail to tip (about 70 pixels across the whole marker in the 2:1 view)
const GAP_FAR := 29.0                   # distance of the tips from the spot when they start and when they arrive
const GAP_NEAR := 6.0
const TEX_SCALE := 4.0                  # the import scale of the svg
const TIP := Vector2(122.0, 32.0)       # the arrow's tip in the svg's own units
const BODY := 118.0                     # its length in svg units (4 to 122)

var t := 0.0
var _arms: Array[Node2D] = []


func _ready() -> void:
	transform = Transform2D(Vector2(0.70711, 0.35355), Vector2(-0.70711, 0.35355), position)      # (keeps the spot it was put at)
	var tex: Texture2D = load("res://assets/marker_arrow.svg")
	for i in 4:
		var arm := Node2D.new()
		arm.rotation = i * PI / 2.0
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.offset = -TIP * TEX_SCALE
		spr.scale = Vector2.ONE * (LENGTH / BODY / TEX_SCALE)
		arm.add_child(spr)
		add_child(arm)
		_arms.append(arm)
	_place()


func _place() -> void:
	var ph := fmod(t, CYCLE) / CYCLE
	var gap := lerpf(GAP_FAR, GAP_NEAR, ph * ph * (3.0 - 2.0 * ph))
	for arm in _arms:
		arm.position = -Vector2.RIGHT.rotated(arm.rotation) * gap


func _process(delta: float) -> void:
	t += delta
	if t >= LIFE:
		queue_free()
		return
	modulate.a = 1.0 if t < LIFE - 0.4 else (LIFE - t) / 0.4
	_place()
