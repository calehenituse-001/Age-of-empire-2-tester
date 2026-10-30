class_name Relic
extends Unit
## One of the golden reliquaries lying about the map (the original's Relic, unit 285). A monk of ours picks it up, carries it and puts
## it in a Monastery, which then pays gold for it as long as it stands. A relic is on the ground, in a monk's arms or in a Monastery.

const GOLD_RATE := 0.5          # gold per second (game seconds) for each relic inside a Monastery

var map: GameMap
var alive := true
var carrier: Mob = null
var holder: Building = null


func setup(m: GameMap, p: Vector2) -> void:
	map = m
	play("u285_idle_blue")
	place(p)


func on_ground() -> bool:
	return carrier == null and holder == null


## A monk takes it: it disappears from the map until he puts it down.
func pick_up(by: Mob) -> void:
	carrier = by
	holder = null
	visible = false


func drop(at: Vector2) -> void:
	carrier = null
	holder = null
	visible = true
	place(at)


func store(b: Building) -> void:
	carrier = null
	holder = b
	visible = false
	b.relics.append(self)
