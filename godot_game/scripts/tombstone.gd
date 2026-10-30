class_name Tombstone
extends Sprite2D
## Marks where a villager or soldier fell: appears when the corpse is gone, stays 10 seconds, then fades out.
## Driven by the game clock, so it waits while the game is paused.

const STAY := 10.0
const FADE := 1.5

static var _tex: Texture2D
static var enabled := true          # the Settings menu can turn tombstones off

var t := 0.0


static func spawn(map: GameMap, pos: Vector2) -> void:
	if not enabled:
		return
	if _tex == null:
		_tex = load("res://assets/tombstone.png")
	var s := Tombstone.new()
	s.texture = _tex
	s.centered = false
	s.offset = Vector2(-_tex.get_width() * 0.5, -_tex.get_height() + 6.0)
	s.position = pos
	map.entities.add_child(s)
	map.tombs.append(s)
	s.modulate.a = 0.0


## Returns false when it is done and should be removed.
func tick(dt: float) -> bool:
	t += dt
	if t < 0.4:
		modulate.a = t / 0.4
	elif t < STAY:
		modulate.a = 1.0
	else:
		modulate.a = clampf(1.0 - (t - STAY) / FADE, 0.0, 1.0)
	return t < STAY + FADE
