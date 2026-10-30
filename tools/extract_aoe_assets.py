#!/usr/bin/env python3
"""Extract a small set of sprites from an Age of Empires II HD install for the personal sample.

Usage:  python3 extract_aoe_assets.py [GAME_DIR] [OUT_DIR]
Reads the game's DRS archives and loose SLP files (read-only) and writes PNG atlases plus
manifest.js into OUT_DIR.  Needs Pillow.

Formats handled: DRS archive, SLP v2.0N sprites, JASC palettes.
"""
import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

GAME = Path(sys.argv[1] if len(sys.argv) > 1 else '/home/j3rry/AOE')
OUT = Path(sys.argv[2] if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / 'aoe_assets')


from aoe_formats import read_drs, read_pal, decode_slp, frame_image  # noqa: E402


# ---------------------------------------------------------------- packers
def pack_grid(frames, pal, cols, cell_w, cell_h, path):
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new('RGBA', (cols * cell_w, rows * cell_h), (0, 0, 0, 0))
    meta = []
    for i, fr in enumerate(frames):
        im = frame_image(fr, pal)
        sheet.paste(im, ((i % cols) * cell_w, (i // cols) * cell_h))
        meta.append([fr['w'], fr['h'], fr['hx'], fr['hy']])
    sheet.save(path)
    return meta


def pack_animation(frames, pal, path, angles=5):
    """5 stored angles x N frames; one row per angle."""
    fpa = len(frames) // angles
    cw = max(f['w'] for f in frames)
    ch = max(f['h'] for f in frames)
    meta = pack_grid(frames[:fpa * angles], pal, fpa, cw, ch, path)
    return dict(fpa=fpa, cw=cw, ch=ch, frames=[meta[a * fpa:(a + 1) * fpa] for a in range(angles)])


def pack_strip(frames, pal, path):
    """Variable-size frames side by side; returns rects."""
    gap = 2
    total = sum(f['w'] + gap for f in frames)
    hmax = max(f['h'] for f in frames)
    sheet = Image.new('RGBA', (total, hmax), (0, 0, 0, 0))
    x = 0
    items = []
    for fr in frames:
        sheet.paste(frame_image(fr, pal), (x, 0))
        items.append(dict(x=x, y=0, w=fr['w'], h=fr['h'], hx=fr['hx'], hy=fr['hy']))
        x += fr['w'] + gap
    sheet.save(path)
    return items


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    data = GAME / 'Data'
    graphics = read_drs(data / 'graphics.drs')
    interfac = read_drs(data / 'interfac.drs')
    terrain = read_drs(data / 'terrain.drs')
    pal_main = read_pal(interfac[('bina', 50500)].decode('latin1'))
    manifest = {'terrain': {}, 'buildings': {}, 'trees': {}, 'units': {}}

    # terrain: 100 frames per tile type, 10x10 pattern; frame = (x % 10) + (y % 10) * 10
    for name, sid in [('grass', 15008)]:
        frames = decode_slp(terrain[('slp', sid)])
        pack_grid(frames, pal_main, 10, 97, 49, OUT / f'terrain_{name}.png')
        manifest['terrain'][name] = dict(file=f'terrain_{name}.png', cols=10, tw=97, th=49)

    # town centre, western Imperial age: garden plaza (RTWC4N1E) drawn first, then the building (RTWC4NNE).
    # Both hotspots refer to the centre of the 4x4 footprint.
    for name, sid in [('tc_plaza', 920), ('tc', 924)]:
        fr = decode_slp(graphics[('slp', sid)])[0]
        frame_image(fr, pal_main, shadow_idx=(0, 206)).save(OUT / f'{name}.png')
        manifest['buildings'][name] = dict(file=f'{name}.png', w=fr['w'], h=fr['h'], hx=fr['hx'], hy=fr['hy'])

    # trees: loose forest SLPs come with their own palettes
    tree_frames, kinds = [], []
    for slp, palf, picks, kind in [('foak_nn', 'pal_2', [0, 1, 2, 4, 9, 10, 11, 12, 13], 'oak'),
                                   ('fpin_nn', 'pal_4', [1, 2, 3, 4, 7], 'pine')]:
        frames = decode_slp((data / 'Slp' / f'{slp}.slp').read_bytes())
        pal = read_pal((data / f'{palf}.pal').read_text())
        for k in picks:
            tree_frames.append((frames[k], pal))
            kinds.append(kind)
    gap = 2
    total = sum(f['w'] + gap for f, _ in tree_frames)
    hmax = max(f['h'] for f, _ in tree_frames)
    sheet = Image.new('RGBA', (total, hmax), (0, 0, 0, 0))
    x, items = 0, []
    for (fr, pal), kind in zip(tree_frames, kinds):
        sheet.paste(frame_image(fr, pal), (x, 0))
        items.append(dict(x=x, y=0, w=fr['w'], h=fr['h'], hx=fr['hx'], hy=fr['hy'], kind=kind))
        x += fr['w'] + gap
    sheet.save(OUT / 'trees.png')
    manifest['trees'] = dict(file='trees.png', items=items)

    # villagers: male VM*, female VF*  (walk, lumberjack walk, chop)
    anims = {
        'male_walk': (1484, .07), 'male_lumber_walk': (1548, .07), 'male_chop': (1535, .10),
        'female_walk': (1392, .07), 'female_lumber_walk': (1444, .07), 'female_chop': (1434, .10),
    }
    for name, (sid, dur) in anims.items():
        info = pack_animation(decode_slp(graphics[('slp', sid)]), pal_main, OUT / f'{name}.png')
        info.update(file=f'{name}.png', dur=dur)
        manifest['units'][name] = info

    (OUT / 'manifest.js').write_text('window.AOE_MANIFEST = ' + json.dumps(manifest, separators=(',', ':')) + ';\n')
    print('wrote', len(list(OUT.glob('*.png'))), 'PNGs and manifest.js to', OUT)


if __name__ == '__main__':
    main()
