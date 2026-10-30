class_name Drs
extends RefCounted
## A DRS archive (the game's resource containers). Reads the table of contents, then single files on demand (the archives are up
## to 86 MB, they are never loaded whole).

var path := ""
var _f: FileAccess
var _files: Dictionary = {}          # "ext:id" -> [offset, size]


static func open(p: String) -> Drs:
	var d := Drs.new()
	d.path = p
	d._f = FileAccess.open(p, FileAccess.READ)
	if d._f == null:
		return null
	d._f.seek(0x38)
	var ntab := d._f.get_32()
	d._f.get_32()
	for t in ntab:
		d._f.seek(0x40 + t * 12)
		var ext := d._f.get_buffer(4)
		ext.reverse()
		var e := ext.get_string_from_ascii().strip_edges()
		var toff := d._f.get_32()
		var nfiles := d._f.get_32()
		d._f.seek(toff)
		var table := d._f.get_buffer(nfiles * 12)
		for i in nfiles:
			d._files["%s:%d" % [e, table.decode_u32(i * 12)]] = [table.decode_u32(i * 12 + 4), table.decode_u32(i * 12 + 8)]
	return d


func has(ext: String, id: int) -> bool:
	return _files.has("%s:%d" % [ext, id])


func get_file(ext: String, id: int) -> PackedByteArray:
	var e: Variant = _files.get("%s:%d" % [ext, id])
	if e == null:
		return PackedByteArray()
	_f.seek(e[0])
	return _f.get_buffer(e[1])
