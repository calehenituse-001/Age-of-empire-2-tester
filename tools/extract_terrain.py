#!/usr/bin/env python3
"""Extracts the terrain tiles and the blending masks (for shorelines and other terrain edges) from an AoE2 HD install.

    python3 -I tools/extract_terrain.py --game /path/to/AoE2HD [--out godot_game/assets/aoe]

Writes terrain/t<terrain id>.png (100 tiles of 97x49 per terrain, a 10x10 pattern), terrain/blend.png (9 modes x 31 masks
in the alpha channel = how much of the neighbouring terrain shows) and terrain.json. Uses the terrain table imported by tools/import_dat.py (rules.json).
See docs/FORMATS.md, "Terrain blending".
"""
import argparse
import json
import struct
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from aoe_formats import read_drs, read_pal, decode_slp, frame_image  # noqa: E402

PAD = 1
TW, TH = 97, 49
WANT = {0: 'grass', 1: 'water', 2: 'beach', 3: 'dirt3', 4: 'shallows', 6: 'dirt', 9: 'grass3', 10: 'forest', 11: 'dirt2',
        12: 'grass2', 13: 'palm', 22: 'water2', 23: 'water3'}


# blend mode of the tile (row) and of the neighbour laid over it (column); the same table as scripts/terrain_blend.gd
LOOK = [[2, 3, 2, 1, 1, 6, 5, 4], [3, 3, 3, 1, 1, 6, 5, 4], [2, 3, 2, 1, 1, 6, 1, 4], [1, 1, 1, 0, 7, 6, 5, 4],
        [1, 1, 1, 7, 7, 6, 5, 4], [6, 6, 6, 6, 6, 6, 5, 4], [5, 5, 1, 5, 5, 5, 5, 4], [4, 3, 4, 4, 4, 4, 4, 4]]
USED = (0, 12, 9, 2, 4, 1)                # the three grasses, beach, shallows, water: the terrains the generated maps use
VARIANTS = [0, 27, 41, 66]                 # tile patterns used for blended tiles (keeps the atlas small)


def read_blendomatic(path):
    """9 blending modes, each 31 alpha masks as 97x49 arrays of weights 0..128 (-1 outside the diamond)."""
    b = Path(path).read_bytes()
    modes, tiles = struct.unpack_from('<II', b, 0)
    pos = 8
    out = []
    for _ in range(modes):
        px, = struct.unpack_from('<I', b, pos)
        pos += 4 + tiles
        pos += px * 4                          # the bit masks (which pixels count), not needed here
        masks = []
        for _ in range(tiles):
            data = b[pos:pos + px]
            pos += px
            rows, p = [], 0
            half = 49 // 2
            for y in range(49):
                n = 1 + 4 * y if y < half else 97 - 4 * (y - half)
                if y == half:
                    n = 97
                pad = 48 - n // 2
                rows.append([-1] * pad + list(data[p:p + n]) + [-1] * pad)
                p += n
            masks.append(rows)
        out.append(masks)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--game', type=Path, default=Path('/home/j3rry/AOE'))
    ap.add_argument('--out', type=Path, default=Path(__file__).resolve().parent.parent / 'godot_game' / 'assets' / 'aoe')
    a = ap.parse_args()
    rules = json.loads((a.out / 'data' / 'rules.json').read_text())
    terr = {t['id']: t for t in rules['terrains']}
    data = a.game / 'Data'
    drs = read_drs(data / 'terrain.drs')
    pal = read_pal(read_drs(data / 'interfac.drs')[('bina', 50500)].decode('latin1'))
    (a.out / 'terrain').mkdir(exist_ok=True)
    man = {'tiles': {}, 'blend': {}}
    for tid, name in WANT.items():
        t = terr[tid]
        frames = decode_slp(drs[('slp', t['slp_id'])])
        cw, ch = TW + 2 * PAD, TH + 2 * PAD
        sheet = Image.new('RGBA', (10 * cw, 10 * ch), (0, 0, 0, 0))
        for i, fr in enumerate(frames[:100]):
            sheet.paste(frame_image(fr, pal), ((i % 10) * cw + PAD, (i // 10) * ch + PAD))
        sheet.save(a.out / 'terrain' / f't{tid}.png', optimize=True)
        man['tiles'][str(tid)] = dict(file=f'terrain/t{tid}.png', name=name, cols=10, frames=len(frames), tw=TW, th=TH, cw=cw, ch=ch, pad=PAD,
                                      prio=t['blend_priority'], mode=t['blend_mode'], colour=t['map_color_med'])
    modes = read_blendomatic(data / 'blendomatic_x1.dat')
    cw, ch = TW + 2 * PAD, TH + 2 * PAD
    sheet = Image.new('RGBA', (31 * cw, len(modes) * ch), (0, 0, 0, 0))
    for m, masks in enumerate(modes):
        for k, rows in enumerate(masks):
            im = Image.new('RGBA', (TW, TH), (0, 0, 0, 0))
            px = im.load()
            for y, row in enumerate(rows):
                for x, v in enumerate(row):
                    if v >= 0:
                        px[x, y] = (255, 255, 255, 255 - min(255, round(v * 255 / 128)))   # 128 = keep the base pixel, 0 = take the neighbour's
            sheet.paste(im, (k * cw + PAD, m * ch + PAD))
    sheet.save(a.out / 'terrain' / 'blend.png', optimize=True)
    man['blend'] = dict(file='terrain/blend.png', modes=len(modes), masks=31, tw=TW, th=TH, cw=cw, ch=ch, pad=PAD)
    # pre-masked overlays: the neighbour's tile with the mask's weight as alpha, for every (terrain, mode) that can be laid over
    # another used terrain. The game lays these over a tile with a plain alpha blend (Image.blend_rect_mask is all-or-nothing).
    import numpy as np
    combos = []
    for me in USED:
        for o in USED:
            if terr[o]['blend_priority'] > terr[me]['blend_priority']:
                c = [o, LOOK[terr[me]['blend_mode']][terr[o]['blend_mode']]]
                if c not in combos:
                    combos.append(c)
    blend = Image.open(a.out / 'terrain' / 'blend.png').convert('RGBA')
    rows = len(combos) * len(VARIANTS)
    atlas = Image.new('RGBA', (31 * cw, rows * ch), (0, 0, 0, 0))
    sheets = {t: Image.open(a.out / 'terrain' / f't{t}.png').convert('RGBA') for t, _ in combos}
    for ci, (o, mode) in enumerate(combos):
        for vi, frame in enumerate(VARIANTS):
            tile = np.array(sheets[o].crop(((frame % 10) * cw + PAD, (frame // 10) * ch + PAD, (frame % 10) * cw + PAD + TW, (frame // 10) * ch + PAD + TH)))
            for k in range(31):
                m = np.array(blend.crop((k * cw + PAD, mode * ch + PAD, k * cw + PAD + TW, mode * ch + PAD + TH)))[:, :, 3].astype(np.float32) / 255.0
                out = tile.copy()
                out[:, :, 3] = (out[:, :, 3].astype(np.float32) * m).round().astype(np.uint8)
                atlas.paste(Image.fromarray(out), (k * cw + PAD, (ci * len(VARIANTS) + vi) * ch + PAD))
    atlas.save(a.out / 'terrain' / 'overlay.png', optimize=True)
    man['overlay'] = dict(file='terrain/overlay.png', combos=combos, variants=VARIANTS, cw=cw, ch=ch, pad=PAD, tw=TW, th=TH)
    (a.out / 'terrain.json').write_text(json.dumps(man, separators=(',', ':')))
    print('terrains', len(man['tiles']), 'blend modes', len(modes))


if __name__ == '__main__':
    main()
