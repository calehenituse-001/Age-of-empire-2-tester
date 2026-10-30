class_name Slp
extends RefCounted
## SLP v2.0N sprites (the Genie engine's picture format), decoded straight to RGBA, and JASC palettes. A port of tools/aoe_formats.py.

const PLAYER := 256                 # lut slots 256..511: player colour entries; 512: shadow; 513: outline (transparent)
const SHADOW := 512
const SHADOW_RGBA := 90 << 24       # (0, 0, 0, 90)


## "JASC-PAL\n0100\n256\nr g b\n..." -> PackedByteArray of 256*3 bytes
static func read_pal(text: String) -> PackedByteArray:
	var t := text.replace("\r", " ").replace("\n", " ").replace("\t", " ").split(" ", false)
	var n := int(t[2])
	var out := PackedByteArray()
	out.resize(n * 3)
	for i in n * 3:
		out[i] = int(t[3 + i])
	return out


## Code -> packed RGBA lookup for one palette. `pc_offset` shifts the player colour entries (32 = red, 0 = blue); `shadow_idx` are
## palette indices drawn as a shadow (the near-black ones buildings use for theirs).
static func lut(pal: PackedByteArray, pc_offset := 0, shadow_idx: Array = []) -> PackedInt32Array:
	var l := PackedInt32Array()
	l.resize(514)
	for i in 256:
		l[i] = _rgba(pal, i)
		l[256 + i] = _rgba(pal, mini(i + pc_offset, 255))
	for s: int in shadow_idx:
		l[s] = SHADOW_RGBA
	l[SHADOW] = SHADOW_RGBA
	l[513] = 0
	return l


static func _rgba(pal: PackedByteArray, i: int) -> int:
	return pal[i * 3] | (pal[i * 3 + 1] << 8) | (pal[i * 3 + 2] << 16) | (255 << 24)


## Frames of an SLP as [{w, h, hx, hy, img: Image (RGBA8)}]. Pixels the file leaves empty are transparent.
static func decode(b: PackedByteArray, lut: PackedInt32Array, max_frames := -1) -> Array:
	var nframes := b.decode_s32(4)
	if max_frames >= 0:
		nframes = mini(nframes, max_frames)
	var frames := []
	for f in nframes:
		var h0 := 0x20 + f * 32
		var cmd_off := b.decode_u32(h0)
		var out_off := b.decode_u32(h0 + 4)
		var w := b.decode_s32(h0 + 16)
		var h := b.decode_s32(h0 + 20)
		var hx := b.decode_s32(h0 + 24)
		var hy := b.decode_s32(h0 + 28)
		var px := PackedByteArray()
		px.resize(maxi(w * h * 4, 0))
		for y in h:
			var left := b.decode_u16(out_off + y * 4)
			var right := b.decode_u16(out_off + y * 4 + 2)
			if left == 0x8000 or right == 0x8000:
				continue
			var x := left
			var p := b.decode_u32(cmd_off + y * 4)
			var row := y * w
			while true:
				var c := b[p]
				p += 1
				if c == 0x0F:
					break
				var lo := c & 3
				if lo == 0:                                   # colour list
					for _i in c >> 2:
						px.encode_u32((row + x) * 4, lut[b[p]])
						p += 1
						x += 1
				elif lo == 1:                                 # skip
					var n := c >> 2
					if n == 0:
						n = b[p]
						p += 1
					x += n
				elif (c & 0x0F) == 2:                         # big colour list
					var n := ((c & 0xF0) << 4) + b[p]
					p += 1
					for _i in n:
						px.encode_u32((row + x) * 4, lut[b[p]])
						p += 1
						x += 1
				elif (c & 0x0F) == 3:                         # big skip
					x += ((c & 0xF0) << 4) + b[p]
					p += 1
				else:
					var cmd := c & 0x0F
					var n := c >> 4
					if (cmd == 6 or cmd == 7 or cmd == 10 or cmd == 11) and n == 0:
						n = b[p]
						p += 1
					if cmd == 6:                              # player colour list
						for _i in n:
							px.encode_u32((row + x) * 4, lut[PLAYER + b[p]])
							p += 1
							x += 1
					elif cmd == 7:                            # fill
						var v: int = lut[b[p]]
						p += 1
						for _i in n:
							px.encode_u32((row + x) * 4, v)
							x += 1
					elif cmd == 10:                           # player colour fill
						var v: int = lut[PLAYER + b[p]]
						p += 1
						for _i in n:
							px.encode_u32((row + x) * 4, v)
							x += 1
					elif cmd == 11:                           # shadow
						for _i in n:
							px.encode_u32((row + x) * 4, SHADOW_RGBA)
							x += 1
					elif cmd == 14:                           # extended commands
						var ext := c >> 4
						if ext == 4 or ext == 6:
							x += 1
						elif ext == 5 or ext == 7:
							x += b[p]
							p += 1
					else:
						push_error("unknown SLP command %d" % c)
						return frames
		var img: Image = Image.create_from_data(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8, px) if w > 0 and h > 0 else Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
		frames.append({"w": w, "h": h, "hx": hx, "hy": hy, "img": img})
	return frames
