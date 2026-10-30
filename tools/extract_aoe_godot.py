#!/usr/bin/env python3
"""Extract the sprites for the Godot game from an Age of Empires II HD install.

Usage:  python3 extract_aoe_godot.py [GAME_DIR] [OUT_DIR]
Reads the game's DRS archives and loose SLP files (read-only) and writes PNG atlases plus
manifest.json into OUT_DIR (default: ../godot_game/assets/aoe).  Needs Pillow.

SLP ids come from the graphics table (graphics.drs ids; the names in the comments are the game's own
graphic names).  Animations store 5 angles; the other 3 are mirrors, which the game does with flip_h.
"""
import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from aoe_formats import read_drs, read_pal, decode_slp, frame_image  # noqa: E402

GAME = Path(sys.argv[1] if len(sys.argv) > 1 else '/home/j3rry/AOE')
OUT = Path(sys.argv[2] if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / 'godot_game' / 'assets' / 'aoe')

RED = 32          # player-colour palette offset that gives red (blue is 0)
BUILDING_SHADOW = (0, 206)  # palette indices buildings use for their baked-in shadow
PAD = 1           # transparent border around every atlas cell (keeps bilinear sampling from bleeding)

# name: (slp id, seconds per frame, graphic name)
VILLAGER_ANIMS = {
    'walk':       ((1484, 1392), .07),    # VMBAS_WN / VFBAS_WN
    'stand':      ((1479, 1388), .25),    # VMBAS_FN / VFBAS_FN (idle fidget; the *_SN sprites are corpses)
    'carry_wood': ((1536, 1883), .07),    # VMLUM_CN / VFLUM_CN
    'carry_ore':  ((1552, 1879), .07),    # VMMIN_CN / VFMIN_CN
    'carry_food': ((2592, 4602), .07),    # VMFOR_CN / VFFOR_CN
    'chop':       ((1545, 1884), .10),    # VMLUM_TN / VFLUM_TN
    'mine':       ((1560, 1880), .10),    # VMMIN_TN / VFMIN_TN
    'forage':     ((2589, 2573), .20),    # VMFOR_TN / VFFOR_TN
    'farm':       ((1512, 1876), .13),    # VMFAR_TN / VFFAR_TN
    'build':      ((1496, 1874), .07),    # VMBLD_TN / VFBLD_TN
    'die':        ((1476, 1385), .10),    # VMBAS_DN / VFBAS_DN
}

# kind: {anim: (slp, seconds per frame)}
FIGHTERS = {
    'militia':   {'walk': (1048, .09), 'attack': (1038, .16), 'stand': (1044, .25), 'die': (1041, .10)},   # SWDMN_*
    'archer':    {'walk': (12, .07),   'attack': (2, .07),    'stand': (8, .20),    'die': (5, .10)},      # ARCHR_*
    'twohand':   {'walk': (1185, .09), 'attack': (1175, .12), 'stand': (1181, .25), 'die': (1178, .10)},   # THSWD_*
    'crossbow':  {'walk': (1654, .07), 'attack': (1644, .10), 'stand': (1650, .20), 'die': (1647, .10)},   # XBOWM_*
    'spearman':  {'walk': (997, .07),  'attack': (987, .10),  'stand': (993, .25),  'die': (990, .10)},    # SPRMN_*
    'knight':    {'walk': (673, .11),  'attack': (663, .135), 'stand': (669, .20),  'die': (666, .185)},   # KNGHT_*
}
RED_FIGHTERS = ('militia', 'archer', 'twohand', 'crossbow')
BLUE_FIGHTERS = ('militia', 'archer', 'twohand', 'crossbow', 'spearman', 'knight')

ANIMALS = {
    'wolf': {'walk': (1640, .09), 'run': (1636, .07), 'attack': (1629, .09), 'stand': (1635, .10), 'die': (1632, .10)},  # WOLFX_*
    'boar': {'walk': (2559, .10), 'run': (3577, .09), 'attack': (2555, .10), 'stand': (2557, .12), 'die': (2556, .10)},  # BOARX_*
}

# name: (slp, graphic name) -- finished buildings, western set (E), hotspot = centre of the footprint
BUILDINGS = {
    # town centre, one look per level (Dark, Feudal, Castle, Imperial). The original draws it from separate
    # pieces on one hotspot: the left wing parts (N4, N3, N2, all left of the hotspot), the right wing parts
    # (N7, N6, N5, all right of it) and the main hall (NN) last so its whole front stays visible.
    'tc': [3596, 3595, 4612, 4611, 3594, 4610, 891],      # RTWC1  (Dark Age)
    'tc2': [3605, 3601, 4621, 4617, 3597, 4613, 900],     # RTWC2E (Feudal)
    'tc3': [3617, 3613, 4633, 4629, 3609, 4625, 912],     # RTWC3E (Castle)
    'tc4': [3473, 3469, 4645, 4641, 3465, 4637, 924],     # RTWC4E (Imperial)
    # the ground under each look: shadow (N0) and, in the Imperial age, the garden (N1)
    'tc_plaza1': [889],
    'tc_plaza2': [892],
    'tc_plaza3': [904],
    'tc_plaza4': [916, 920],
    'house': 2232,        # HOUS2NNE (3 variants, frame 0 used)
    'barracks': 130,      # BRKS2NNE
    'mill': 738,          # MILL2NNE
    'lumber_camp': 3504,  # SMIL1NNGE
    'mining_camp': 3492,  # MINE1NNGE
    'tower': 2652,        # WCTW1NNGE
    'tower2': 2664,       # WCTW2NNGE  guard tower
    'tower3': 2538,       # WCTW3NNGE  keep
    'tower4': 2546,       # WCTW4NNGE  bombard tower, used as the top level
    'rubble1': 928,       # RUBL1_NN   what a destroyed building leaves behind, by footprint size
    'rubble2': 929,       # RUBL2_NN
    'rubble3': 930,       # RUBL3_NN
}

WALL_SLP = 2098        # WALL2NNE

TREE_SETS = [('foak_nn', 'pal_2', [0, 1, 2, 4, 9, 10, 11, 12, 13], 'oak'),
             ('fpin_nn', 'pal_4', [1, 2, 3, 4, 7], 'pine')]


# ---------------------------------------------------------------- packers
def pack_animation(frames, pal, path, angles=5, pc_offset=0):
    """angles x N frames; one row per angle, one column per frame."""
    fpa = len(frames) // angles
    cw = max(f['w'] for f in frames) + 2 * PAD
    ch = max(f['h'] for f in frames) + 2 * PAD
    sheet = Image.new('RGBA', (fpa * cw, angles * ch), (0, 0, 0, 0))
    meta = []
    for a in range(angles):
        row = []
        for k in range(fpa):
            fr = frames[a * fpa + k]
            sheet.paste(frame_image(fr, pal, pc_offset=pc_offset), (k * cw + PAD, a * ch + PAD))
            row.append([fr['w'], fr['h'], fr['hx'], fr['hy']])
        meta.append(row)
    sheet.save(path, optimize=True)
    return dict(fpa=fpa, angles=angles, cw=cw, ch=ch, pad=PAD, frames=meta)


def pack_strip(frames_pal, path, shadow_idx=()):
    """Variable-size frames side by side; returns item rects."""
    total = sum(f['w'] + 2 * PAD for f, _ in frames_pal)
    hmax = max(f['h'] for f, _ in frames_pal) + 2 * PAD
    sheet = Image.new('RGBA', (total, hmax), (0, 0, 0, 0))
    x, items = 0, []
    for fr, pal in frames_pal:
        sheet.paste(frame_image(fr, pal, shadow_idx=shadow_idx), (x + PAD, PAD))
        items.append(dict(x=x + PAD, y=PAD, w=fr['w'], h=fr['h'], hx=fr['hx'], hy=fr['hy']))
        x += fr['w'] + 2 * PAD
    sheet.save(path, optimize=True)
    return items


def pack_terrain(frames, pal, cols, path):
    tw, th = frames[0]['w'], frames[0]['h']
    cw, ch = tw + 2 * PAD, th + 2 * PAD
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new('RGBA', (cols * cw, rows * ch), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        sheet.paste(frame_image(fr, pal), ((i % cols) * cw + PAD, (i // cols) * ch + PAD))
    sheet.save(path, optimize=True)
    return dict(file=path.name, cols=cols, frames=len(frames), tw=tw, th=th, cw=cw, ch=ch, pad=PAD)


def gold_mine(stone_frames, fleck_frames, pal):
    """The game draws gold as bare nuggets; give them a golden rock body so a mine reads at a glance."""
    out = []
    for stone, fleck in zip(stone_frames, fleck_frames):
        body = frame_image(stone, pal)
        px = body.load()
        for y in range(body.height):
            for x in range(body.width):
                r, g, b, a = px[x, y]
                if a:
                    lum = (r + g + b) / 3 / 255
                    px[x, y] = (int(70 + 175 * lum), int(48 + 150 * lum), int(8 + 40 * lum), a)
        nug = frame_image(fleck, pal)
        w = max(body.width, nug.width) + 6
        h = max(body.height, nug.height) + 8
        im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        bx, by = (w - body.width) // 2, h - body.height - 2
        im.alpha_composite(body, (bx, by))
        nx = bx + (body.width - nug.width) // 2
        ny = by + body.height - nug.height - 2
        im.alpha_composite(nug, (nx, ny))
        out.append((im, (bx + stone['hx'], by + stone['hy'])))
    return out


SOUNDS = [  # file names in the game's sound table; used by the game as sets, see sfx.gd
    'SWORD1 SWORD2 SWORD3 SWORD4 SWORD5 SWORD6 SWORD7 ARROW1 ARROW2 ARROW3 ARROW4 ARROW5 DAGGER1 DAGGER2 DAGGER3 '
    'GRUNT1 GRUNT2 GRUNT3 DEATH1 DEATH2 DEATH3 DEATH4 DEATH5 DEATH6 FDIE1 FDIE3 FDIE4 WOLFF1 WOLFF2 WOLFF3 HITWALL EXP1 EXP2 '
    'CHOPS1 CHOPS2 CHOPS3 ORE1 ORE2 ORE3 GATHER1 GATHER2 FARM1 FARM2 FARM3 HAMMER1 HAMMER2 HAMMER3 FALL1 '
    'READY READYM MDONE CONVERT1 CONVERT2 PUPRELIC'
]
MUSIC = [('music1.mp3', 'm1.mp3'), ('xmusic1.mp3', 'm2.mp3')]
MUSIC_BYTES = 6_000_000     # the first ~4 minutes of each (192 kbps), cut at an arbitrary frame: plenty of music, small APK


def extract_sounds(game, out):
    import re
    import struct
    import zlib
    data = zlib.decompress((game / 'Data' / 'empires2_x1_p1.dat').read_bytes(), wbits=-15)
    ids = {}
    for m in re.finditer(rb'([A-Za-z0-9_\-]{1,12})\.wav\x00', data[:90000], re.I):
        rid, = struct.unpack_from('<i', data, m.start() + 13)
        ids.setdefault(m.group(1).decode().upper(), rid)
    drs = {}
    for f in ('sounds.drs', 'sounds_x1.drs'):
        drs.update(read_drs(game / 'Data' / f))
    snd = out / 'snd'
    snd.mkdir(exist_ok=True)
    n = 0
    for name in SOUNDS[0].split():
        wav = drs.get(('wav', ids.get(name, -1)))
        if wav is None:
            print('missing sound', name)
            continue
        (snd / f'{name.lower()}.wav').write_bytes(wav)
        n += 1
    mus = out / 'music'
    mus.mkdir(exist_ok=True)
    for src, dst in MUSIC:
        f = game / 'Sound' / 'music' / src
        if f.exists():
            with open(f, 'rb') as fh:
                (mus / dst).write_bytes(fh.read(MUSIC_BYTES))
    return n


def extract_markers(graphics, interfac, pal):
    """The marks shown where units are sent. `move` is the four arrows closing in on a spot (graphic MOVETO, graphics.drs slp 3405; frame 0 and
    the last frame are empty). The game's picture is red; it is saved with red and green swapped because the arrows are green in the player's
    memory of the game. `target` keeps the red original (the mouse cursor "arrow over ripples", interfac 51000 frame 17, goes with `cursor`)."""
    frames = [f for f in decode_slp(graphics[('slp', 3405)]) if f['w'] > 1]
    move = pack_strip([(f, pal) for f in frames], OUT / 'a_marker_move.png')
    im = Image.open(OUT / 'a_marker_move.png').convert('RGBA')
    r, g, b, a = im.split()
    Image.merge('RGBA', (g, r, b, a)).save(OUT / 'a_marker_move.png', optimize=True)
    target = pack_strip([(f, pal) for f in frames], OUT / 'a_marker_target.png')
    cursor = pack_strip([(decode_slp(interfac[('slp', 51000)])[17], pal)], OUT / 'a_marker_cursor.png')
    return {'move': dict(file='a_marker_move.png', items=move, spf=0.125), 'target': dict(file='a_marker_target.png', items=target, spf=0.125),
            'cursor': dict(file='a_marker_cursor.png', items=cursor)}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    data = GAME / 'Data'
    graphics = read_drs(data / 'graphics.drs')
    interfac = read_drs(data / 'interfac.drs')
    terrain = read_drs(data / 'terrain.drs')
    pal = read_pal(interfac[('bina', 50500)].decode('latin1'))
    slp = lambda sid: decode_slp(graphics[('slp', sid)])  # noqa: E731
    man = {'terrain': {}, 'buildings': {}, 'resources': {}, 'anims': {}}

    # terrain: 100 frames per tile type, 10x10 pattern; frame = (x % 10) + (y % 10) * 10
    for name, sid, cols in [('grass', 15008, 10), ('dirt', 15000, 10), ('farm_fresh', 15021, 3), ('farm_grown', 15023, 3)]:
        man['terrain'][name] = pack_terrain(decode_slp(terrain[('slp', sid)]), pal, cols, OUT / f'terrain_{name}.png')

    # buildings, one PNG each
    for name, sid in BUILDINGS.items():
        parts = []
        for e in (sid if isinstance(sid, list) else [sid]):
            i, dx, dy = e if isinstance(e, tuple) else (e, 0, 0)
            parts.append((slp(i)[0], dx, dy))
        x0 = min(dx - f['hx'] for f, dx, dy in parts)
        y0 = min(dy - f['hy'] for f, dx, dy in parts)
        w = max(dx - f['hx'] + f['w'] for f, dx, dy in parts) - x0
        h = max(dy - f['hy'] + f['h'] for f, dx, dy in parts) - y0
        hx, hy = -x0, -y0
        img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        for f, dx, dy in parts:
            img.alpha_composite(frame_image(f, pal, shadow_idx=BUILDING_SHADOW), (dx - f['hx'] - x0, dy - f['hy'] - y0))
        img.save(OUT / f'b_{name}.png', optimize=True)
        man['buildings'][name] = dict(file=f'b_{name}.png', w=w, h=h, hx=hx, hy=hy)

    # stone wall: 5 pieces (0 = run along y, 1 = run along x, 2 = post for corners and junctions)
    man['walls'] = dict(file='b_wall.png', items=pack_strip([(f, pal) for f in slp(WALL_SLP)], OUT / 'b_wall.png', shadow_idx=BUILDING_SHADOW))

    man['markers'] = extract_markers(graphics, interfac, pal)

    # fire laid over damaged buildings: small, medium and large (DMGA3, DMGB3, DMGC3)
    for name, sid in [('fire_s', 362), ('fire_m', 363), ('fire_l', 364)]:
        info = pack_animation(slp(sid), pal, OUT / f'a_{name}.png', angles=1)
        info.update(file=f'a_{name}.png', dur=0.05)
        man['anims'][name] = info

    # construction foundations (stakes, planks, stones) for 1x1 .. 4x4 footprints, 3 stages each
    man['foundations'] = {}
    for n, sid in enumerate([236, 237, 238, 239], 1):
        man['foundations'][str(n)] = dict(file=f'found_{n}.png', items=pack_strip([(f, pal) for f in slp(sid)], OUT / f'found_{n}.png', shadow_idx=BUILDING_SHADOW))

    # trees: the loose forest SLPs come with their own palettes
    tree_frames = []
    kinds = []
    for slp_name, palf, picks, kind in TREE_SETS:
        frames = decode_slp((data / 'Slp' / f'{slp_name}.slp').read_bytes())
        tpal = read_pal((data / f'{palf}.pal').read_text())
        for k in picks:
            tree_frames.append((frames[k], tpal))
            kinds.append(kind)
    items = pack_strip(tree_frames, OUT / 'r_trees.png')
    for it, kind in zip(items, kinds):
        it['kind'] = kind
    man['resources']['trees'] = dict(file='r_trees.png', items=items)

    # stone, gold, berries: several variants each
    for name, sid in [('stone', 1034), ('berries', 2560)]:
        frames = slp(sid)
        man['resources'][name] = dict(file=f'r_{name}.png', items=pack_strip([(f, pal) for f in frames], OUT / f'r_{name}.png'))
    stone_f, fleck_f = slp(1034), slp(2561)
    gold = gold_mine(stone_f, fleck_f, pal)
    sheet_items, total, hmax = [], 0, max(im.height for im, _ in gold) + 2 * PAD
    sheet = Image.new('RGBA', (sum(im.width + 2 * PAD for im, _ in gold), hmax), (0, 0, 0, 0))
    for im, (hx, hy) in gold:
        sheet.paste(im, (total + PAD, PAD))
        sheet_items.append(dict(x=total + PAD, y=PAD, w=im.width, h=im.height, hx=hx, hy=hy))
        total += im.width + 2 * PAD
    sheet.save(OUT / 'r_gold.png', optimize=True)
    man['resources']['gold'] = dict(file='r_gold.png', items=sheet_items)

    # villagers: male (VM*) and female (VF*)
    for gi, gender in enumerate(('m', 'f')):
        for name, (ids, dur) in VILLAGER_ANIMS.items():
            info = pack_animation(slp(ids[gi]), pal, OUT / f'a_v{gender}_{name}.png')
            info.update(file=f'a_v{gender}_{name}.png', dur=dur)
            man['anims'][f'v{gender}_{name}'] = info

    # soldiers: blue for the player, red for the enemy
    for kind, anims in FIGHTERS.items():
        for colour, off, allowed in (('blue', 0, BLUE_FIGHTERS), ('red', RED, RED_FIGHTERS)):
            if kind not in allowed:
                continue
            for name, (sid, dur) in anims.items():
                key = f'{kind}_{colour}_{name}'
                info = pack_animation(slp(sid), pal, OUT / f'a_{key}.png', pc_offset=off)
                info.update(file=f'a_{key}.png', dur=dur)
                man['anims'][key] = info

    # wild animals
    for kind, anims in ANIMALS.items():
        for name, (sid, dur) in anims.items():
            key = f'{kind}_{name}'
            info = pack_animation(slp(sid), pal, OUT / f'a_{key}.png')
            info.update(file=f'a_{key}.png', dur=dur)
            man['anims'][key] = info

    (OUT / 'manifest.json').write_text(json.dumps(man, separators=(',', ':')))
    print('sounds:', extract_sounds(GAME, OUT))
    pngs = list(OUT.glob('*.png'))
    print('wrote', len(pngs), 'PNGs (%.1f MB) and manifest.json to' % (sum(p.stat().st_size for p in pngs) / 1e6), OUT)


if __name__ == '__main__':
    main()
