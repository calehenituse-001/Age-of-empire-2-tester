extends Node
## In-process bridge configuration is separate from cheat policy and mod registry.
var root := ""
var config: Dictionary = {}
var cheats := CheatPolicy.new()
var mods := ModRegistry.new()
var safe_mode := false
var resume_game := true
var bridge: Object
var overlay: CanvasLayer

func _ready() -> void:
	root = ProjectSettings.globalize_path("user://AgeOfEmpires2")
	if OS.has_feature("Android") and Engine.has_singleton("LauncherBridge"):
		bridge = Engine.get_singleton("LauncherBridge")
		root = bridge.rootPath()
		safe_mode = bridge.safeMode()
		resume_game = bridge.resumeGame()
	elif OS.get_environment("AOE_LAUNCHER_ROOT") != "":
		root = OS.get_environment("AOE_LAUNCHER_ROOT")
	for folder in ["Launcher", "GameData", "Mods", "Cheats", "Config", "Saves", "Logs"]:
		DirAccess.make_dir_recursive_absolute(root.path_join(folder))
	config = read_json("Config/launcher.json")
	if not config.get("preset") in ["LOW", "BALANCED", "HIGH"]:
		config.preset = "BALANCED"
	if not ModRegistry.integer(config, "resolutionPercent", 50, 100):
		config.resolutionPercent = {"LOW": 70, "BALANCED": 85, "HIGH": 100}[config.preset]
	if not ModRegistry.integer(config, "mapSize", 96, 160):
		config.mapSize = 128
	if not config.get("difficulty") in ["easy", "medium", "hard"]:
		config.difficulty = "medium"
	if not config.get("opponent") in ["rival", "raids"]:
		config.opponent = "rival"
	config.diagnostics = config.get("diagnostics") is bool and config.get("diagnostics", false) == true
	cheats.configure(read_json("Cheats/config.json"))
	cheats.safe_mode = safe_mode
	cheats.offline = true
	cheats.session_check = is_offline
	var enabled: Variant = read_json("Config/mods.json").get("enabled", [])
	if not enabled is Array:
		mods.error = "Invalid mod selection. Use Safe Mode and reselect mods."
	elif not safe_mode:
		mods.prepare(root.path_join("Mods"), enabled)
	SaveGame.MANUAL = save_path("save.json")
	SaveGame.AUTO = save_path("autosave.json")
	Importer.DEST = root.path_join("GameData/importing")
	Engine.max_fps = 30 if config.preset == "LOW" else 60
	apply_resolution.call_deferred()
	print("[launcher] Godot ", Engine.get_version_info().string, " renderer=gl_compatibility profile=", mods.fingerprint)

func is_offline() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer == null or peer is OfflineMultiplayerPeer

func apply_resolution() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var win := get_window()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	win.content_scale_size = Vector2i(Vector2(win.size) * float(config.resolutionPercent) / 100.0)

func save_path(name: String) -> String:
	var folder := root.path_join("Saves").path_join(mods.fingerprint)
	DirAccess.make_dir_recursive_absolute(folder)
	return folder.path_join(name)

func read_json(path: String) -> Dictionary:
	return ModRegistry._json(root.path_join(path))

func write_json(path: String, data: Dictionary) -> bool:
	var dest := root.path_join(path)
	var f := FileAccess.open(dest + ".part", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.flush()
	var err := f.get_error()
	f.close()
	return err == OK and DirAccess.rename_absolute(dest + ".part", dest) == OK

func save_cheats() -> bool:
	return write_json("Cheats/config.json", cheats.values)

func reduced_effects() -> bool:
	return config.get("preset") == "LOW"

func cache_budget() -> int:
	return int({"LOW": 64, "BALANCED": 128, "HIGH": 192}.get(config.get("preset"), 128)) * 1024 * 1024

func blocks(point: Vector2) -> bool:
	return is_instance_valid(overlay) and overlay.blocks(point)

func diagnostics() -> String:
	var mb: float = float(OS.get_static_memory_usage()) / 1048576.0
	var label := "heap"
	if bridge:
		mb = float(bridge.processMemoryMb())
		label = "PSS"
	return "%.0f FPS · %.0f MB %s · %d draws" % [Engine.get_frames_per_second(), mb, label, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]
