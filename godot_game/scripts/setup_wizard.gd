class_name SetupWizard
extends Control
## The portable version's first start: asks for the player's own copy of Age of Empires II HD and imports the game data from it into
## the app (see Importer). Screens: welcome, folder browser, import progress (pause / resume / cancel), done, problems.

signal finished

const INK := Color(0.96, 0.91, 0.76)
const DIM := Color(0.72, 0.66, 0.5)
const GOLD := Color(0.95, 0.8, 0.4)
const EDGE := Color(0.62, 0.48, 0.24)
const GREEN := Color(0.5, 0.85, 0.4)
const RED := Color(0.95, 0.45, 0.35)

var s := 1.0
var imp: Importer
var _body: VBoxContainer
var _path := ""
var _found := ""
var _wait_for_access := false
var _bar: ProgressBar
var _stage: Label
var _detail: Label
var _time: Label
var _pause_btn: Button
var _poll := 0.0
var _mode := ""                 # "" welcome | browse | progress | done


func _ready() -> void:
	s = clampf(get_viewport_rect().size.y / 1840.0, 0.45, 1.6)
	# the parent is a plain Node, so anchors have nothing to follow: size to the window by hand
	position = Vector2.ZERO
	size = get_viewport_rect().size
	get_viewport().size_changed.connect(func() -> void: size = get_viewport_rect().size)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.055, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, int(120 * s))
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, int(60 * s))
	add_child(m)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", int(22 * s))
	m.add_child(_body)
	_request_permissions()
	_welcome()


func _process(dt: float) -> void:
	if _mode == "progress" and imp:
		_poll -= dt
		if _poll <= 0.0:
			_poll = 0.25
			_update_progress()
	elif _mode == "" and _wait_for_access and storage_ok():
		_wait_for_access = false
		_welcome()


# ------------------------------------------------------------------------------------------------ helpers

func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()


func _label(text: String, size_px: int, col := INK, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(size_px * s))
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _box(col: Color, edge: Color, radius := 14.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius * s))
	sb.border_color = edge
	sb.set_border_width_all(int(2 * s))
	sb.content_margin_left = 18 * s
	sb.content_margin_right = 18 * s
	sb.content_margin_top = 8 * s
	sb.content_margin_bottom = 8 * s
	return sb


func _button(text: String, cb: Callable, fill := Color(0.34, 0.25, 0.14), edge := EDGE, h := 100.0, size_px := 32) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h * s)
	b.add_theme_font_size_override("font_size", int(size_px * s))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.42))
	b.add_theme_stylebox_override("normal", _box(fill, edge))
	b.add_theme_stylebox_override("hover", _box(fill.lightened(0.1), edge))
	b.add_theme_stylebox_override("pressed", _box(fill.lightened(0.25), edge))
	b.add_theme_stylebox_override("disabled", _box(fill.darkened(0.35), edge.darkened(0.4)))
	b.pressed.connect(cb)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _primary(text: String, cb: Callable) -> Button:
	return _button(text, cb, Color(0.2, 0.42, 0.2), GREEN)


func _danger(text: String, cb: Callable) -> Button:
	return _button(text, cb, Color(0.45, 0.14, 0.1), Color(0.9, 0.4, 0.3))


func _row(items: Array) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", int(18 * s))
	for i: Control in items:
		r.add_child(i)
	return r


func _title(text: String) -> void:
	_body.add_child(_label(text, 64, GOLD))


# ------------------------------------------------------------------------------------------------ storage permission

static func storage_ok() -> bool:
	if not OS.has_feature("android"):
		return true
	var d := DirAccess.open("/storage/emulated/0")
	return d != null and (d.get_directories().size() + d.get_files().size()) > 0


func _request_permissions() -> void:
	if OS.has_feature("android"):
		OS.request_permissions()


## The places a game folder is likely to be: internal storage, Downloads, and any USB drive or SD card that is plugged in.
func _roots() -> Array:
	var out := []
	if OS.has_feature("android"):
		out.append(["Internal storage", "/storage/emulated/0"])
		out.append(["Downloads", "/storage/emulated/0/Download"])
		var d := DirAccess.open("/storage")
		if d:
			for sub in d.get_directories():
				if sub != "emulated" and sub != "self":
					out.append(["USB drive / SD card  " + sub, "/storage/" + sub])
	else:
		var home := OS.get_environment("HOME")
		out.append(["Home", home if home != "" else "/"])
		out.append(["Downloads", home.path_join("Downloads")])
		out.append(["Whole disk", "/"])
	return out


# ------------------------------------------------------------------------------------------------ screens

func _welcome() -> void:
	_mode = ""
	_clear()
	_title("AoE2HDBeta")
	_body.add_child(_label("This app plays with the graphics, sounds and rules of your own copy of Age of Empires II HD. Nothing of the game is inside the app: it is imported from your game files once, on this device, and kept inside the app afterwards.", 34))
	_body.add_child(_label("The import takes a while (about 5 to 50 minutes, depending on the device). You can pause it, and if it is interrupted it continues where it stopped.", 30, DIM))
	if not storage_ok():
		_body.add_child(_label("The app needs permission to read your files. Android asks for it in a separate screen: allow \"all files access\" (or storage) for this app, then come back.", 30, RED))
		_body.add_child(_row([_button("Grant access to files", func() -> void:
			_request_permissions()
			_wait_for_access = true)]))
		_wait_for_access = true
	var unfinished := Importer.has_unfinished()
	if unfinished:
		_body.add_child(_label("An earlier import was not finished.", 30, GOLD))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(18 * s))
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(col)
	var b1 := _primary("Import from the game folder", _browse)
	b1.disabled = not storage_ok()
	col.add_child(b1)
	var b2 := _button("Import from a CD or ISO image", _iso_info)
	col.add_child(b2)


func _iso_info() -> void:
	_mode = ""
	_clear()
	_title("Import from a CD or ISO image")
	_body.add_child(_label("The disc image holds the game inside an installer archive (Inno Setup, compressed). Opening that on the tablet is not built in yet.", 34))
	_body.add_child(_label("For now: install the game from the disc or ISO on a computer (or unpack the ISO there, e.g. with the free \"innoextract\" tool), copy the game folder to this tablet or a USB drive, and import it with \"Import from the game folder\".", 32, DIM))
	_body.add_child(_button("Back", _welcome))


func _browse() -> void:
	_mode = "browse"
	if _path == "":
		var r := _roots()
		_path = r[0][1]
	_show_folder()


func _show_folder() -> void:
	_clear()
	_title("Where is the game?")
	_body.add_child(_label("Open the folder that holds the game (it contains the folders Data and Bin), a USB drive or SD card with it, or a folder one or two levels above.", 28, DIM))
	var roots := _row([])
	for r: Array in _roots():
		var rb := _button(r[0], _go.bind(r[1]), Color(0.25, 0.2, 0.12), EDGE, 80, 26)
		roots.add_child(rb)
	_body.add_child(roots)
	_body.add_child(_label(_path, 28, GOLD, false))
	_found = Importer.find_game_root(_path)
	if _found != "":
		var c := Importer.check(_found)
		if c.ok:
			_body.add_child(_label("Game found: " + _found, 28, GREEN))
		else:
			var names := []
			for m: Array in c.missing:
				names.append(m[0])
			_body.add_child(_label("This folder looks like the game but is missing: " + ", ".join(names), 26, RED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", int(10 * s))
	scroll.add_child(list)
	if _path != "/" and _path != "":
		list.add_child(_button("..  (up one folder)", _go.bind(_path.get_base_dir()), Color(0.25, 0.2, 0.12), EDGE, 80, 30))
	var d := DirAccess.open(_path)
	if d == null:
		list.add_child(_label("This folder cannot be opened.", 30, RED))
	else:
		var dirs := Array(d.get_directories())
		dirs.sort_custom(func(a: String, b: String) -> bool: return a.to_lower() < b.to_lower())
		for sub: String in dirs:
			if sub.begins_with("."):
				continue
			list.add_child(_button(sub, _go.bind(_path.path_join(sub)), Color(0.3, 0.22, 0.13), EDGE, 80, 30))
		if dirs.is_empty():
			list.add_child(_label("(no folders here)", 28, DIM))
	var use := _primary("Import the game from here", func() -> void: _start(_found))
	use.disabled = _found == "" or not Importer.check(_found).ok
	_body.add_child(_row([_button("Back", _welcome), use]))


func _go(path: String) -> void:
	_path = path
	_show_folder()


func _start(root: String) -> void:
	_mode = "progress"
	imp = Importer.new()
	DisplayServer.screen_set_keep_on(true)
	imp.start(root)
	_clear()
	_title("Importing the game")
	_stage = _label("", 40, GOLD)
	_body.add_child(_stage)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 60 * s)
	_bar.min_value = 0.0
	_bar.max_value = 1000.0
	_bar.add_theme_font_size_override("font_size", int(30 * s))
	_body.add_child(_bar)
	_detail = _label("", 32)
	_body.add_child(_detail)
	_time = _label("", 28, DIM)
	_body.add_child(_time)
	_body.add_child(_label("Keep the app open and the screen on. If Android closes the app, open it again and choose the same folder: the import continues where it stopped.", 26, DIM))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(spacer)
	_pause_btn = _button("Pause", _toggle_pause)
	_body.add_child(_row([_pause_btn, _danger("Stop", _stop)]))


func _toggle_pause() -> void:
	if imp.state == "paused":
		imp.resume()
		_pause_btn.text = "Pause"
	else:
		imp.pause()
		_pause_btn.text = "Continue"


func _stop() -> void:
	imp.cancel()
	imp.wait()
	DisplayServer.screen_set_keep_on(false)
	_welcome()


func _update_progress() -> void:
	var sn := imp.snapshot()
	_stage.text = sn.stage
	_detail.text = sn.detail
	_bar.value = sn.fraction * 1000.0
	var left := ""
	if sn.eta >= 0.0:
		left = "   about %s left" % _duration(sn.eta)
	_time.text = ("Paused." if sn.state == "paused" else ("Continuing an earlier import." if sn.resumed and sn.fraction < 0.05 else "")) + left
	_bar.tooltip_text = "%d%%" % int(sn.fraction * 100.0)
	if sn.state == "done":
		DisplayServer.screen_set_keep_on(false)
		_done()
	elif sn.state == "error":
		DisplayServer.screen_set_keep_on(false)
		_failed(sn.error)


func _duration(sec: float) -> String:
	var m := int(ceil(sec / 60.0))
	return "%d min" % m if m > 1 else "a minute"


func _done() -> void:
	_mode = "done"
	_clear()
	_title("The game is ready")
	_body.add_child(_label("Everything was imported. You do not need the game folder any more; the app keeps its own copy.", 34))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(spacer)
	_body.add_child(_primary("Start the game", func() -> void: finished.emit()))


func _failed(msg: String) -> void:
	_mode = "done"
	_clear()
	_title("The import stopped")
	_body.add_child(_label(msg, 34, RED))
	_body.add_child(_label("Check that the folder is a complete copy of the game, then try again; finished parts are not redone.", 30, DIM))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(spacer)
	_body.add_child(_button("Back", _welcome))
