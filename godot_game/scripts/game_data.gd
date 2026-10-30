class_name GameData
extends RefCounted
## Where the game's pictures, sounds, music and data tables come from.
## Development version: bundled in the app (res://assets/aoe/). Portable version: imported on the device from the player's own
## copy of the game into user://gamedata/ (same layout), by the import wizard.

const BUNDLED := "res://assets/aoe/"
const IMPORTED := "user://gamedata/"      # holds a file ".complete" once an import has finished

static var _root := "?"


## The folder the data is read from, or "" when there is none yet (the portable version before its import).
static func root() -> String:
	if _root == "?":
		_root = ""
		var order := [IMPORTED] if OS.get_environment("AOE_DATA") == "imported" else [BUNDLED, IMPORTED]     # (the variable lets tests use the import)
		for d in order:
			if FileAccess.file_exists(d + "manifest.json") and FileAccess.file_exists(d + "data/rules.json") \
					and (d == BUNDLED or FileAccess.file_exists(d + ".complete")):
				_root = d
				break
	return _root


static func ready() -> bool:
	return root() != ""


static func bundled() -> bool:
	return root() == BUNDLED


## Forget what was found (after an import finished).
static func rescan() -> void:
	_root = "?"


static func exists(rel: String) -> bool:
	return ready() and FileAccess.file_exists(root() + rel)


static func text(rel: String) -> String:
	return FileAccess.get_file_as_string(root() + rel) if ready() else ""


static func json(rel: String) -> Variant:
	return JSON.parse_string(text(rel)) if exists(rel) else null


static func texture(rel: String) -> Texture2D:
	if not ready():
		return null
	if bundled():
		return load(BUNDLED + rel)
	var img := Image.load_from_file(IMPORTED + rel)
	return ImageTexture.create_from_image(img) if img else null


## A sound effect (.wav) or a music track (.mp3); null when it is not there.
static func audio(rel: String) -> AudioStream:
	if not exists(rel):
		return null
	if bundled():
		return load(BUNDLED + rel)
	if rel.ends_with(".mp3"):
		return AudioStreamMP3.load_from_file(IMPORTED + rel)
	return AudioStreamWAV.load_from_file(IMPORTED + rel)
