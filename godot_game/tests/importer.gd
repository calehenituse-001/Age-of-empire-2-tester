extends Node
## godot --headless --path godot_game res://tests/importer.tscn
##   GAME = install folder; MODE = full (default) | resume (cancel after a few seconds, start again, check the result)
## Imports into user://gamedata/ (it is erased first) and checks the result.

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	var game := OS.get_environment("GAME") if OS.get_environment("GAME") != "" else "/home/j3rry/AOE"
	check(Importer.find_game_root(game.get_base_dir()) == game or Importer.find_game_root(game) == game, "the game folder is found from its parent too")
	var bad := Importer.check("/tmp")
	check(not bad.ok and bad.missing.size() == Importer.REQUIRED.size(), "an unrelated folder is refused")
	check(Importer.check(game).ok, "the install passes the check")
	Importer.erase()
	check(not GameData.ready() or GameData.bundled(), "no imported data after erase")
	var imp := Importer.new()
	var t := Time.get_ticks_msec()
	imp.start(game)
	if OS.get_environment("MODE") == "resume":
		await get_tree().create_timer(6.0).timeout
		imp.pause()
		await get_tree().create_timer(1.0).timeout
		var a := imp.snapshot()
		await get_tree().create_timer(2.0).timeout
		var b := imp.snapshot()
		check(a.state == "paused" and a.fraction == b.fraction, "pause holds the import (%.1f%%)" % (a.fraction * 100.0))
		imp.cancel()
		imp.wait()
		check(imp.state == "cancelled" and Importer.has_unfinished(), "cancel leaves a resumable state")
		imp = Importer.new()
		imp.start(game)
	while imp.state == "running" or imp.state == "paused":
		await get_tree().create_timer(2.0).timeout
		var s := imp.snapshot()
		print("  %.0f%%  %s - %s" % [s.fraction * 100.0, s.stage, s.detail])
	imp.wait()
	check(imp.state == "done", "the import finishes (%s %s) in %d s" % [imp.state, imp.error, (Time.get_ticks_msec() - t) / 1000])
	if OS.get_environment("MODE") == "resume":
		check(imp.resumed, "the second run continued the first")
	check(Importer.complete(), "it is marked complete")
	GameData.rescan()
	check(GameData.ready(), "the game data is found")
	print("RESULT: ", "ALL PASS" if fails == 0 else "%d FAILED" % fails)
	get_tree().quit()
