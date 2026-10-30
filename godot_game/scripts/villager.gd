class_name Villager
extends Mob
## Works on orders: gather from a resource, farm, build, or walk somewhere. Gatherers carry what they
## collect to the nearest suitable drop-off and come back on their own until the resource runs out.

enum S { IDLE, GOTO, WORK, RETURN }


var male := true
var state := S.IDLE
var job := ""                  # "", "gather", "farm", "build", "repair", "hunt"
var prey: Mob
var _prey_pos := Vector2.ZERO
var gather_kind := ""
var res: ResNode
var farm: Building
var site: Building
var build_queue: Array[Building] = []   # more pieces to build after this one (walls)
var drop: Building
var carry_kind := ""
var carry_n := 0
var _acc := 0.0
var _msg_cd := 0.0
var _aggro := 0.0
var _snd := 0.0
var _idle_t := 0.5
var _hurt_say := -10.0
var _resume_job := ""            # what to go back to after a repair ordered from the building's button
var _resume_target: Object = null


func setup(m: GameMap, is_male: bool) -> void:
	init_mob(m, "villager", Defs.UNITS["villager"], 0)
	male = is_male
	pre = "vm_" if male else "vf_"
	bar_y = 52.0
	refresh_stats()
	stand()


## Hit points follow the player's research (Loom).
func refresh_stats() -> void:
	var want := float(map.tech.stats(83).hp)
	if not is_equal_approx(want, max_hp):
		hp += want - max_hp
		max_hp = want


func death_effect() -> String:
	return "death_m" if male else "death_f"


func speed_mult() -> float:
	return map.walk_factor()


func armor() -> Dictionary:
	return map.tech.stats(83).arm


func is_idle() -> bool:
	return state == S.IDLE and path.is_empty()


func status_text() -> String:
	match state:
		S.GOTO:
			return "walking to work"
		S.WORK:
			return {"gather": "gathering", "farm": "farming", "build": "building", "repair": "repairing", "hunt": "hunting"}.get(job, "working")
		S.RETURN:
			return "carrying %d %s" % [carry_n, carry_kind]
	return "idle" if path.is_empty() else "walking"


# ------------------------------------------------------------------ orders
func order_move(c: Vector2i) -> void:
	_clear_job()
	state = S.IDLE
	go_to(c)


func order_gather(r: ResNode) -> void:
	_clear_job()
	if carry_n > 0 and carry_kind != r.kind:
		carry_n = 0
	job = "gather"
	res = r
	gather_kind = r.kind
	_start_goto()


func on_unloaded() -> void:
	state = S.IDLE
	job = ""
	super.on_unloaded()


## Goes after a deer or boar and kills it (villagers fight with their own attack), then gathers the meat.
func order_hunt(a: Mob) -> void:
	_clear_job()
	job = "hunt"
	prey = a
	_prey_pos = a.tp
	state = S.IDLE


func _hunt_ai(dt: float) -> void:
	if not valid(prey):
		var carcass := map.carcass_near(_prey_pos)
		_clear_job()
		state = S.IDLE
		target = null
		if carcass != null:
			order_gather(carcass)
		else:
			stand()
		return
	_prey_pos = prey.tp
	target = prey
	if not combat(dt, pre + "walk"):
		_clear_job()
		state = S.IDLE
		target = null
		stand()


## What a villager hits with (the data's attack, so Loom and the like count) and how often.
func atk_dict() -> Dictionary:
	return map.tech.stats(83).atk


func reload() -> float:
	return float(map.tech.stats(83).reload) / Rules.GAME_SPEED


func anim(action: String) -> String:
	return pre + ("build" if action == "attack" else action)       # hacks at the animal with the builder's swing


func order_farm(f: Building) -> void:
	_clear_job()
	job = "farm"
	farm = f
	f.farmer = self
	_start_goto()


func order_build(b: Building) -> void:
	_clear_job()
	job = "build"
	site = b
	_start_goto()


func order_repair(b: Building, resume := false) -> void:
	var rj := ""
	var rt: Object = null
	if resume:
		if job == "repair":
			rj = _resume_job
			rt = _resume_target
		else:
			rj = job
			rt = res if job == "gather" else (farm if job == "farm" else (site if job == "build" else null))
	_clear_job()
	_resume_job = rj
	_resume_target = rt
	job = "repair"
	site = b
	_start_goto()


## Repair done: back to what the villager was doing before.
func _finish_repair() -> void:
	var rj := _resume_job
	var rt: Object = _resume_target
	_clear_job()
	state = S.IDLE
	match rj:
		"gather":
			if is_instance_valid(rt) and rt.alive:
				order_gather(rt)
			else:
				var r := map.find_resource(gather_kind, cell(), 14)
				if r:
					order_gather(r)
		"farm":
			if is_instance_valid(rt) and rt.alive and rt.food > 0.0:
				order_farm(rt)
		"build":
			if is_instance_valid(rt) and rt.alive and not rt.done:
				order_build(rt)
	if state == S.IDLE and job == "":
		stand()


func _clear_job() -> void:
	garrison_target = null
	if farm and farm.farmer == self:
		farm.farmer = null
	job = ""
	_resume_job = ""
	_resume_target = null
	build_queue = []
	res = null
	farm = null
	site = null
	drop = null
	prey = null
	path.clear()


func on_hurt(attacker: Object) -> void:
	map.rally_defenders(attacker, tp)
	_say_hurt()


func _say_hurt() -> void:
	var now := Time.get_ticks_msec() * 0.001
	if now - _hurt_say > 4.0:
		_hurt_say = now
		Chatter.say(self, "hurt", 0.7)


func die() -> void:
	_clear_job()
	super.die()


# ------------------------------------------------------------------ state machine
func tick(dt: float) -> void:
	if garrison_target and garrison_tick(dt, _walk_anim()):
		advance(dt)
		return
	_msg_cd -= dt
	if job == "hunt":
		_hunt_ai(dt)
		advance(dt)
		return
	match state:
		S.IDLE:
			if not path.is_empty():
				follow(dt, _walk_anim())
				if path.is_empty():
					stand()
			elif job == "":
				_idle_t -= dt
				if _idle_t <= 0.0:
					_idle_t = 1.0
					_assist_nearby_camp()
		S.GOTO:
			follow(dt, _walk_anim())
			if path.is_empty():
				state = S.WORK
				_acc = 0.0
				_face_job()
				play(pre + _work_anim())
		S.WORK:
			_work(dt)
		S.RETURN:
			follow(dt, _walk_anim())
			if path.is_empty():
				_deposit()
	advance(dt)


func _walk_anim() -> String:
	if carry_n > 0:
		return pre + {"wood": "carry_wood", "food": "carry_food"}.get(carry_kind, "carry_ore")
	return pre + "walk"


func _res_ok() -> bool:
	return is_instance_valid(res) and res.alive


func _work_anim() -> String:
	match job:
		"build", "repair":
			return "build"
		"farm":
			return "farm"
		"gather":
			return {"wood": "chop", "food": "forage"}.get(res.kind if res else "", "mine")
	return "build"


func _face_job() -> void:
	var p := tp
	if job == "gather" and res:
		p = Vector2(res.cell)
	elif (job == "build" or job == "repair") and site:
		p = map.nearest_point(site, tp)
	elif job == "farm" and farm:
		p = farm.tp + Vector2(0.4, 0.4)
	face_towards(p.x - tp.x, p.y - tp.y)


func _start_goto() -> void:
	var ok := false
	match job:
		"gather":
			if not _res_ok():
				res = null
				_find_replacement()
			if res:
				ok = go_adjacent(Rect2i(res.cell, Vector2i.ONE))
				if not ok:
					# unreachable (walled in by trees): try another one
					var bad := res
					res = null
					_find_replacement(bad)
					if res:
						ok = go_adjacent(Rect2i(res.cell, Vector2i.ONE))
		"farm":
			if is_instance_valid(farm) and farm.alive:
				var r := farm.rect()
				var c := Vector2i(clampi(roundi(tp.x), r.position.x, r.end.x - 1), clampi(roundi(tp.y), r.position.y, r.end.y - 1))
				ok = go_to(c)
		"build":
			if is_instance_valid(site) and site.alive and not site.done:
				ok = go_adjacent(site.rect())
		"repair":
			if is_instance_valid(site) and site.alive and site.hp < site.max_hp:
				ok = go_adjacent(site.rect())
	if ok:
		state = S.GOTO
	else:
		_give_up()


func _give_up() -> void:
	var q := build_queue
	_clear_job()
	state = S.IDLE
	stand()
	_continue_queue(q)


## A villager doing nothing helps build a camp or mill going up nearby, and then, as for any builder of
## these, goes to work with it (chopping, mining or foraging around it).
func _assist_nearby_camp() -> void:
	var best: Building = null
	var best_d := 14.0
	for b in map.buildings:
		if b.alive and not b.done and b.kind in ["lumber_camp", "mining_camp", "mill"]:
			var d := b.tp.distance_to(tp)
			if d < best_d:
				best_d = d
				best = b
	if best:
		order_build(best)


## Nothing new ordered: pick up the nearest building plot nearby that still needs work.
func _help_nearby(done_site: Building) -> void:
	var best: Building = null
	var best_d := 12.0
	for b in map.buildings:
		if b == done_site or not b.alive or b.done or b.kind == "farm":
			continue
		var d := b.tp.distance_to(tp)
		if d < best_d:
			best_d = d
			best = b
	if best:
		order_build(best)


## Goes on to the next unfinished piece of a wall.
func _continue_queue(q: Array[Building]) -> void:
	while not q.is_empty():
		var nb: Building = q.pop_front()
		if is_instance_valid(nb) and nb.alive and not nb.done:
			order_build(nb)
			if job == "build":
				build_queue = q
				return


## While repairing, enemies hitting the building turn on the repairer instead.
func _draw_aggro() -> void:
	for m in map.mobs:
		if m.team != 0 and m.alive and m.target == site and m.tp.distance_to(tp) < 12.0:
			m.target = self
			m.path.clear()


func _find_replacement(exclude: ResNode = null) -> void:
	if gather_kind != "":
		res = map.find_resource(gather_kind, cell(), 14, exclude)


func _work_sound(dt: float) -> void:
	_snd -= dt
	if _snd > 0.0:
		return
	var effect := ""
	match job:
		"gather":
			if res:
				effect = {"wood": "chop", "food": "gather", "gold": "ore", "stone": "ore"}[res.kind]
				_snd = {"chop": 0.8, "gather": 1.3, "ore": 0.9}[effect]
		"farm":
			effect = "farm"
			_snd = 1.6
		"build", "repair":
			effect = "hammer"
			_snd = 0.5
	if effect != "":
		Sfx.at(effect, position)


func _work(dt: float) -> void:
	_work_sound(dt)
	match job:
		"gather":
			if not _res_ok():
				res = null
				if carry_n > 0:
					_begin_return()
				else:
					_start_goto()
				return
			_acc += map.gather_rate("hunt" if res.hunt else res.kind) * dt
			while _acc >= 1.0 and res:
				_acc -= 1.0
				res.amount -= 1
				carry_n += 1
				carry_kind = res.kind
				if res.amount <= 0:
					map.remove_res(res)
					res = null
			if res == null or carry_n >= map.carry_cap("hunt" if res.hunt else res.kind):
				_begin_return()
		"farm":
			if not is_instance_valid(farm) or not farm.alive or not farm.done or farm.food <= 0.0:
				if is_instance_valid(farm) and farm.alive and farm.done:
					map.on_building_destroyed(farm, true)
				_give_up()
				return
			_acc += map.gather_rate("farm") * dt
			while _acc >= 1.0:
				_acc -= 1.0
				farm.food = maxf(0.0, farm.food - 1.0)
				carry_n += 1
				carry_kind = "food"
			if carry_n >= map.carry_cap("farm"):
				farm.queue_redraw()
				_begin_return()
		"build":
			if not is_instance_valid(site) or not site.alive:
				_give_up()
			elif site.done:
				var s := site
				var q := build_queue
				_clear_job()
				state = S.IDLE
				_after_build(s)
				_continue_queue(q)
				if state == S.IDLE and job == "":
					_help_nearby(s)
			else:
				site.add_work(dt)
		"repair":
			if not is_instance_valid(site) or not site.alive:
				_give_up()
			elif site.hp >= site.max_hp:
				_finish_repair()
			else:
				site.repair(dt)
				_aggro -= dt
				if _aggro <= 0.0:
					_aggro = 0.6
					_draw_aggro()
		_:
			state = S.IDLE


func _begin_return() -> void:
	var b := map.find_dropoff(carry_kind, tp)
	if b == null:
		if _msg_cd <= 0.0:
			_msg_cd = 8.0
			map.message.emit("No drop-off for %s: build a Town Center%s" % [carry_kind, "" if carry_kind == "wood" or carry_kind == "food" else " or Mining Camp"])
		_give_up()
		return
	drop = b
	if go_adjacent(b.rect()):
		state = S.RETURN
	else:
		_give_up()


func _deposit() -> void:
	if is_instance_valid(drop) and drop.alive:
		map.add_resource(carry_kind, carry_n)
		carry_n = 0
	drop = null
	if job == "":
		state = S.IDLE
		stand()
		return
	_start_goto()


## A finished camp, mill or farm puts its builder straight to work next to it.
func _after_build(b: Building) -> void:
	match b.kind:
		"farm":
			if b.farmer == null:
				order_farm(b)
		"lumber_camp":
			var r := map.find_resource("wood", b.origin, 12)
			if r:
				order_gather(r)
		"mining_camp":
			var r := map.find_resource("gold", b.origin, 12)
			if r == null:
				r = map.find_resource("stone", b.origin, 12)
			if r:
				order_gather(r)
		"mill":
			var r := map.find_resource("food", b.origin, 12)
			if r:
				order_gather(r)
	if state == S.IDLE:
		stand()
