class_name Inflate
extends RefCounted
## Raw DEFLATE (RFC 1951) decoder. Godot's own decompressor insists on a zlib checksum that the game's .dat file does not carry.

const LEN_BASE: Array[int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
const LEN_EXTRA: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
const DIST_BASE: Array[int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
const DIST_EXTRA: Array[int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
const CL_ORDER: Array[int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]


## Decodes the raw deflate stream `data`; `expected` is the size of the result when known (speeds it up), or 0.
static func raw(data: PackedByteArray, expected := 0) -> PackedByteArray:
	var out := PackedByteArray()
	if expected > 0:
		out.resize(expected)
	var n := 0                  # bytes written to out
	var pos := 0                # next input byte
	var bitbuf := 0
	var bitcnt := 0
	var size := data.size()
	var fixed_lit: Array = []
	var fixed_dist: Array = []
	while true:
		# header: 1 bit final, 2 bits type
		while bitcnt < 3:
			bitbuf |= (data[pos] if pos < size else 0) << bitcnt
			pos += 1
			bitcnt += 8
		var final := bitbuf & 1
		var type := (bitbuf >> 1) & 3
		bitbuf >>= 3
		bitcnt -= 3
		if type == 0:
			bitbuf = 0
			bitcnt = 0
			var ln := data[pos] | (data[pos + 1] << 8)
			pos += 4
			if expected > 0 and n + ln <= expected:
				for i in ln:
					out[n + i] = data[pos + i]
			else:
				if expected > 0:
					out.resize(n + ln)
				else:
					out.resize(n + ln)
				for i in ln:
					out[n + i] = data[pos + i]
			n += ln
			pos += ln
		elif type == 3:
			push_error("inflate: bad block")
			return PackedByteArray()
		else:
			var lit: Array
			var dist: Array
			if type == 1:
				if fixed_lit.is_empty():
					var lens: Array[int] = []
					lens.resize(288)
					for i in 288:
						lens[i] = 8 if i < 144 else (9 if i < 256 else (7 if i < 280 else 8))
					fixed_lit = _table(lens)
					var dl: Array[int] = []
					dl.resize(30)
					dl.fill(5)
					fixed_dist = _table(dl)
				lit = fixed_lit
				dist = fixed_dist
			else:
				while bitcnt < 14:
					bitbuf |= (data[pos] if pos < size else 0) << bitcnt
					pos += 1
					bitcnt += 8
				var hlit := (bitbuf & 31) + 257
				var hdist := ((bitbuf >> 5) & 31) + 1
				var hclen := ((bitbuf >> 10) & 15) + 4
				bitbuf >>= 14
				bitcnt -= 14
				var cl: Array[int] = []
				cl.resize(19)
				cl.fill(0)
				for i in hclen:
					while bitcnt < 3:
						bitbuf |= (data[pos] if pos < size else 0) << bitcnt
						pos += 1
						bitcnt += 8
					cl[CL_ORDER[i]] = bitbuf & 7
					bitbuf >>= 3
					bitcnt -= 3
				var cltab := _table(cl)
				var lens2: Array[int] = []
				while lens2.size() < hlit + hdist:
					while bitcnt < 15:
						bitbuf |= (data[pos] if pos < size else 0) << bitcnt
						pos += 1
						bitcnt += 8
					var e: int = cltab[1][bitbuf & ((1 << cltab[0]) - 1)]
					var l := e >> 16
					var sym := e & 0xFFFF
					bitbuf >>= l
					bitcnt -= l
					if sym < 16:
						lens2.append(sym)
					else:
						var rep := 0
						var val := 0
						var extra := 0
						if sym == 16:
							val = lens2[lens2.size() - 1]
							extra = 2
							rep = 3
						elif sym == 17:
							extra = 3
							rep = 3
						else:
							extra = 7
							rep = 11
						while bitcnt < extra:
							bitbuf |= (data[pos] if pos < size else 0) << bitcnt
							pos += 1
							bitcnt += 8
						rep += bitbuf & ((1 << extra) - 1)
						bitbuf >>= extra
						bitcnt -= extra
						for i in rep:
							lens2.append(val)
				lit = _table(lens2.slice(0, hlit))
				dist = _table(lens2.slice(hlit, hlit + hdist))
			var lbits: int = lit[0]
			var lmask := (1 << lbits) - 1
			var ltab: Array = lit[1]
			var dbits: int = dist[0]
			var dmask := (1 << dbits) - 1
			var dtab: Array = dist[1]
			while true:
				while bitcnt < 15:
					bitbuf |= (data[pos] if pos < size else 0) << bitcnt
					pos += 1
					bitcnt += 8
				var e: int = ltab[bitbuf & lmask]
				var l := e >> 16
				var sym := e & 0xFFFF
				bitbuf >>= l
				bitcnt -= l
				if sym < 256:
					if n >= out.size():
						out.resize(maxi(out.size() * 2, 1024))
					out[n] = sym
					n += 1
				elif sym == 256:
					break
				else:
					sym -= 257
					var extra: int = LEN_EXTRA[sym]
					while bitcnt < extra + 15 + 13:
						bitbuf |= (data[pos] if pos < size else 0) << bitcnt
						pos += 1
						bitcnt += 8
					var length: int = LEN_BASE[sym] + (bitbuf & ((1 << extra) - 1))
					bitbuf >>= extra
					bitcnt -= extra
					var de: int = dtab[bitbuf & dmask]
					var dl2 := de >> 16
					var dsym := de & 0xFFFF
					bitbuf >>= dl2
					bitcnt -= dl2
					var dextra: int = DIST_EXTRA[dsym]
					var distance: int = DIST_BASE[dsym] + (bitbuf & ((1 << dextra) - 1))
					bitbuf >>= dextra
					bitcnt -= dextra
					if n + length > out.size():
						out.resize(maxi(out.size() * 2, n + length))
					var src := n - distance
					if distance >= length:
						for i in length:
							out[n + i] = out[src + i]
					else:
						for i in length:
							out[n + i] = out[src + i]
					n += length
		if final == 1:
			break
	out.resize(n)
	return out


## Canonical Huffman decoding table: [bits, lookup] where lookup[reversed code bits] = (length << 16) | symbol.
static func _table(lens: Array) -> Array:
	var maxlen := 1
	for l: int in lens:
		maxlen = maxi(maxlen, l)
	var count: Array[int] = []
	count.resize(maxlen + 2)
	count.fill(0)
	for l: int in lens:
		if l > 0:
			count[l] += 1
	var next: Array[int] = []
	next.resize(maxlen + 2)
	next.fill(0)
	var code := 0
	for b in range(1, maxlen + 1):
		code = (code + count[b - 1]) << 1 if b > 1 else 0
		next[b] = code
	var lookup: Array[int] = []
	lookup.resize(1 << maxlen)
	lookup.fill(0)
	for sym in lens.size():
		var l: int = lens[sym]
		if l == 0:
			continue
		var c: int = next[l]
		next[l] += 1
		var rev := 0
		for i in l:
			rev |= ((c >> i) & 1) << (l - 1 - i)
		var step := 1 << l
		var entry := (l << 16) | sym
		var k := rev
		while k < (1 << maxlen):
			lookup[k] = entry
			k += step
	return [maxlen, lookup]
