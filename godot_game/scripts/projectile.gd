class_name Projectile
extends Sprite2D
## An arrow flying along a shallow arc from shooter to target; damage lands on arrival.

static var _tex: ImageTexture

var from := Vector2.ZERO
var to := Vector2.ZERO
var dmg := 5.0
var target: Object = null
var shooter: Object = null
var dur := 0.3
var t := 0.0
var done := false
var splash := 0.0                 # blast radius in tiles (Mangonel, Onager): enemies around the target are hit too
var splash_atk: Dictionary = {}


static func arrow_texture() -> ImageTexture:
	if _tex == null:
		# a long, bright arrow with a dark outline so it reads against grass at tablet zoom
		var w := 44
		var h := 11
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var mid := h / 2
		for x in range(2, w - 8):
			for dy in range(-2, 3):
				img.set_pixel(x, mid + dy, Color(0.08, 0.05, 0.02, 0.9) if absi(dy) == 2 else Color(1.0, 0.86, 0.5, 1))
		for x in range(w - 9, w):
			var half := (w - 1 - x) * 5 / 9 + 1
			for dy in range(-half, half + 1):
				img.set_pixel(x, mid + dy, Color(0.95, 0.95, 1.0, 1) if absi(dy) < half else Color(0.1, 0.1, 0.12, 1))
		for x in range(0, 9):
			for dy in [-4, -3, 3, 4]:
				if (x + absi(dy)) % 2 == 0 or x > 2:
					img.set_pixel(x, mid + dy, Color(1.0, 0.25, 0.2, 1))
		_tex = ImageTexture.create_from_image(img)
	return _tex


func launch(a: Vector2, b: Vector2, damage: float, tgt: Object, who: Object, blast := 0.0, atk := {}) -> void:
	texture = arrow_texture()
	from = a
	to = b
	dmg = damage
	target = tgt
	shooter = who
	splash = blast
	splash_atk = atk
	dur = maxf(0.2, a.distance_to(b) / 11.0)
	_place(0.0)


func tick(dt: float) -> void:
	if is_instance_valid(target) and target.alive:
		to = target.tp
	t += dt
	var k := minf(t / dur, 1.0)
	_place(k)
	if k >= 1.0:
		done = true
		if splash > 0.0:
			_blast()
		if is_instance_valid(target) and target.alive:
			target.take_damage(dmg, shooter)
			if target is Mob:
				Sfx.at("hit", position)
				if not target.alive and shooter is Building and shooter.def.get("shoots", false):
					Chatter.say(shooter, "tower_kill", 0.7)


## Everyone hostile to the shooter within the blast radius of the target's spot takes the blow as their own armour leaves it.
func _blast() -> void:
	var team: int = shooter.team if is_instance_valid(shooter) else 0
	var map: GameMap = null
	if is_instance_valid(shooter):
		map = shooter.map
	if map == null:
		return
	for m in map.mobs.duplicate():
		if m.alive and m != target and m.team != team and m.tp.distance_to(to) <= splash:
			m.take_damage(Combat.damage(splash_atk, m.armor()), shooter)


func _place(k: float) -> void:
	var p0 := Iso.to_world(from)
	var p1 := Iso.to_world(to)
	var arc := sin(k * PI) * minf(40.0, p0.distance_to(p1) * 0.25)
	var p := p0.lerp(p1, k)
	position = p + Vector2(0, -24 - arc)
	var ahead := p0.lerp(p1, minf(k + 0.05, 1.0)) + Vector2(0, -24 - sin(minf(k + 0.05, 1.0) * PI) * minf(40.0, p0.distance_to(p1) * 0.25))
	rotation = (ahead - position).angle()
