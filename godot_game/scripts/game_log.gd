extends Node
## Debug logs kept on the device, one text file per session (`user://logs/session_2026-10-22_13-05-41.txt`), for when the tablet is not
## attached to a computer. Everything the game prints and every engine error goes in (a custom Logger), plus the lines the game writes itself
## (a status line every 30 s, slow frames, events). While USB debugging has a cable plugged in, logcat can be read from the computer, so nothing
## is stored then, unless "Always log" is on. At the next start the reason the app's previous process ended (a crash, the system killing it, the
## user closing it) is read from Android (ApplicationExitInfo) and written to `exits.txt` and to the log it belongs to.
## The Logs window of the menu lists, shows, exports, shares and deletes the files.

const DIR := "user://logs"
const KEEP := 30                    # sessions kept
const MAX_FILE := 3_000_000         # bytes written to one session before it stops (the end of the file says so)
const MAX_TOTAL := 40_000_000
const CONFIG := "user://logs.cfg"
const EXIT_NAMES := {1: "EXIT_SELF", 2: "SIGNALED", 3: "LOW_MEMORY", 4: "CRASH", 5: "CRASH_NATIVE", 6: "ANR", 7: "INITIALIZATION_FAILURE",
	8: "PERMISSION_CHANGE", 9: "EXCESSIVE_RESOURCE_USAGE", 10: "USER_REQUESTED", 11: "USER_STOPPED", 12: "DEPENDENCY_DIED", 13: "OTHER",
	14: "FREEZER", 15: "PACKAGE_STATE_CHANGE", 16: "PACKAGE_UPDATED"}
const BAD_EXITS := [3, 4, 5, 6, 7, 9]

var enabled := false                # this session is being written
var always := false                 # also log with USB debugging attached
var path := ""                      # the file of this session
var adb_note := ""                  # what was found out about USB debugging
var _file: FileAccess
var _mutex := Mutex.new()
var _written := 0
var _capped := false
var _sink: Sink
var _t0 := 0


## The engine's Logger: every print and error goes through here (from any thread).
class Sink extends Logger:
	var target: Node

	func _log_message(message: String, error: bool) -> void:
		target.line(("E " if error else "") + message.strip_edges(false, true))

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array) -> void:
		target.line("%s %s:%d %s %s" % [["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)], file.get_file(), line, function, rationale if rationale != "" else code])


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	var cf := ConfigFile.new()
	if cf.load(CONFIG) == OK:
		always = bool(cf.get_value("log", "always", false))
	DirAccess.make_dir_recursive_absolute(DIR)
	_check_previous_exit()
	if DisplayServer.get_name() == "headless":
		return                       # the tests do not write logs (they call start() themselves when they test this)
	start()


## Opens this session's file when logging applies (no USB debugging attached, or "Always log").
func start(force := false) -> void:
	var st := adb_state()
	adb_note = "USB debugging %s, cable %s" % ["on" if st.adb else "off", "plugged" if st.usb else "unplugged"]
	var attached: bool = st.adb and st.usb
	enabled = force or always or not attached
	if not enabled:
		return
	_prune()
	var d := Time.get_datetime_dict_from_system()
	path = "%s/session_%04d-%02d-%02d_%02d-%02d-%02d.txt" % [DIR, d.year, d.month, d.day, d.hour, d.minute, d.second]
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		enabled = false
		return
	_sink = Sink.new()
	_sink.target = self
	OS.add_logger(_sink)
	line("[session] started %s" % Time.get_datetime_string_from_system())
	line("[session] %s, Android %s, %s, %s" % [OS.get_model_name(), OS.get_version(), OS.get_distribution_name(), "debug build" if OS.is_debug_build() else "release build"])
	line("[session] engine %s, screen %s, %s" % [Engine.get_version_info().string, DisplayServer.window_get_size(), adb_note])


func set_always(v: bool) -> void:
	always = v
	var cf := ConfigFile.new()
	cf.load(CONFIG)
	cf.set_value("log", "always", v)
	cf.save(CONFIG)


## One line with the time since the session began. Safe to call from anywhere (a no-op when not logging).
func line(text: String) -> void:
	if not enabled or _file == null:
		return
	_mutex.lock()
	if _written < MAX_FILE:
		var s := "%7.1f %s\n" % [(Time.get_ticks_msec() - _t0) / 1000.0, text]
		_file.store_string(s)
		_file.flush()
		_written += s.length()
	elif not _capped:
		_capped = true
		_file.store_string("[session] file is full (%d bytes): nothing more is written\n" % MAX_FILE)
		_file.flush()
	_mutex.unlock()


func event(text: String) -> void:
	line("[event] " + text)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		line("[session] closed by the user")
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		line("[session] app went to the background")
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		line("[session] app is back")


# ------------------------------------------------------------------ what Android says
func _activity() -> Object:
	if not OS.has_feature("android") or not Engine.has_singleton("AndroidRuntime"):
		return null
	return Engine.get_singleton("AndroidRuntime").getActivity()


## {"adb": USB debugging switched on, "usb": a cable is plugged in}. A cable and debugging together count as attached to a computer.
func adb_state() -> Dictionary:
	var out := {"adb": false, "usb": false}
	var act := _activity()
	if act == null:
		return out
	var g: Object = JavaClassWrapper.wrap("android.provider.Settings$Global")
	if g:
		out.adb = int(g.getInt(act.getContentResolver(), "adb_enabled", 0)) == 1
	var f: Object = JavaClassWrapper.wrap("android.content.IntentFilter")
	if f:
		var battery: Object = act.registerReceiver(null, f.IntentFilter("android.intent.action.BATTERY_CHANGED"))
		if battery:
			out.usb = (int(battery.getIntExtra("plugged", 0)) & 2) != 0
	return out


## The newest entry of Android's list of how this app's earlier processes ended, as {"reason", "time", "text"}; {} when unknown.
func previous_exit() -> Dictionary:
	var act := _activity()
	if act == null:
		return {}
	var am: Object = act.getSystemService("activity")
	if am == null:
		return {}
	var list: Object = am.getHistoricalProcessExitReasons(null, 0, 1)
	if list == null or int(list.size()) == 0:
		return {}
	var e: Object = list.call("get", 0)          # (a Java List.get(int); Object.get() would be the property getter)
	return {"reason": int(e.getReason()), "time": int(e.getTimestamp()), "text": str(e.getDescription())}


func _check_previous_exit() -> void:
	note_previous_exit(previous_exit())


## Writes how the previous run ended to exits.txt and to the end of the newest session file (it is that run's log). Once per exit.
func note_previous_exit(e: Dictionary) -> void:
	if e.is_empty():
		return
	var cf := ConfigFile.new()
	cf.load(CONFIG)
	if int(cf.get_value("log", "last_exit", 0)) >= int(e.time):
		return
	cf.set_value("log", "last_exit", int(e.time))
	cf.save(CONFIG)
	var name: String = EXIT_NAMES.get(int(e.reason), "UNKNOWN %d" % int(e.reason))
	var stamp := Time.get_datetime_string_from_unix_time(int(e.time) / 1000, true)
	var msg := "[exit] the previous run ended: %s at %s %s" % [name, stamp, str(e.text)]
	var f := FileAccess.open(DIR + "/exits.txt", FileAccess.READ_WRITE if FileAccess.file_exists(DIR + "/exits.txt") else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line("%s  %s%s" % [stamp, name, "  <-- a problem" if int(e.reason) in BAD_EXITS else ""] + ("  " + str(e.text) if str(e.text) != "" else ""))
	var files := sessions()
	if not files.is_empty() and files[0].path != path:
		var g := FileAccess.open(files[0].path, FileAccess.READ_WRITE)
		if g:
			g.seek_end()
			g.store_line(msg)


# ------------------------------------------------------------------ managing the files
## The session files, newest first: {name, path, size, started (text), seconds, errors, exit (text or "")}.
func sessions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.begins_with("session_") and f.ends_with(".txt"):
			var p := DIR + "/" + f
			var info := _inspect(p)
			info.name = f
			info.path = p
			info.started = _nice(f)
			out.append(info)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name > b.name)
	return out


func _nice(f: String) -> String:
	var s := f.trim_prefix("session_").trim_suffix(".txt")
	var parts := s.split("_")
	if parts.size() != 2:
		return s
	return parts[0] + "  " + parts[1].replace("-", ":")


## Size, how long it ran (the time of its last line), how many errors, and how the run ended if that is in the file.
func _inspect(p: String) -> Dictionary:
	var out := {"size": 0, "seconds": 0, "errors": 0, "exit": "", "bad": false}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return out
	out.size = f.get_length()
	var last := 0.0
	while not f.eof_reached():
		var l := f.get_line()
		if l.length() > 8:
			var t := l.substr(0, 7).strip_edges()
			if t.is_valid_float():
				last = maxf(last, t.to_float())
		if "ERROR" in l:
			out.errors += 1
		if l.begins_with("[exit]"):
			out.exit = l.trim_prefix("[exit] the previous run ended: ")
			for r: int in BAD_EXITS:
				if EXIT_NAMES[r] in l:
					out.bad = true
	out.seconds = int(last)
	return out


func read_tail(p: String, max_bytes := 200_000) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var n := f.get_length()
	if n > max_bytes:
		f.seek(n - max_bytes)
		f.get_line()                    # (the first line is cut)
		return "... (the first %d bytes are left out)\n%s" % [n - max_bytes, f.get_as_text()]
	return f.get_as_text()


func delete_session(p: String) -> void:
	if p == path:
		_mutex.lock()
		_file = null
		enabled = false
		_mutex.unlock()
	DirAccess.remove_absolute(p)


func delete_all() -> void:
	for s in sessions():
		delete_session(s.path)
	DirAccess.remove_absolute(DIR + "/exits.txt")


## Keeps the newest KEEP sessions and at most MAX_TOTAL bytes in all.
func _prune() -> void:
	var all := sessions()
	var total := 0
	for i in all.size():
		total += int(all[i].size)
		if i >= KEEP - 1 or total > MAX_TOTAL:
			DirAccess.remove_absolute(all[i].path)


func exits_text() -> String:
	var f := FileAccess.open(DIR + "/exits.txt", FileAccess.READ)
	return f.get_as_text() if f else ""


## Copies a session file to the device's Downloads folder (AoE2HDBeta/logs). Returns the new path, or "" when the folder cannot be written
## (Android 11 and later needs "All files access" for this).
func export_file(p: String, folder := "") -> String:
	var dir := folder if folder != "" else OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS) + "/AoE2HDBeta/logs"
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	var dst := dir + "/" + p.get_file()
	var src := FileAccess.open(p, FileAccess.READ)
	var out := FileAccess.open(dst, FileAccess.WRITE)
	if src == null or out == null:
		return ""
	out.store_buffer(src.get_buffer(src.get_length()))
	return dst


## The share sheet with the log as text (the newest part when it is long); the text goes to the clipboard when that does not work.
func share_text(p: String, mail_to := false) -> String:
	var text := read_tail(p, 150_000)
	var act := _activity()
	if act != null:
		var ok := _android_share(act, "Age of Android log " + p.get_file(), text, mail_to)
		if ok:
			return "share"
	DisplayServer.clipboard_set(text)
	return "clipboard"


func _android_share(act: Object, subject: String, text: String, mail_to: bool) -> bool:
	var intent_class: Object = JavaClassWrapper.wrap("android.content.Intent")
	if intent_class == null:
		return false
	var intent: Object = intent_class.Intent("android.intent.action.SENDTO" if mail_to else "android.intent.action.SEND")
	if mail_to:
		var uri_class: Object = JavaClassWrapper.wrap("android.net.Uri")
		intent.setData(uri_class.parse("mailto:"))
	else:
		intent.setType("text/plain")
	intent.putExtra("android.intent.extra.SUBJECT", subject)
	intent.putExtra("android.intent.extra.TEXT", text)
	var chooser: Object = intent_class.createChooser(intent, "Send the log")
	act.startActivity(chooser)
	return true
