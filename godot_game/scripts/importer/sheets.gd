class_name Sheets
extends RefCounted
## Small helpers to lay sprites out on atlas sheets (images are RGBA8) and write them as PNG.

const PAD := 1          # transparent border around every atlas cell (keeps bilinear sampling from bleeding)


static func blank(w: int, h: int) -> Image:
	return Image.create_empty(maxi(w, 1), maxi(h, 1), false, Image.FORMAT_RGBA8)


## Copies src over dst at (x, y), replacing what is there (PIL's paste).
static func paste(dst: Image, src: Image, x: int, y: int) -> void:
	dst.blit_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i(x, y))


## Lays src over dst with alpha (PIL's alpha_composite).
static func over(dst: Image, src: Image, x: int, y: int) -> void:
	dst.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i(x, y))


static func save(img: Image, path: String) -> void:
	var tmp := path + ".part"
	img.save_png(tmp)
	DirAccess.rename_absolute(tmp, path)


## angles x N frames; one row per angle, one column per frame. Returns the manifest entry (without file and dur).
static func animation(frames: Array, angles: int, path: String) -> Dictionary:
	var fpa := frames.size() / angles
	var cw := 0
	var ch := 0
	for f: Dictionary in frames:
		cw = maxi(cw, f.w)
		ch = maxi(ch, f.h)
	cw += 2 * PAD
	ch += 2 * PAD
	var sheet := blank(fpa * cw, angles * ch)
	var meta := []
	for a in angles:
		var row := []
		for k in fpa:
			var fr: Dictionary = frames[a * fpa + k]
			paste(sheet, fr.img, k * cw + PAD, a * ch + PAD)
			row.append([fr.w, fr.h, fr.hx, fr.hy])
		meta.append(row)
	save(sheet, path)
	return {"fpa": fpa, "angles": angles, "cw": cw, "ch": ch, "pad": PAD, "frames": meta}


## Like animation() for frames already composited: [{img, hx, hy}] row after row.
static func animation_images(frames: Array, rows: int, fpa: int, path: String) -> Dictionary:
	var cw := 0
	var ch := 0
	for f: Dictionary in frames:
		cw = maxi(cw, f.img.get_width())
		ch = maxi(ch, f.img.get_height())
	cw += 2 * PAD
	ch += 2 * PAD
	var sheet := blank(fpa * cw, rows * ch)
	var meta := []
	for a in rows:
		var row := []
		for k in fpa:
			var f: Dictionary = frames[a * fpa + k]
			paste(sheet, f.img, k * cw + PAD, a * ch + PAD)
			row.append([f.img.get_width(), f.img.get_height(), f.hx, f.hy])
		meta.append(row)
	save(sheet, path)
	return {"fpa": fpa, "angles": rows, "cw": cw, "ch": ch, "pad": PAD, "frames": meta}


## Variable-size frames side by side; returns the item rectangles.
static func strip(frames: Array, path: String) -> Array:
	var total := 0
	var hmax := 0
	for f: Dictionary in frames:
		total += f.w + 2 * PAD
		hmax = maxi(hmax, f.h)
	hmax += 2 * PAD
	var sheet := blank(total, hmax)
	var x := 0
	var items := []
	for f: Dictionary in frames:
		paste(sheet, f.img, x + PAD, PAD)
		items.append({"x": x + PAD, "y": PAD, "w": f.w, "h": f.h, "hx": f.hx, "hy": f.hy})
		x += f.w + 2 * PAD
	save(sheet, path)
	return items
