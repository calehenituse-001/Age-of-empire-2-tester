extends Node
## godot --headless --path godot_game res://tests/wizard.tscn   (walks through the import wizard's screens; GAME = install folder)

var fails := 0
var done := false


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	var game := OS.get_environment("GAME") if OS.get_environment("GAME") != "" else "/home/j3rry/AOE"
	Importer.erase()
	var w := SetupWizard.new()
	w.finished.connect(func() -> void: done = true)
	add_child(w)
	await get_tree().process_frame
	check(w._body.get_child_count() > 3, "the welcome screen is built")
	w._iso_info()
	await get_tree().process_frame
	check(w._body.get_child_count() >= 3, "the ISO screen explains the situation")
	w._welcome()
	w._browse()
	await get_tree().process_frame
	check(w._path != "" and w._body.get_child_count() > 4, "the folder browser opens at " + w._path)
	w._go(game.get_base_dir())
	await get_tree().process_frame
	check(w._found == game, "the game is found from the folder above it (%s)" % w._found)
	w._go("/tmp")
	await get_tree().process_frame
	check(w._found == "", "an unrelated folder finds nothing")
	w._start(game)
	var t := Time.get_ticks_msec()
	while w._mode != "done" and Time.get_ticks_msec() - t < 300000:
		await get_tree().create_timer(1.0).timeout
	check(w._mode == "done" and w._body.get_child_count() >= 3, "the import ends on the ready screen (%d s)" % ((Time.get_ticks_msec() - t) / 1000))
	await get_tree().process_frame
	(w._body.get_child(w._body.get_child_count() - 1) as Button).pressed.emit()
	check(done, "the wizard reports it is finished (%d s)" % ((Time.get_ticks_msec() - t) / 1000))
	check(Importer.complete(), "and the data is complete")
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
