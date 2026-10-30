extends Node
## The first scene. Plays on at once when the game data is there (the development version carries it); the portable version shows
## the import wizard first.

const GAME := "res://scenes/main.tscn"


func _ready() -> void:
	if GameData.ready():
		_play.call_deferred()
		return
	var w := SetupWizard.new()
	w.finished.connect(func() -> void:
		GameData.rescan()
		Rules.reload()
		Assets.load_all()
		Sfx.reload_data()
		_play())
	add_child(w)


func _play() -> void:
	get_tree().change_scene_to_file(GAME)
