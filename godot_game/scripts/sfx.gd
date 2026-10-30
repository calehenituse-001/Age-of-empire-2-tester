extends Node
## Sound: effects from the original sound files, a music playlist, and one volume per kind of sound
## (Master, Music, Fighting, Work and building, Alerts) that the sound menu changes and saves.

const BUSES := ["Music", "Combat", "Work", "Alerts"]
const LABELS := {"Master": "Master volume", "Music": "Music", "Combat": "Fighting", "Work": "Work and building", "Alerts": "Alerts and events"}
const DEFAULTS := {"Master": 0.8, "Music": 0.35, "Combat": 0.8, "Work": 0.7, "Alerts": 0.9}
const CONFIG := "user://sound.cfg"

# effect name -> sound files (res://assets/aoe/snd/<key>.wav); one is picked at random each time
const FILES := {
	"sword": ["sword1", "sword2", "sword3", "sword4", "sword5", "sword6", "sword7"],
	"arrow": ["arrow1", "arrow2", "arrow3", "arrow4", "arrow5"],
	"hit": ["dagger1", "dagger2", "dagger3", "grunt1", "grunt2", "grunt3"],
	"death_m": ["death1", "death2", "death3", "death4", "death5", "death6"],
	"death_f": ["fdie1", "fdie3", "fdie4"],
	"wolf": ["wolff1", "wolff2", "wolff3"],
	"wall_hit": ["hitwall"],
	"collapse": ["exp1", "exp2"],
	"chop": ["chops1", "chops2", "chops3"],
	"ore": ["ore1", "ore2", "ore3"],
	"gather": ["gather1", "gather2"],
	"farm": ["farm1", "farm2", "farm3"],
	"hammer": ["hammer1", "hammer2", "hammer3"],
	"tree_fall": ["fall1"],
	"unit_ready": ["ready"],
	"soldier_ready": ["readym"],
	"done": ["readym"],
	"raid": ["mdone"],
	"chant": ["convert1", "convert2"],
	"relic_up": ["puprelic"],
}
const BUS_OF := {
	"sword": "Combat", "arrow": "Combat", "hit": "Combat", "death_m": "Combat", "death_f": "Combat", "wolf": "Combat",
	"wall_hit": "Combat", "collapse": "Combat",
	"chop": "Work", "ore": "Work", "gather": "Work", "farm": "Work", "hammer": "Work", "tree_fall": "Work",
	"unit_ready": "Alerts", "soldier_ready": "Alerts", "done": "Alerts", "raid": "Alerts", "chant": "Work", "relic_up": "Alerts",
}
const GAIN_DB := {"hammer": 8.0, "arrow": 4.0, "chop": 3.0, "ore": 1.0, "wolf": -4.0, "raid": -3.0, "collapse": -2.0}
const MIN_GAP := {"hammer": 0.1, "arrow": 0.05, "sword": 0.08, "wolf": 1.5, "death_m": 0.15, "death_f": 0.15, "collapse": 0.3, "chant": 1.2}

var volume := DEFAULTS.duplicate()
var cam: Camera2D          # set by Main: effects far from the screen are not played

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _last := {}
var _music: AudioStreamPlayer
var _tracks: Array[AudioStream] = []
var _track := 0


func _ready() -> void:
	for b: String in BUSES:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, b)
		AudioServer.set_bus_send(i, "Master")
	_load_settings()
	_apply_all()
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.finished.connect(_next_track)
	add_child(_music)
	reload_data()


## (Re)loads the music; the portable version calls this once its import has finished.
func reload_data() -> void:
	_streams.clear()
	_tracks.clear()
	for f: String in ["m1", "m2"]:
		var track := GameData.audio("music/%s.mp3" % f)
		if track:
			_tracks.append(track)
	_track = randi() % maxi(1, _tracks.size())
	_next_track(false)


func _next_track(advance := true) -> void:
	if _tracks.is_empty():
		return
	if advance:
		_track = (_track + 1) % _tracks.size()
	_music.stream = _tracks[_track]
	_music.play()


# ------------------------------------------------------------------ volumes
func get_volume(key: String) -> float:
	return float(volume[key])


func set_volume(key: String, v: float) -> void:
	volume[key] = clampf(v, 0.0, 1.0)
	_apply(key)
	_save_settings()


func _apply(key: String) -> void:
	var i := AudioServer.get_bus_index(key)
	if i < 0:
		return
	var v: float = volume[key]
	AudioServer.set_bus_mute(i, v <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


func _apply_all() -> void:
	for key: String in volume:
		_apply(key)


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(CONFIG) == OK:
		for key: String in volume:
			volume[key] = clampf(float(cf.get_value("volume", key, volume[key])), 0.0, 1.0)


func _save_settings() -> void:
	var cf := ConfigFile.new()
	for key: String in volume:
		cf.set_value("volume", key, volume[key])
	cf.save(CONFIG)


# ------------------------------------------------------------------ effects
## Plays an effect anywhere (alerts, interface).
func play(effect: String, gain_db := 0.0) -> void:
	var files: Array = FILES.get(effect, [])
	if files.is_empty():
		return
	var now := Time.get_ticks_msec() * 0.001
	if now - float(_last.get(effect, -10.0)) < float(MIN_GAP.get(effect, 0.06)):
		return
	var key: String = files[randi() % files.size()]
	var stream: AudioStream = _stream(key)
	if stream == null:
		return
	for p in _pool:
		if not p.playing:
			_last[effect] = now
			p.bus = BUS_OF.get(effect, "Work")
			p.stream = stream
			p.volume_db = gain_db + float(GAIN_DB.get(effect, 0.0))
			p.pitch_scale = randf_range(0.94, 1.06)
			p.play()
			return


## Plays an effect at a place in the world: full volume on screen, fading out just beyond its edge.
func at(effect: String, world: Vector2, gain_db := 0.0) -> void:
	if cam == null or not is_instance_valid(cam):
		return
	var half := get_viewport().get_visible_rect().size / cam.zoom * 0.5
	var d := world - cam.position
	var n := maxf(absf(d.x) / half.x, absf(d.y) / half.y)
	if n > 1.4:
		return
	var att := 1.0 if n <= 0.8 else (1.4 - n) / 0.6
	play(effect, gain_db + linear_to_db(maxf(att, 0.01)))


func _stream(key: String) -> AudioStream:
	if not _streams.has(key):
		_streams[key] = GameData.audio("snd/%s.wav" % key)
	return _streams[key]
