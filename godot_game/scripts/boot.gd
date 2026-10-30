extends Node
## Converts only user-imported files. The previous complete import survives failure.
var importer: Importer
var label: Label
var progress: ProgressBar
var cancel_button: Button
var revision := ""
var finished := false

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("0e1916")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var column := VBoxContainer.new()
	column.position = Vector2(32, 40)
	column.size = Vector2(get_viewport().get_visible_rect().size.x - 64, 450)
	bg.add_child(column)
	label = Label.new()
	label.add_theme_font_size_override("font_size", 28)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "Preparing Age of Empires II…"
	column.add_child(label)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 32
	column.add_child(progress)
	cancel_button = Button.new()
	cancel_button.text = "Cancel / Return to Launcher"
	cancel_button.custom_minimum_size.y = 64
	cancel_button.add_theme_font_size_override("font_size", 26)
	cancel_button.pressed.connect(_cancel)
	column.add_child(cancel_button)
	if not AppRuntime.mods.error.is_empty():
		_fail(AppRuntime.mods.error + "\nReturn and use Safe Mode.")
		return
	var raw := AppRuntime.root.path_join("GameData/raw")
	revision = FileAccess.get_file_as_string(raw.path_join(".revision")) if FileAccess.file_exists(raw.path_join(".revision")) else ""
	var imported := GameData.imported_root().trim_suffix("/")
	if ImportActivation.recover_missing(imported):
		print("[launcher] Recovered prior game data after interrupted activation")
		GameData.rescan()
		Rules.reload()
		Assets.load_all()
		Sfx.reload_data()
	var revision_marker := imported.path_join(".revision")
	var old_revision := FileAccess.get_file_as_string(revision_marker) if FileAccess.file_exists(revision_marker) else ""
	if GameData.ready() and (GameData.bundled() or (revision != "" and revision == old_revision)):
		_start_game.call_deferred()
		return
	var check := Importer.check(raw)
	if not check.ok:
		_fail("Game files are missing. Return to GAME FILE MANAGER and import your own HD folder.\n" + str(check.missing))
		print("[launcher] BOOT_READY_MISSING_DATA")
		return
	var marker := Importer.DEST.path_join(".revision")
	if not FileAccess.file_exists(marker) or FileAccess.get_file_as_string(marker) != revision:
		Importer.erase()
	DirAccess.make_dir_recursive_absolute(Importer.DEST)
	var f := FileAccess.open(marker, FileAccess.WRITE)
	if f == null:
		_fail("Cannot write import staging folder. Check free storage.")
		return
	f.store_string(revision)
	f.close()
	importer = Importer.new()
	importer.start(raw)

func _process(_dt: float) -> void:
	if importer == null or finished:
		return
	var s := importer.snapshot()
	label.text = "%s\n%s\nKeep this screen open. Conversion resumes after interruption." % [s.stage, s.detail]
	progress.value = float(s.fraction) * 100.0
	if s.state == "error":
		importer.wait()
		_fail("Import failed: " + str(s.error))
	elif s.state == "done":
		importer.wait()
		finished = true
		var dest := GameData.imported_root().trim_suffix("/")
		var promotion_error := ImportActivation.promote(Importer.DEST, dest)
		if not promotion_error.is_empty():
			_fail(promotion_error + "\nPrevious data was not discarded.")
			return
		GameData.rescan()
		Rules.reload()
		Assets.load_all()
		Sfx.reload_data()
		if not Rules.loaded or Assets.man.is_empty() or not AppRuntime.mods.error.is_empty():
			var had_previous := DirAccess.dir_exists_absolute(dest + ".previous")
			var restored := ImportActivation.rollback(dest)
			GameData.rescan()
			Rules.reload()
			Assets.load_all()
			Sfx.reload_data()
			var outcome := ("Previous import restored." if had_previous else
				"Invalid import discarded; no previous import existed.") if restored else
				"Recovery failed; the previous import may still be available as .previous."
			_fail("Imported game data failed runtime initialization. " + outcome +
				"\nCheck Logs/godot.log before importing again.")
			return
		ImportActivation.commit(dest)
		_start_game.call_deferred()

func _start_game() -> void:
	if not Rules.loaded or Assets.man.is_empty() or not AppRuntime.mods.error.is_empty():
		_fail("Game data/registry initialization failed. " + AppRuntime.mods.error + "\nSee Logs/godot.log, or reimport compatible HD files.")
		return
	label.text = "Creating world…"
	await get_tree().process_frame
	Main.map_size = int(AppRuntime.config.mapSize)
	Main.pending = SaveGame.read(SaveGame.AUTO) if AppRuntime.resume_game else {}
	if Main.pending.is_empty():
		var c := ConfigFile.new()
		c.load(Defs.GAME_CONFIG)
		c.set_value("game", "difficulty", AppRuntime.config.difficulty)
		c.set_value("game", "opponent", AppRuntime.config.opponent)
		c.save(Defs.GAME_CONFIG)
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _fail(message: String) -> void:
	finished = true
	label.text = message
	progress.visible = false
	print("[launcher] ", message)

func _cancel() -> void:
	if importer:
		importer.cancel()
		importer.wait()
	get_tree().quit()

func _exit_tree() -> void:
	if importer:
		importer.cancel()
		importer.wait()
