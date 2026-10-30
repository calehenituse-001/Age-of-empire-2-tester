class_name ModRegistry
extends RefCounted
## Version 1 supports genuine additional buildings via a bounded declarative adapter.
const GAME := "aoe2hd-beta-source-1"
const FRAMEWORK := "1.0.0"
var buildings: Array[Dictionary] = []
var active: Array[Dictionary] = []
var textures: Dictionary = {}
var error := ""
var fingerprint := "vanilla"

static func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > 262144:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

static func valid_id(value: Variant) -> bool:
	if not value is String:
		return false
	var re := RegEx.new()
	re.compile("^[a-z][a-z0-9_.-]{2,63}$")
	return re.search(value) != null

static func number(d: Dictionary, key: String, low: float, high: float) -> bool:
	var n: Variant = d.get(key)
	return (n is int or n is float) and is_finite(float(n)) and float(n) >= low and float(n) <= high

static func integer(d: Dictionary, key: String, low: int, high: int) -> bool:
	return number(d, key, low, high) and float(d[key]) == float(int(d[key]))

func _fail(message: String) -> bool:
	error = message
	buildings.clear()
	active.clear()
	textures.clear()
	fingerprint = "vanilla"
	return false

func prepare(root: String, enabled: Array) -> bool:
	buildings.clear()
	active.clear()
	textures.clear()
	error = ""
	fingerprint = "vanilla"
	if enabled.size() > 32:
		return _fail("Too many mods")
	var versions := {}
	var used := {}
	var keys := {}
	var hashes := PackedStringArray()
	for value: Variant in enabled:
		if not valid_id(value) or versions.has(value):
			return _fail("Invalid/duplicate mod ID")
		var id: String = value
		var dir := root.path_join(id)
		var m := _json(dir.path_join("manifest.json"))
		if m.get("id") != id or m.get("formatVersion") != 1 or m.get("gameVersion") != GAME or m.get("frameworkVersion") != FRAMEWORK or m.get("capabilities") != ["buildings.add"]:
			return _fail("Unsupported manifest: " + id)
		if not m.get("dependencies") is Array or not m.get("version") is String:
			return _fail("Invalid dependencies/version: " + id)
		var version_re := RegEx.new()
		version_re.compile("^[0-9]{1,4}\\.[0-9]{1,4}\\.[0-9]{1,4}$")
		if version_re.search(m.version) == null:
			return _fail("Invalid version: " + id)
		for dependency: Variant in m.dependencies:
			if not dependency is Dictionary or not valid_id(dependency.get("id")) or versions.get(dependency.id) != dependency.get("version"):
				return _fail("Missing, incompatible or incorrectly ordered dependency: " + id)
		var content := _json(dir.path_join("content.json"))
		if content.keys() != ["buildings"] or not content.buildings is Array or content.buildings.is_empty() or content.buildings.size() > 32:
			return _fail("Only buildings.add is supported: " + id)
		hashes.append(FileAccess.get_sha256(dir.path_join("manifest.json")))
		hashes.append(FileAccess.get_sha256(dir.path_join("content.json")))
		for row: Variant in content.buildings:
			if not row is Dictionary:
				return _fail("Invalid building")
			var b: Dictionary = row.duplicate(true)
			if not integer(b, "id", 900000, 999999) or used.has(b.id) or not valid_id(b.get("key")) or keys.has(b.key) or Defs.BUILDINGS.has(b.key):
				return _fail("Invalid/conflicting building ID or key: " + id)
			if not integer(b, "baseId", 0, 10000) or not int(b.baseId) in [70, 562, 584, 68] or not b.get("name") is String or b.name.length() not in range(1, 81):
				return _fail("Unsupported building base/name: " + id)
			if not integer(b, "size", 1, 4) or not integer(b, "hp", 1, 100000) or not integer(b, "population", 0, 50) or not integer(b, "requiredAge", 0, 3) or not number(b, "seconds", 1, 3600):
				return _fail("Invalid building bounds: " + id)
			if not b.get("cost") is Dictionary or not b.get("dropoff") is Array:
				return _fail("Invalid costs/dropoffs")
			for resource: Variant in b.cost:
				if not resource in ["food", "wood", "gold", "stone"] or not integer(b.cost, resource, 0, 100000):
					return _fail("Invalid resource cost")
			for resource: Variant in b.dropoff:
				if not resource in ["food", "wood", "gold", "stone"]:
					return _fail("Invalid dropoff")
			var sprite: Variant = b.get("sprite")
			if not sprite is String or not sprite.begins_with("sprites/") or not sprite.ends_with(".png") or sprite.contains("\\") or sprite.contains(":"):
				return _fail("Invalid sprite path")
			for segment: String in sprite.split("/"):
				if segment in ["", ".", ".."]:
					return _fail("Unsafe sprite path")
			var path := dir.path_join(sprite)
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null or file.get_length() < 24 or file.get_length() > 8000000:
				return _fail("Missing/oversized sprite")
			if file.get_buffer(8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
				return _fail("Sprite must be PNG")
			file.big_endian = true
			file.seek(16)
			var w := file.get_32()
			var h := file.get_32()
			if w < 1 or w > 2048 or h < 1 or h > 2048 or not integer(b, "hotspotX", 0, w) or not integer(b, "hotspotY", 0, h):
				return _fail("Invalid sprite dimensions/hotspot")
			var img := Image.load_from_file(path)
			if img == null or img.is_empty():
				return _fail("Sprite decoding failed")
			b.texture_key = "mod/" + id + "/" + sprite
			b.width = w
			b.height = h
			textures[b.texture_key] = path
			hashes.append(FileAccess.get_sha256(path))
			buildings.append(b)
			used[b.id] = true
			keys[b.key] = true
		versions[id] = m.version
		active.append({"id": id, "version": m.version})
	if not active.is_empty():
		fingerprint = "mods-" + "|".join(hashes).sha256_text().substr(0, 20)
	return true

func apply_rules(rules: Node) -> bool:
	# Preflight every addition before mutating any original registry.
	for b in buildings:
		if rules.units.has(int(b.id)) or not rules.units.has(int(b.baseId)):
			return _fail("Missing base or conflicting engine ID: " + str(b.id))
	for b in buildings:
		var row: Dictionary = rules.units[int(b.baseId)].duplicate(true)
		row.merge({"id": int(b.id), "name": b.name, "hp": int(b.hp), "type": 80, "loc": 118, "enabled": true, "time": float(b.seconds) * Rules.GAME_SPEED, "radius": [b.size / 2.0, b.size / 2.0], "pop": b.population, "research_id": -1}, true)
		var cost: Array = []
		for rid: int in Rules.RES_NAMES:
			if b.cost.has(Rules.RES_NAMES[rid]):
				cost.append([rid, int(b.cost[Rules.RES_NAMES[rid]])])
		row.cost = cost
		rules.units[int(b.id)] = row
		Defs.BUILDINGS[b.key] = {"uid": int(b.id), "name": b.name, "size": int(b.size), "hp": int(b.hp), "cost": b.cost, "time": float(b.seconds), "pop": int(b.population), "drop": b.dropoff, "required_age": int(b.requiredAge)}
	return true

func apply_assets(assets: Node) -> void:
	for b in buildings:
		assets.man.buildings["bld_" + str(int(b.id))] = {"file": b.texture_key, "x": 0, "y": 0, "w": b.width, "h": b.height, "hx": b.hotspotX, "hy": b.hotspotY}
