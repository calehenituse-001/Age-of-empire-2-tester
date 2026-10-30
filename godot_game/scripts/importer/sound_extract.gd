class_name SoundExtract
extends RefCounted
## The sound effects (snd/<name>.wav) and the two music tracks (music/m1.mp3, m2.mp3), copied out of the game's archives. A port of
## extract_sounds in tools/extract_aoe_godot.py.

const SOUNDS := "SWORD1 SWORD2 SWORD3 SWORD4 SWORD5 SWORD6 SWORD7 ARROW1 ARROW2 ARROW3 ARROW4 ARROW5 DAGGER1 DAGGER2 DAGGER3 " + \
	"GRUNT1 GRUNT2 GRUNT3 DEATH1 DEATH2 DEATH3 DEATH4 DEATH5 DEATH6 FDIE1 FDIE3 FDIE4 WOLFF1 WOLFF2 WOLFF3 HITWALL EXP1 EXP2 " + \
	"CHOPS1 CHOPS2 CHOPS3 ORE1 ORE2 ORE3 GATHER1 GATHER2 FARM1 FARM2 FARM3 HAMMER1 HAMMER2 HAMMER3 FALL1 " + \
	"READY READYM MDONE CONVERT1 CONVERT2 PUPRELIC"
const MUSIC := [["music1.mp3", "m1.mp3"], ["xmusic1.mp3", "m2.mp3"]]
const MUSIC_BYTES := 6_000_000       # the first ~4 minutes of each (192 kbps), cut at an arbitrary frame: plenty of music, small storage


## `dat` is the parsed empires2_x1_p1.dat (DatReader). Returns the number of sounds written.
static func run(game: String, out: String, dat: Dictionary, step: Callable) -> int:
	var ids := {}
	for s: Dictionary in dat.sounds:
		for it: Dictionary in s.get("sound_items", []):
			var name := String(it.filename).get_basename().to_upper()
			if name != "" and not ids.has(name):
				ids[name] = int(it.resource_id)
	var data := game.path_join("Data")
	var drs := []
	for f in ["sounds.drs", "sounds_x1.drs"]:
		var d := Drs.open(data.path_join(f))
		if d:
			drs.append(d)
	DirAccess.make_dir_recursive_absolute(out.path_join("snd"))
	step.call("Sound effects")
	var n := 0
	for name in SOUNDS.split(" "):
		var wav := PackedByteArray()
		for i in range(drs.size() - 1, -1, -1):          # the expansion's archive wins
			if drs[i].has("wav", ids.get(name, -1)):
				wav = drs[i].get_file("wav", ids[name])
				break
		if wav.is_empty():
			push_warning("missing sound " + name)
			continue
		var f := FileAccess.open(out.path_join("snd/%s.wav" % name.to_lower()), FileAccess.WRITE)
		f.store_buffer(wav)
		f.close()
		n += 1
	DirAccess.make_dir_recursive_absolute(out.path_join("music"))
	for m: Array in MUSIC:
		var src := game.path_join("Sound/music").path_join(m[0])
		if FileAccess.file_exists(src):
			step.call("Music " + m[1])
			var fin := FileAccess.open(src, FileAccess.READ)
			var fout := FileAccess.open(out.path_join("music").path_join(m[1]), FileAccess.WRITE)
			fout.store_buffer(fin.get_buffer(MUSIC_BYTES))
	return n
