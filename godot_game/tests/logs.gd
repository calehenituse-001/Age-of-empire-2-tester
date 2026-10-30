extends Node
## Headless test of the debug logs:  godot --headless --path godot_game res://tests/logs.tscn

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	GameLog.delete_all()
	DirAccess.remove_absolute(GameLog.CONFIG)
	check(GameLog.sessions().is_empty() and not GameLog.enabled, "nothing is logged in a headless run until a test starts it")
	GameLog.start(true)
	check(GameLog.enabled and GameLog.path.begins_with("user://logs/session_"), "a session file is opened (%s)" % GameLog.path.get_file())
	print("hello from the game")
	GameLog.event("a wave of 12 attackers")
	push_warning("a test warning")
	var text := GameLog.read_tail(GameLog.path)
	check("[session] started" in text and "Android" in text, "it starts with what device and engine this is")
	check("hello from the game" in text, "everything the game prints goes in")
	check("[event] a wave of 12 attackers" in text, "and the events the game writes")
	check("WARNING" in text and "a test warning" in text, "and engine warnings and errors")
	var list := GameLog.sessions()
	check(list.size() == 1 and list[0].size > 100 and list[0].started != "", "the list shows it (%s, %d bytes)" % [list[0].started, list[0].size])
	# the end of an earlier run, as Android would report it
	GameLog.note_previous_exit({"reason": 5, "time": 1761000000000, "text": "crash"})
	var exits := GameLog.exits_text()
	check("CRASH_NATIVE" in exits and "a problem" in exits, "a native crash is recorded in the exit list")
	GameLog.note_previous_exit({"reason": 5, "time": 1761000000000, "text": "crash"})
	check(GameLog.exits_text().count("CRASH_NATIVE") == 1, "and only once")
	# an older session file takes the exit note
	var old := "user://logs/session_2020-01-01_00-00-00.txt"
	var f := FileAccess.open(old, FileAccess.WRITE)
	f.store_line("   0.0 [session] started long ago")
	f.store_line("  63.5 [status] up 63 s")
	f = null
	GameLog.note_previous_exit({"reason": 5, "time": 1761000500000, "text": "second"})
	var seen := GameLog.sessions()
	check(seen.size() == 2, "the older session is listed too")
	# export and delete
	var tmp := OS.get_user_data_dir() + "/exported"
	var dst := GameLog.export_file(GameLog.path, tmp)
	check(dst != "" and FileAccess.file_exists(dst), "a log can be exported to a folder (%s)" % dst.get_file())
	GameLog.delete_session(GameLog.path)
	check(not FileAccess.file_exists(GameLog.path) and not GameLog.enabled, "a log can be deleted")
	GameLog.delete_all()
	check(GameLog.sessions().is_empty() and GameLog.exits_text() == "", "and all of them")
	# the size cap
	GameLog.start(true)
	for i in 200:
		GameLog.line("x".repeat(20000))
	check(GameLog.read_tail(GameLog.path, 100).contains("nothing more is written") or GameLog.sessions()[0].size < GameLog.MAX_FILE + 30000, "a session stops at its size cap (%d bytes)" % GameLog.sessions()[0].size)
	GameLog.delete_all()
	print("RESULT: %s" % ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	get_tree().quit(fails)
