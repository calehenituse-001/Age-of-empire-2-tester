class_name DatReader
extends RefCounted
## Reads empires2_x1_p1.dat (the game's rules: units, buildings, techs, graphics, terrains ...). The layout of the file comes from
## data/dat_schema.json (see tools/make_dat_schema.py); this interprets it. Returns nested Dictionaries/Arrays named like the
## fields of the file.

const SCHEMA := "res://data/dat_schema.json"

var _classes: Dictionary = {}
var _d: PackedByteArray
var _pos := 0
var progress := 0.0                 # 0..1 while read() runs (for a progress bar), read from another thread


func _init() -> void:
	var s: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SCHEMA))
	_classes = s.classes
	_root = s.root
	for cname: String in _classes:
		for op: Dictionary in _classes[cname]:
			if op.has("t"):
				op["tc"] = _TYPES[op.t]
				op["sz"] = _SIZES[op.t]


var _root := ""
var _trace := false

const _TYPES := {"char": 0, "int8_t": 1, "uint8_t": 2, "int16_t": 3, "uint16_t": 4, "int32_t": 5, "uint32_t": 6, "float": 7}
const _SIZES := {"char": 1, "int8_t": 1, "uint8_t": 1, "int16_t": 2, "uint16_t": 2, "int32_t": 4, "uint32_t": 4, "float": 4}


func read(data: PackedByteArray) -> Dictionary:
	_d = data
	_pos = 0
	var out := {}
	_struct(_root, {}, out)
	if _pos != data.size():
		push_error("dat parse stopped at %d of %d bytes" % [_pos, data.size()])
		return {}
	progress = 1.0
	return out


func _num(tc: int) -> Variant:
	var v: Variant
	match tc:
		1: v = _d.decode_s8(_pos)
		2: v = _d.decode_u8(_pos)
		3: v = _d.decode_s16(_pos)
		4: v = _d.decode_u16(_pos)
		5: v = _d.decode_s32(_pos)
		6: v = _d.decode_u32(_pos)
		7: v = _d.decode_float(_pos)
		_: v = _d.decode_u8(_pos)
	return v


func _count(c: Variant, scope: Dictionary) -> int:
	if c is String:
		return int(scope.get(c, 0))
	if c is Dictionary:
		return int(scope.get(c["if"][1], 0)) if int(scope.get(c["if"][0], 0)) != 0 else 0
	return int(c)


func _struct(cname: String, scope: Dictionary, out: Variant) -> void:
	var stop := false
	for op: Dictionary in _classes[cname]:
		if stop:
			return
		match op.k:
			"skip":
				_pos += int(op.n)
			"p":
				if _prim(op, scope, out):
					stop = true
			"inc":
				_struct(op.c, scope, out if int(op.a) == 2 else null)
			"grp":
				var sub := {}
				_struct(op.c, {}, sub)
				if int(op.a) == 2 and out != null:
					out[op.n] = [sub] if op.st == "ac" else sub
			"sub", "multi":
				_array(op, scope, out)


## Reads one field; returns true when the rest of the structure is absent (an "exists" flag of 0).
func _prim(op: Dictionary, scope: Dictionary, out: Variant) -> bool:
	var acc: int = op.a
	var tc: int = op.tc
	var sz: int = op.sz
	if op.has("c"):
		var n := _count(op.c, scope)
		if acc == 0:
			_pos += n * sz
			return false
		if op.has("str"):
			var s := _string(n)
			scope[op.n] = s
			if acc == 2 and out != null:
				out[op.n] = s
			return false
		var arr := []
		arr.resize(n)
		var b: bool = op.st == "ab"
		for i in n:
			var v: Variant = _num(tc)
			_pos += sz
			arr[i] = (v != 0) if b else v
		scope[op.n] = arr
		if acc == 2 and out != null:
			out[op.n] = arr
		return false
	if acc == 0:
		_pos += sz
		return false
	var v: Variant = _num(tc)
	_pos += sz
	scope[op.n] = v
	if acc == 2 and out != null:
		match op.st:
			"b": out[op.n] = v != 0
			"s": out[op.n] = op.lk[str(v)] if op.has("lk") else v
			_: out[op.n] = v
	return op.has("abort0") and v == 0


func _string(n: int) -> String:
	var bytes := _d.slice(_pos, _pos + n)
	_pos += n
	var z := bytes.find(0)
	if z >= 0:
		bytes = bytes.slice(0, z)
	var ascii := true
	for c in bytes:
		if c > 127:
			ascii = false
			break
	if ascii:
		return bytes.get_string_from_ascii()
	var s := ""
	for c in bytes:
		s += char(c)
	return s


func _array(op: Dictionary, scope: Dictionary, out: Variant) -> void:
	var n := _count(op.len, scope)
	var offs: Variant = scope[op.off] if op.has("off") else null
	var multi: bool = op.k == "multi"
	var keep: bool = int(op.a) == 2 and out != null
	var list := []
	for i in n:
		if offs != null and int(offs[i]) <= 0:
			continue
		var child := {}
		var inner := {}
		if op.has("pass"):
			for p: String in op["pass"]:
				inner[p] = scope.get(p, 0)
		var cls: String
		if multi:
			var sd: Dictionary = op.sub
			var tag: int = _num(_TYPES[sd.t])
			_pos += _SIZES[sd.t]
			cls = op.cls[str(tag)]
			if int(sd.a) == 2:
				child[sd.n] = tag
		else:
			cls = op.c
		_struct(cls, inner, child if keep else null)
		if keep:
			list.append(child)
		if cls == "Civ" or cls == "Graphic":
			progress = float(_pos) / float(_d.size())
			if OS.is_stdout_verbose() or _trace:
				print("%s #%d at %d" % [cls, i, _pos])
	if keep:
		out[op.n] = list
