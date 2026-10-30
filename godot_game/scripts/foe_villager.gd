class_name FoeVillager
extends Mob
## One of the rival's workers. It does what the player's villagers do: builds what the Rival has placed, fells trees, mines gold
## and stone, forages berries and works farms, and carries every load to the nearest drop-off of the rival, where it becomes the
## rival's stock. The Rival (assign) decides what each one does next. Killing one costs the rival that worker and its income.

enum S { IDLE, GOTO, WORK, RETURN }

var male := true
var state := S.IDLE
var job := ""                  # "build" | "gather" | "farm"
var site: FoeBuilding
var res: ResNode
var farm: FoeBuilding
var gather_kind := ""          # wood, food, gold or stone: what the job yields
var carry_kind := ""
var carry_n := 0
var drop: FoeBuilding
var _acc := 0.0
var _idle := 0.0
var _snd := 0.0


func setup(m: GameMap, is_male: bool) -> void:
	init_mob(m, "villager", Defs.UNITS["villager"], 1)
	male = is_male
	pre = "vm_" if male else "vf_"
	bar_y = 52.0
	var s := _stats()
	max_hp = float(s.hp)
	hp = max_hp
	material = FoeBuilding.red_material()
	_idle = randf()
	stand()


func armor() -> Dictionary:
	return _stats().arm


func _stats() -> Dictionary:
	return map.rival.tech.stats(83) if map.rival and map.rival.tech else Combat.base_stats(83)


## Research (Loom) changed the villager's hit points and armour.
func refresh_stats() -> void:
	var want := float(_stats().hp)
	if not is_equal_approx(want, max_hp):
		hp += want - max_hp
		max_hp = want


func death_effect() -> String:
	return "death_m" if male else "death_f"


func die() -> void:
	_release()
	if map.rival:
		map.rival.on_worker_died(self)
	super.die()


func tick(dt: float) -> void:
	if garrison_target and garrison_tick(dt, _walk()):
		advance(dt)
		return
	match state:
		S.IDLE:
			if not path.is_empty():
				follow(dt, pre + "walk")
			else:
				_idle -= dt
				if _idle <= 0.0:
					_idle = 1.0
					_pick()
		S.GOTO:
			follow(dt, _walk())
			if path.is_empty():
				if _target_ok():
					state = S.WORK
					_acc = 0.0
					_face()
					play(pre + _work_anim())
				else:
					_to_idle()
		S.WORK:
			_work(dt)
		S.RETURN:
			follow(dt, _walk())
			if path.is_empty():
				_deposit()
	advance(dt)


func _walk() -> String:
	if carry_n > 0:
		return pre + {"wood": "carry_wood", "food": "carry_food"}.get(carry_kind, "carry_ore")
	return pre + "walk"


func _work_anim() -> String:
	match job:
		"build":
			return "build"
		"farm":
			return "farm"
	return {"wood": "chop", "food": "forage"}.get(gather_kind, "mine")


func on_unloaded() -> void:
	_to_idle()


func _release() -> void:
	garrison_target = null
	if is_instance_valid(farm) and farm.farmer == self:
		farm.farmer = null
	site = null
	res = null
	farm = null


func _to_idle() -> void:
	_release()
	state = S.IDLE
	job = ""
	_idle = 0.2
	stand()


func _target_ok() -> bool:
	match job:
		"build":
			return is_instance_valid(site) and site.alive and not site.done
		"farm":
			return is_instance_valid(farm) and farm.alive and farm.done
		"gather":
			return is_instance_valid(res) and res.alive
	return false


func _face() -> void:
	var p := tp
	if job == "build" and site:
		p = map.nearest_point(site, tp)
	elif job == "farm" and farm:
		p = farm.tp
	elif res:
		p = Vector2(res.cell)
	face_towards(p.x - tp.x, p.y - tp.y)


func _go_farm() -> bool:
	var r := farm.rect()
	return go_to(Vector2i(clampi(roundi(tp.x), r.position.x, r.end.x - 1), clampi(roundi(tp.y), r.position.y, r.end.y - 1)))


## Asks the rival what to do next: something to build, a resource, or a farm.
func _pick() -> void:
	if map.rival == null:
		return
	var j: Dictionary = map.rival.assign(self)
	if not j.is_empty():
		_start(j)


## The rival orders this villager off whatever it does to a new job (a house that must go up, a farm nobody works).
func command(j: Dictionary) -> void:
	_release()
	path.clear()
	state = S.IDLE
	_start(j)


func _start(j: Dictionary) -> void:
	job = String(j.job)
	match job:
		"garrison":
			if not order_garrison(j.bld):
				_to_idle()
			return
		"build":
			site = j.site
			if not go_adjacent(site.rect()):
				map.rival.mark_site_bad(site)
				_to_idle()
				return
		"farm":
			farm = j.farm
			farm.farmer = self
			gather_kind = "food"
			if not _go_farm():
				_to_idle()
				return
		_:
			res = j.res
			gather_kind = String(j.kind)
			if not go_adjacent(Rect2i(res.cell, Vector2i.ONE)):
				map.rival.mark_unreachable(res)
				_to_idle()
				return
	state = S.GOTO


func _work_sound(dt: float) -> void:
	_snd -= dt
	if _snd > 0.0:
		return
	var effect := ""
	match job:
		"build":
			effect = "hammer"
			_snd = 0.5
		"farm":
			effect = "farm"
			_snd = 1.6
		"gather":
			effect = {"wood": "chop", "food": "gather", "gold": "ore", "stone": "ore"}[gather_kind]
			_snd = {"chop": 0.8, "gather": 1.3, "ore": 0.9}[effect]
	if effect != "":
		Sfx.at(effect, position)


func _work(dt: float) -> void:
	if not _target_ok():
		if carry_n > 0:
			_begin_return()
		else:
			_to_idle()
		return
	_work_sound(dt)
	match job:
		"build":
			site.help_build(dt)
		"farm":
			if farm.food <= 0.0 and not map.rival.reseed(farm):
				_to_idle()
				return
			_acc += map.rival.rate("farm") * dt
			while _acc >= 1.0 and farm.food > 0.0:
				_acc -= 1.0
				farm.food -= 1.0
				carry_n += 1
				carry_kind = "food"
			if carry_n >= map.rival.cap("farm"):
				farm.queue_redraw()
				_begin_return()
		"gather":
			_acc += map.rival.rate(gather_kind) * dt
			while _acc >= 1.0 and res:
				_acc -= 1.0
				res.amount -= 1
				carry_n += 1
				carry_kind = res.kind
				if res.amount <= 0:
					map.remove_res(res)
					res = null
			if res == null or carry_n >= map.rival.cap(gather_kind):
				_begin_return()


func _begin_return() -> void:
	var b: FoeBuilding = map.rival.dropoff(carry_kind, tp)
	if b == null or not go_adjacent(b.rect()):
		carry_n = 0
		_to_idle()
		return
	drop = b
	state = S.RETURN


## The load becomes the rival's stock; then the same work goes on while it lasts, else the rival picks a new one.
func _deposit() -> void:
	if carry_n > 0 and map.rival:
		map.rival.stock[carry_kind] += carry_n
		map.rival.gathered[carry_kind] += carry_n
	carry_n = 0
	drop = null
	if _target_ok() and map.rival and map.rival.keeps(self):
		var ok := false
		match job:
			"farm":
				ok = _go_farm()
			"gather":
				ok = go_adjacent(Rect2i(res.cell, Vector2i.ONE))
		if ok:
			state = S.GOTO
			return
	_to_idle()
