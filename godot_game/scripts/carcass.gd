class_name Carcass
extends ResNode
## What a dead deer or boar leaves: meat for villagers to gather. It lies the way the animal fell and rots away after a while.

const LIFE := 160.0
var life := LIFE


func setup_carcass(a: Animal) -> void:
	setup("food", a.cell(), a.food())
	rname = "carcass"
	hunt = true
	position = a.position
	var key := a.anim("die")
	var anim: Dictionary = Assets.anim(key)
	texture = anim.tex
	centered = false
	region_enabled = true
	var dir: int = a.get("_dir")
	var stored := dir if dir <= 4 else 8 - dir
	stored = mini(stored, anim.frames.size() - 1)
	var last := int(anim.fpa) - 1
	var f: Array = anim.frames[stored][last]
	region_rect = Rect2(last * int(anim.cw) + int(anim.pad), stored * int(anim.ch) + int(anim.pad), f[0], f[1])
	flip_h = dir > 4
	offset = Vector2(-(f[0] - f[2]) if flip_h else -f[2], -f[3])


func label() -> String:
	return "Carcass"


## Returns false when it has rotted away.
func tick(dt: float) -> bool:
	life -= dt
	modulate.a = clampf(life / 12.0, 0.0, 1.0)
	return life > 0.0 and alive
