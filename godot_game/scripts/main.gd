class_name Main
extends Node
## Builds the world, the camera, the controller and the HUD, and sets up a new game.

static var map_size := 160
static var fixed_seed := -1             # tests set this for a reproducible map
static var opponent := ""             # tests set this; otherwise the saved setting decides (rival or raids)
static var pending: Dictionary = {}     # a loaded save waiting to be put into the new scene

var map: GameMap
var cam: RtsCamera
var ctl: Controller
var hud: Hud


func _ready() -> void:
	Chatter.enabled = Defs.load_chatter() and not AppRuntime.reduced_effects()
	Tombstone.enabled = Defs.load_tombs() and not AppRuntime.reduced_effects()
	map = GameMap.new()
	map.difficulty = Defs.load_difficulty()
	map.civ = int(pending.get("civ", Defs.load_civ())) if not pending.is_empty() else Defs.load_civ()
	add_child(map)
	var loading := not pending.is_empty()
	if loading:
		map_size = int(pending.size)
	map.generate(map_size, int(pending.get("seed", randi())) if loading else (fixed_seed if fixed_seed >= 0 else randi()))
	var centre := Vector2i(map_size / 2, map_size / 2)
	if not loading:
		_new_game(centre)

	cam = RtsCamera.new()
	add_child(cam)
	cam.bounds = map.world_rect()
	var vs := get_viewport().get_visible_rect().size
	var z := clampf(1.9 * vs.y / 1840.0, 0.7, 2.2)
	cam.zoom = Vector2(z, z)
	cam.position = Iso.to_world(Vector2(centre) + Vector2(1.5, 1.5))
	cam.make_current()
	if loading:
		SaveGame.restore(self, pending)
		cam.position = Vector2(float(pending.cam[0]), float(pending.cam[1]))
		cam.zoom = Vector2(float(pending.zoom), float(pending.zoom))
		pending = {}
	Sfx.cam = cam

	ctl = Controller.new()
	ctl.map = map
	ctl.cam = cam
	add_child(ctl)
	cam.tapped.connect(ctl.on_tap)

	hud = Hud.new()
	add_child(hud)
	hud.build(map, ctl)
	cam.ui_blocks = hud.blocks
	cam.lasso_ok = func() -> bool: return ctl.placing == ""
	cam.lasso_started.connect(ctl.cancel_pending_move)
	cam.lasso_drawing.connect(func() -> void: ctl.toast("Draw a loop round the units"))
	cam.lasso_changed.connect(hud.lasso.set_points)
	cam.lasso_ended.connect(ctl.select_in_lasso)
	var overlay := CheatOverlay.new()
	add_child(overlay)
	overlay.setup(self)
	Assets.release_terrain_cpu_cache()


var _auto_t := 120.0


## Autosave every two minutes, and whenever the app goes to the background.
var _log_t := 0.0


## One line every 30 seconds in the log: what the game looked like just before anything went wrong.
func _status() -> void:
	print("[status] up %d s, game %d s x%.0f, fps %d, mobs %d, buildings %d+%d, nodes %d, objects %d, script mem %d MB, video mem %d MB, textures %d MB, draw calls %d" % [
		Time.get_ticks_msec() / 1000, int(map.game_time), map.speed, int(Engine.get_frames_per_second()), map.mobs.size(), map.buildings.size(), map.foes.size(),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0), int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])


func _process(dt: float) -> void:
	_log_t -= dt
	if _log_t <= 0.0:
		_log_t = 30.0
		_status()
	if map.finished:
		return
	_auto_t -= dt
	if _auto_t <= 0.0:
		_auto_t = 120.0
		SaveGame.write(SaveGame.AUTO, self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED and map != null and not map.finished and cam != null:
		SaveGame.write(SaveGame.AUTO, self)


func _new_game(centre: Vector2i) -> void:
	GameLog.event("new game at %s" % centre)
	var tc_origin := centre - Vector2i(2, 2)
	map.place_building("tc", tc_origin, true)
	# starting resources close to the town centre
	map.scatter_clump("berries", centre + Vector2i(-9, 6), 6, 1.4)
	map.scatter_clump("gold", centre + Vector2i(9, -8), 6, 1.5)
	map.scatter_clump("stone", centre + Vector2i(-8, -9), 5, 1.4)
	# the rest of the map
	var area := float(map_size * map_size)
	for i in int(area / 2600.0):
		map.scatter_clump("gold", _far_spot(centre), 5, 1.6)
	for i in int(area / 3200.0):
		map.scatter_clump("stone", _far_spot(centre), 5, 1.6)
	for i in int(area / 2200.0):
		map.scatter_clump("berries", _far_spot(centre), 5, 1.5)
	map.scatter_fish()
	map.scatter_relics(5, centre)
	map.scatter_forests(centre, 10.0)
	for i in 5:
		var v := map.make_unit("villager", 0, Vector2(centre) + Vector2(-2 + i, 3.0))
		v.stand()
	for i in 2:
		map.make_unit("74", 0, Vector2(centre) + Vector2(3 + i, 3.0))
	# what some civilizations start with or without
	var start: Dictionary = Defs.CIV_START.get(map.civ, {})
	for r: String in ["wood", "food", "gold", "stone"]:
		map.stock[r] = maxi(0, int(map.stock[r]) + int(start.get(r, 0)))
	for i in int(start.get("villagers", 0)):
		var v2 := map.make_unit("villager", 0, Vector2(centre) + Vector2(-4 + i, 4.5))
		v2.stand()
	map.opponent = opponent if opponent != "" else Defs.load_opponent()
	if map.opponent == "rival":
		map.start_rival(centre)
	map.recalc_pop()
	map.director.populate_wild(int(map.director.wild_cap() * 0.7))


func _far_spot(centre: Vector2i) -> Vector2i:
	for i in 30:
		var c := Vector2i(map.rng.randi_range(6, map_size - 7), map.rng.randi_range(6, map_size - 7))
		if Vector2(c).distance_to(Vector2(centre)) > 18.0:
			return c
	return Vector2i(6, 6)
