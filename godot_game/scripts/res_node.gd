class_name ResNode
extends Sprite2D
## A tree, berry bush, gold or stone mine: something villagers gather from.

var kind := "wood"      # what it yields: wood, food, gold, stone
var cell := Vector2i.ZERO
var amount := 100
var alive := true
var rname := ""      # which strip it was cut from (for saving)
var variant := 0
var hunt := false     # a carcass: gathered at the hunter's rate and capacity


func setup(res_kind: String, c: Vector2i, amt: int) -> void:
	kind = res_kind
	cell = c
	amount = amt

var selected := false
var _mark: Deco
var _tween: Tween


func label() -> String:
	return {"wood": "Tree", "food": "Berry bush", "gold": "Gold mine", "stone": "Stone mine"}[kind]


## A one-tile outline under the node: kept while selected, or blinked for a second as order feedback.
func _ensure_mark() -> void:
	if _mark == null:
		_mark = Deco.make(Deco.Mode.DIAMOND, Iso.HW * 0.9, Iso.HH * 0.9, Color(1.0, 0.95, 0.4))
		_mark.show_behind_parent = true
		add_child(_mark)
	if _tween:
		_tween.kill()
		_tween = null
	_mark.modulate.a = 1.0


func set_selected(v: bool) -> void:
	selected = v
	if v:
		_ensure_mark()
		_mark.visible = true
	elif _mark and (_tween == null or not _tween.is_valid()):
		_mark.visible = false


func flash() -> void:
	_ensure_mark()
	_mark.visible = true
	_tween = create_tween()
	for i in 2:
		_tween.tween_property(_mark, "modulate:a", 0.2, 0.25)
		_tween.tween_property(_mark, "modulate:a", 1.0, 0.25)
	_tween.tween_callback(func() -> void:
		_tween = null
		if not selected:
			_mark.visible = false)
