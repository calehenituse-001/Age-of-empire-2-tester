class_name PeStrings
extends RefCounted
## Reads the text strings (unit, building and tech names, descriptions) out of AoE2 HD's language*.dll files. The DLLs only hold a
## Windows RT_STRING resource: blocks of 16 strings, block n holds string ids (n-1)*16 .. (n-1)*16+15, each a 16-bit length
## followed by that many UTF-16 characters.

static func read_all(game: String) -> Dictionary:
	var out := {}
	for f in ["language.dll", "language_x1.dll", "language_x1_p1.dll"]:
		var p := game.path_join("Bin/en").path_join(f)
		if FileAccess.file_exists(p):
			out.merge(read(FileAccess.get_file_as_bytes(p)), true)
	return out


static func _rva(secs: Array, rva: int) -> int:
	for s: Array in secs:
		if s[0] <= rva and rva < s[0] + maxi(s[1], s[3]):
			return rva - s[0] + s[2]
	return -1


static func read(d: PackedByteArray) -> Dictionary:
	var pe := d.decode_u32(0x3C)
	var nsec := d.decode_u16(pe + 6)
	var optsz := d.decode_u16(pe + 20)
	var opt := pe + 24
	var magic := d.decode_u16(opt)
	var dd := opt + (96 if magic == 0x10B else 112)
	var res_rva := d.decode_u32(dd + 16)
	var secs := []
	for i in nsec:
		var o := opt + optsz + i * 40
		secs.append([d.decode_u32(o + 12), d.decode_u32(o + 8), d.decode_u32(o + 20), d.decode_u32(o + 16)])   # va, vsize, raw, rsize
	var base := _rva(secs, res_rva)
	var strings := {}
	for e: Array in _entries(d, base):
		if e[0] != 6 or not (e[1] & 0x80000000):
			continue
		for e2: Array in _entries(d, base + (e[1] & 0x7FFFFFFF)):
			if not (e2[1] & 0x80000000):
				continue
			for e3: Array in _entries(d, base + (e2[1] & 0x7FFFFFFF)):
				var de: int = base + e3[1]
				var p := _rva(secs, d.decode_u32(de))
				for k in 16:
					var n := d.decode_u16(p)
					p += 2
					if n > 0:
						strings[(e2[0] - 1) * 16 + k] = d.slice(p, p + n * 2).get_string_from_utf16()
					p += n * 2
	return strings


static func _entries(d: PackedByteArray, off: int) -> Array:
	var named := d.decode_u16(off + 12)
	var ided := d.decode_u16(off + 14)
	var out := []
	for i in named + ided:
		out.append([d.decode_u32(off + 16 + i * 8), d.decode_u32(off + 20 + i * 8)])
	return out
