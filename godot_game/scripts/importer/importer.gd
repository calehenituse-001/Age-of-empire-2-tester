class_name Importer
extends RefCounted
## Builds the game's data (user://gamedata/) from the player's own copy of Age of Empires II HD, on the device. Runs in a thread, in
## stages that can be paused and resumed: every finished stage and every few finished sprites are recorded in progress.json, so a
## cancelled or killed import goes on where it stopped.

const VERSION := 1
static var DEST := "user://gamedata"

## Files the import cannot do without (relative to the game folder), and what they are for.
const REQUIRED := {
	"Data/empires2_x1_p1.dat": "the game rules", "Data/graphics.drs": "sprites", "Data/interfac.drs": "palette and cursors",
	"Data/terrain.drs": "terrain tiles", "Data/sounds.drs": "sound effects", "Data/sounds_x1.drs": "sound effects (expansion)",
	"Data/blendomatic_x1.dat": "terrain blending", "Data/pal_2.pal": "tree colours", "Data/pal_4.pal": "tree colours",
	"Data/Slp/foak_nn.slp": "oak trees", "Data/Slp/fpin_nn.slp": "pine trees", "Bin/en/language.dll": "names and descriptions",
}
const OPTIONAL := {
	"Bin/en/language_x1.dll": "names (expansion)", "Bin/en/language_x1_p1.dll": "names (patch)",
	"Sound/music/music1.mp3": "music", "Sound/music/xmusic1.mp3": "music",
}
# stage -> [label, weight in the progress bar]
const STAGES := [["rules", "Reading the game rules", 4.0], ["base", "Terrain, trees, villagers and soldiers", 6.0],
	["units", "Units and buildings", 72.0], ["terrain", "Terrain blending", 4.0], ["sounds", "Sounds and music", 14.0]]

var source := ""
var state := "idle"                 # idle | running | paused | done | error | cancelled
var stage_label := ""
var detail := ""
var error := ""
var started_ms := 0
var resumed := false                # this run continued an earlier one

var _stage_frac := 0.0
var _stage_index := 0
var _thread: Thread
var _mutex := Mutex.new()
var _pause := false
var _cancel := false
var _busy_ms := 0                   # time spent working (not paused), for the estimate
var _last_tick := 0


## Looks for the game folder at `path` or one or two levels below it. Returns "" when it is not there.
static func find_game_root(path: String) -> String:
	var up := path                       # inside the game's own Data or Bin folder: the game is one level up
	if path.get_file().to_lower() in ["data", "bin", "slp", "en", "music", "sound"]:
		up = path.get_base_dir()
		if up.get_file().to_lower() in ["data", "bin", "sound"]:
			up = up.get_base_dir()
	for depth in 3:
		var found := _find(up, depth)
		if found != "":
			return found
	return ""


static func _find(path: String, depth: int) -> String:
	if depth == 0:
		# a folder with a Data folder counts too, so that an incomplete copy is reported with what is missing
		return path if DirAccess.dir_exists_absolute(path.path_join("Data")) and (DirAccess.dir_exists_absolute(path.path_join("Bin")) or FileAccess.file_exists(path.path_join("Data/empires2_x1_p1.dat"))) else ""
	var d := DirAccess.open(path)
	if d == null:
		return ""
	for sub in d.get_directories():
		var r := _find(path.path_join(sub), depth - 1)
		if r != "":
			return r
	return ""


## {ok, missing: [[path, what]], notes: [what is optional and absent]}
static func check(root: String) -> Dictionary:
	var missing := []
	for f: String in REQUIRED:
		if not FileAccess.file_exists(root.path_join(f)):
			missing.append([f, REQUIRED[f]])
	var notes := []
	for f: String in OPTIONAL:
		if not FileAccess.file_exists(root.path_join(f)):
			notes.append("%s (%s) is missing; the game works without it" % [f, OPTIONAL[f]])
	return {"ok": missing.is_empty(), "missing": missing, "notes": notes}


## Is there a finished import?
static func complete() -> bool:
	return FileAccess.file_exists(DEST + "/.complete")


static func has_unfinished() -> bool:
	return FileAccess.file_exists(DEST + "/progress.json") and not complete()


## Removes everything imported (to import again, or to free the space).
static func erase() -> void:
	_rmdir(DEST)
	GameData.rescan()


static func _rmdir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for s in d.get_directories():
		_rmdir(path.path_join(s))
		d.remove(s)
	DirAccess.remove_absolute(path)


func start(game_root: String) -> void:
	source = game_root
	state = "running"
	error = ""
	_cancel = false
	_pause = false
	started_ms = Time.get_ticks_msec()
	_last_tick = started_ms
	_busy_ms = 0
	_thread = Thread.new()
	_thread.start(_run)


func pause() -> void:
	_mutex.lock()
	_pause = true
	if state == "running":
		state = "paused"
	_mutex.unlock()


func resume() -> void:
	_mutex.lock()
	_pause = false
	if state == "paused":
		state = "running"
		_last_tick = Time.get_ticks_msec()
	_mutex.unlock()


func cancel() -> void:
	_cancel = true
	_pause = false


## For the user interface: {state, stage, detail, fraction, eta (seconds, -1 unknown), error}
func snapshot() -> Dictionary:
	_mutex.lock()
	var total := 0.0
	var before := 0.0
	for i in STAGES.size():
		total += float(STAGES[i][2])
		if i < _stage_index:
			before += float(STAGES[i][2])
	var cur := 0.0
	if _stage_index < STAGES.size():
		cur = STAGES[_stage_index][2]
	var frac: float = 1.0 if state == "done" else (before + _stage_frac * cur) / total
	var eta := -1.0
	if frac > 0.03 and state != "done":
		eta = _busy_ms / 1000.0 / frac * (1.0 - frac)
	var s := {"state": state, "stage": stage_label, "detail": detail, "fraction": frac, "eta": eta, "error": error, "resumed": resumed}
	_mutex.unlock()
	return s


func wait() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


# ------------------------------------------------------------------------------------------------ the work

func _tick() -> void:
	var now := Time.get_ticks_msec()
	_mutex.lock()
	if state == "running":
		_busy_ms += now - _last_tick
	_last_tick = now
	_mutex.unlock()


## Called between pieces of work: lets a pause hold the import here.
func _checkpoint() -> bool:
	_tick()
	while _pause and not _cancel:
		OS.delay_msec(100)
	_last_tick = Time.get_ticks_msec()
	return not _cancel


func _fail(msg: String) -> void:
	_mutex.lock()
	state = "error"
	error = msg
	_mutex.unlock()
	push_error("import: " + msg)


func _read_progress() -> Dictionary:
	var p := DEST + "/progress.json"
	if FileAccess.file_exists(p):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary and int(d.get("version", 0)) == VERSION and d.get("source", "") == source:
			return d
	return {"version": VERSION, "source": source, "done": [], "units_next": 0}


func _write_progress(p: Dictionary) -> void:
	_write(DEST + "/progress.json", JSON.stringify(p))


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path + ".part", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()
	DirAccess.rename_absolute(path + ".part", path)


func _json(path: String) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func _say(text: String) -> void:
	_mutex.lock()
	detail = text
	_mutex.unlock()
	_checkpoint()


func _run() -> void:
	var chk := check(source)
	if not chk.ok:
		_fail("Files are missing in " + source)
		return
	DirAccess.make_dir_recursive_absolute(DEST + "/data")
	var prog := _read_progress()
	if (prog.done as Array).size() > 0 or int(prog.units_next) > 0:
		resumed = true
	if FileAccess.file_exists(DEST + "/.complete"):
		DirAccess.remove_absolute(DEST + "/.complete")
	for i in STAGES.size():
		var key: String = STAGES[i][0]
		_mutex.lock()
		_stage_index = i
		_stage_frac = 0.0
		stage_label = STAGES[i][1]
		_mutex.unlock()
		if key in prog.done:
			continue
		if not _checkpoint():
			break
		if not _stage(key, prog):
			if _cancel:
				break
			return
		(prog.done as Array).append(key)
		_write_progress(prog)
	if _cancel:
		_mutex.lock()
		state = "cancelled"
		_mutex.unlock()
		return
	_write(DEST + "/.complete", str(VERSION))
	DirAccess.remove_absolute(DEST + "/progress.json")
	DirAccess.remove_absolute(DEST + "/units.part.json")
	GameData.rescan()
	_mutex.lock()
	state = "done"
	_stage_frac = 1.0
	detail = ""
	_mutex.unlock()


func _stage(key: String, prog: Dictionary) -> bool:
	var dat_path := source.path_join("Data/empires2_x1_p1.dat")
	match key:
		"rules":
			_say("Unpacking the rules file")
			var raw := Inflate.raw(FileAccess.get_file_as_bytes(dat_path), 0)
			if raw.size() < 1000000:
				_fail("The rules file (empires2_x1_p1.dat) could not be unpacked")
				return false
			_say("Reading units, buildings and technologies")
			var dat := DatReader.new().read(raw)
			if dat.is_empty():
				_fail("The rules file has an unknown layout")
				return false
			_say("Reading names and descriptions")
			var strings := PeStrings.read_all(source)
			_say("Building the rules tables")
			var built := RulesBuilder.new().build(dat, strings)
			_write(DEST + "/data/rules.json", JSON.stringify(built.rules))
			_write(DEST + "/data/graphics.json", JSON.stringify(built.graphics))
			return true
		"base":
			var man := BaseSprites.new(source, DEST, func(t: String) -> void: _say(t)).run()
			_write(DEST + "/manifest.json", JSON.stringify(man))
			return true
		"units":
			var ux := UnitExtract.new(source, DEST, _json(DEST + "/data/rules.json"), _json(DEST + "/data/graphics.json"))
			var next := int(prog.units_next)
			if next > 0 and FileAccess.file_exists(DEST + "/units.part.json"):
				ux.man = _json(DEST + "/units.part.json")
			else:
				next = 0
			var n := ux.tasks.size()
			for i in range(next, n):
				if not _checkpoint():
					return false
				_mutex.lock()
				_stage_frac = float(i) / n
				detail = ux.describe(i)
				_mutex.unlock()
				ux.run_task(i)
				if i % 20 == 19:
					_write(DEST + "/units.part.json", JSON.stringify(ux.man))
					prog.units_next = i + 1
					_write_progress(prog)
			_write(DEST + "/units.json", JSON.stringify(ux.man))
			return true
		"terrain":
			var man := TerrainExtract.new(source, DEST, _json(DEST + "/data/rules.json"), func(t: String) -> void: _say(t)).run()
			_write(DEST + "/terrain.json", JSON.stringify(man))
			return true
		"sounds":
			var dat := DatReader.new().read(Inflate.raw(FileAccess.get_file_as_bytes(dat_path), 0))
			if SoundExtract.run(source, DEST, dat, func(t: String) -> void: _say(t)) == 0:
				_fail("No sounds could be read")
				return false
			return true
	return false
