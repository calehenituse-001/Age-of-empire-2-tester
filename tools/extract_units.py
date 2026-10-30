#!/usr/bin/env python3
"""Extracts sprites for units and buildings from an AoE2 HD install, driven by the imported rules
(tools/import_dat.py): no hand-picked SLP numbers.

    python3 -I tools/extract_units.py --game /path/to/AoE2HD [--out godot_game/assets/aoe] [--only 74,38,109]

Writes u_*.png / bld_*.png atlases and units.json next to the other extracted assets.
 - units: idle, walk, attack, die and the corpse (the dead unit's idle graphic) as angles x frames sheets;
   the SLP stores 5 angles, the other 3 are mirrors (done by flip_h in the game); `red` sheets (player colour +32)
   exist for the units an enemy may field.
 - buildings: the idle graphic plus its delta pieces (recursively, with their offsets) composited on one hotspot and drawn
   by layer; the Town Center uses its head unit's assembly; every age's look is its own unit id (see TechState.current()).
"""
import argparse
import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from aoe_formats import read_drs, read_pal, decode_slp, frame_image  # noqa: E402

PAD = 1
ANNEX_SCALE = 0.0   # annex pieces carry their own hotspots; 1.0 would also shift them by the dat offsets (wrong)
RED = 32
BUILDING_SHADOW = (0, 206)
UNIT_ANIMS = {"idle": "idle", "walk": "move", "attack": "attack", "die": "die"}
SKIP_NAMES = ("Relic", "Yurt", "Pavilion", "Bridge", "Genitour", "Ornlu", "Horse", "Sea ", "Wolf", "Boar", "Deer")
EXTRA_UNITS = [53, 65, 69, 450, 451, 455, 456, 457, 458, 285, 286]     # Gaia's fish (Perch, Shore Fish, Marlin, Dorado, Salmon, Tuna, Snapper), the Relic and the Monk with Relic
NAVAL_WAR = {21, 250, 420, 442, 527, 528, 529, 532, 533, 539, 691, 831, 832}      # warships an enemy may sail (red sheets)
ENEMY_CLASSES = {0, 6, 12, 18, 22, 23, 36, 44, 47, 50, 54}   # archers, infantry, cavalry, ... (see FORMATS.md)


def save_png(img, path):
    """Palette PNG when the image has at most 256 colours (lossless, about half the size), else RGBA."""
    if img.getcolors(maxcolors=256) is not None:
        img = img.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    img.save(path, optimize=True)


def pack_animation(frames, pal, path, angles, pc_offset=0):
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
    save_png(sheet, path)
    return dict(fpa=fpa, angles=angles, cw=cw, ch=ch, pad=PAD, frames=meta)


def pack_images(frames, rows, fpa, path):
    """Like pack_animation for already composited frames: frames is [(PIL image, hotspot x, hotspot y)] row after row."""
    cw = max(im.width for im, _, _ in frames) + 2 * PAD
    ch = max(im.height for im, _, _ in frames) + 2 * PAD
    sheet = Image.new('RGBA', (fpa * cw, rows * ch), (0, 0, 0, 0))
    meta = []
    for a in range(rows):
        row = []
        for k in range(fpa):
            im, hx, hy = frames[a * fpa + k]
            sheet.paste(im, (k * cw + PAD, a * ch + PAD))
            row.append([im.width, im.height, hx, hy])
        meta.append(row)
    save_png(sheet, path)
    return dict(fpa=fpa, angles=rows, cw=cw, ch=ch, pad=PAD, frames=meta)


class Extractor:
    def __init__(self, game: Path, out: Path):
        data = game / 'Data'
        self.out = out
        self.rules = json.loads((out / 'data' / 'rules.json').read_text())
        self.G = json.loads((out / 'data' / 'graphics.json').read_text())
        self.U = self.rules['units']
        self.drs = read_drs(data / 'graphics.drs')
        interfac = read_drs(data / 'interfac.drs')
        self.pal = read_pal(interfac[('bina', 50500)].decode('latin1'))
        self.cache = {}
        self.style_gfx = self.rules['style_gfx']
        self.style = 0
        # what every unit and building has become at each age (Feudal, Castle, Imperial are techs 101..103)
        E = self.rules['effects']
        self.by_age = [{}]
        for t in (101, 102, 103):
            cur = dict(self.by_age[-1])
            for e in E.get(str(self.rules['techs'][str(t)]['effect']), []):
                if e[0] == 3:
                    cur[e[1]] = e[2]
            self.by_age.append(cur)
        self.age_of = {}
        targets = {v for m in self.by_age for v in m.values()}
        for uid, u in self.U.items():
            if u['type'] == 80 and u.get('annex') and int(uid) not in targets:     # a base unit, not an upgraded one
                for k in range(4):
                    self.age_of.setdefault(self.chain(int(uid), k), k)              # the first age it is in use
        self.man = {'anims': {}, 'buildings': {}, 'units': {}, 'construction': {}, 'cons_of': {}}

    def slp(self, gid):
        g = self.G.get(str(gid))
        if g is None or ('slp', g['slp']) not in self.drs:
            return None
        if g['slp'] not in self.cache:
            self.cache[g['slp']] = decode_slp(self.drs[('slp', g['slp'])])
        return self.cache[g['slp']]

    def chain(self, uid, age):
        seen = 0
        while uid in self.by_age[age] and seen < 8:
            uid = self.by_age[age][uid]
            seen += 1
        return uid

    def gfx(self, uid):
        """The graphics of a unit or building in the current architecture style."""
        return self.style_gfx[str(self.style)].get(str(uid)) or self.U[str(uid)]['gfx']

    def expand(self, gid, dx=0, dy=0, out=None, seen=None):
        """A static graphic as pieces (layer, frame, x, y): its own picture and, recursively, every delta graphic placed by its
        offset. Nested deltas repeat pieces (a part lists its neighbours again), so a piece is kept once per place."""
        out = [] if out is None else out
        seen = set() if seen is None else seen
        g = self.G.get(str(gid))
        if g is None or (gid, dx, dy) in seen:
            return out
        seen.add((gid, dx, dy))
        fr = self.slp(gid)
        if fr:
            out.append((g['layer'], fr[0], dx, dy))
        for d in g['deltas']:
            if d['graphic_id'] >= 0:
                self.expand(d['graphic_id'], dx + d['offset_x'], dy + d['offset_y'], out, seen)
        return out

    def pieces(self, uid, dx0=0, dy0=0):
        """One building's picture, drawn by layer (ground, then shadows, then the structure), list order within a layer.
        The Town Center is made of a hall and two wings; the game keeps the finished assembly in its head unit (621, 617, 484,
        597 by age), whose delta offsets place the parts. The annexes' tile offsets give the same offsets (y = -(dx - dy) * 24)."""
        u = self.U[str(uid)]
        head = u.get('head', -1)
        age = self.age_of.get(uid)
        if u.get('annex') and head >= 0 and age is not None:
            gid = self.gfx(self.chain(head, age))['idle']
            out = self.expand(gid, dx0, dy0)
            if out:
                return sorted(out, key=lambda p: p[0])
        out = self.expand(self.gfx(uid)['idle'], dx0, dy0)
        return sorted(out, key=lambda p: p[0])

    def composite(self, gid, pc_offset=0, with_main=False):
        """A graphic without a picture of its own (a ship's) is drawn from its delta graphics: every delta contributes the
        same angle and frame, placed by its offset and hotspot. 16-angle graphics store 9 angles (the rest are mirrors); we keep
        every second one so that we have the 5 rows the game turns into 8 directions."""
        g = self.G.get(str(gid))
        if not g or not g['deltas']:
            return None
        parts = []
        if with_main:          # siege engines: the graphic's own picture is only one layer (the moving parts)
            fr = self.slp(gid)
            if fr and g['frames'] >= 1 and len(fr) >= g['frames']:
                parts.append(({'offset_x': 0, 'offset_y': 0}, g, fr))
        for d in g['deltas']:
            if d['graphic_id'] < 0:
                continue
            gd = self.G.get(str(d['graphic_id']))
            fr = self.slp(d['graphic_id'])
            if gd and fr and gd['frames'] >= 1 and len(fr) >= gd['frames']:
                parts.append((d, gd, fr))
        if not parts:
            return None
        fpa = max([g['frames']] + [p[1]['frames'] for p in parts])
        rows = 5
        out = []
        for r in range(rows):
            for k in range(fpa):
                layers = []
                for d, gd, fr in parts:
                    stored = len(fr) // gd['frames']
                    src = r * (stored - 1) // (rows - 1)
                    f = fr[src * gd['frames'] + (k % gd['frames'])]
                    layers.append((f, d['offset_x'], d['offset_y']))
                x0 = min(dx - f['hx'] for f, dx, dy in layers)
                y0 = min(dy - f['hy'] for f, dx, dy in layers)
                w = max(dx - f['hx'] + f['w'] for f, dx, dy in layers) - x0
                h = max(dy - f['hy'] + f['h'] for f, dx, dy in layers) - y0
                im = Image.new('RGBA', (max(w, 1), max(h, 1)), (0, 0, 0, 0))
                for f, dx, dy in layers:
                    im.alpha_composite(frame_image(f, self.pal, pc_offset=pc_offset), (dx - f['hx'] - x0, dy - f['hy'] - y0))
                out.append((im, -x0, -y0))
        return out, fpa, rows

    # ---------------------------------------------------------------- units
    def unit(self, uid, red):
        u = self.U[str(uid)]
        entry = {'name': u['name'], 'anims': {}, 'angles': 8}
        gfx = dict(u['gfx'])
        dead = self.U.get(str(u['dead']))
        corpse = dead['gfx']['idle'] if dead else -1
        jobs = [(a, gfx[k]) for a, k in UNIT_ANIMS.items()] + [('corpse', corpse)]
        for colour, off in (('blue', 0), ('red', RED)) if red else (('blue', 0),):
            for name, gid in jobs:
                frames = self.slp(gid)
                g = self.G.get(str(gid))
                key = f'u{uid}_{name}_{colour}'
                layered = bool(frames) and u['class'] in (13, 55) and name != 'corpse'
                if (not frames or layered) and g and g['deltas']:
                    comp = self.composite(gid, off, with_main=layered)
                    if comp:
                        info = pack_images(comp[0], comp[2], comp[1], self.out / f'{key}.png')
                        info.update(file=f'{key}.png', dur=g['speed'] if g['speed'] > 0 else 0.1, total_angles=g['angles'])
                        self.man['anims'][key] = info
                        entry['anims'].setdefault(name, key.rsplit('_', 1)[0])
                        entry['angles'] = g['angles']
                    continue
                if not frames or not g or g['frames'] < 1 or len(frames) < g['frames']:
                    continue
                stored = len(frames) // g['frames']
                frames = frames[:stored * g['frames']]      # a few SLPs carry spare frames at the end
                info = pack_animation(frames, self.pal, self.out / f'{key}.png', stored, off)
                info.update(file=f'{key}.png', dur=g['speed'] if g['speed'] > 0 else 0.1, total_angles=g['angles'])
                self.man['anims'][key] = info
                entry['anims'].setdefault(name, key.rsplit('_', 1)[0])
                entry['angles'] = g['angles']
        self.man['units'][str(uid)] = entry

    # ---------------------------------------------------------------- buildings
    def construction(self, uid):
        """The building site picture the data names for this building: three stages (stakes, frame, scaffold) of one SLP.
        Most buildings share the generic CNST1..CNST8 by size; the Dock and Fish Trap have their own. Walls and gates build
        from composite graphics and keep the game's own pieces."""
        gid = self.U[str(uid)].get('construction_gfx', -1)
        g = self.G.get(str(gid))
        fr = self.slp(gid) if g else None
        if not fr or g['frames'] != 1 or len(fr) != 3 or g['deltas']:
            return
        if str(gid) not in self.man['construction']:
            total = sum(f['w'] + 2 for f in fr)
            sheet = Image.new('RGBA', (total, max(f['h'] for f in fr) + 2), (0, 0, 0, 0))
            x, items = 0, []
            for f in fr:
                sheet.paste(frame_image(f, self.pal, shadow_idx=BUILDING_SHADOW), (x + 1, 1))
                items.append(dict(x=x + 1, y=1, w=f['w'], h=f['h'], hx=f['hx'], hy=f['hy']))
                x += f['w'] + 2
            save_png(sheet, self.out / f'cons_{gid}.png')
            self.man['construction'][str(gid)] = dict(file=f'cons_{gid}.png', items=items)
        self.man['cons_of'][str(uid)] = gid

    def uses_head(self, uid):
        u = self.U[str(uid)]
        return bool(u.get('annex')) and u.get('head', -1) >= 0 and self.age_of.get(uid) is not None

    def piece_ids(self, uid, style):
        """Every graphic a building is drawn from, to tell whether two styles differ."""
        keep, self.style = self.style, style
        ids = [(p[0], p[2], p[3], id(p[1])) for p in self.parts(uid)]
        self.style = keep
        return ids

    def parts(self, uid):
        """All pieces of a building: layer, frame, x, y. A building whose head unit holds the assembly (Town Center) needs no
        annexes added; others add the annex units at their offsets (none found to need it)."""
        pieces = self.pieces(uid)
        if not self.uses_head(uid):
            age = self.age_of.get(uid)
            for ann in self.U[str(uid)].get('annex', []):
                part = self.chain(ann[0], age or 0)
                pieces += self.pieces(part, round((ann[1] - ann[2]) * 48 * ANNEX_SCALE), round((ann[1] + ann[2]) * 24 * ANNEX_SCALE))
            pieces.sort(key=lambda p: p[0])
        return pieces

    def building(self, uid):
        u = self.U[str(uid)]
        if self.style and self.piece_ids(uid, self.style) == self.piece_ids(uid, 0):
            return                      # the same picture as the Britons' set: the game falls back to it
        key = f'bld_{self.style}_{uid}' if self.style else f'bld_{uid}'
        pieces = [(f, dx, dy) for _, f, dx, dy in self.parts(uid)]
        if not pieces:
            return
        x0 = min(dx - f['hx'] for f, dx, dy in pieces)
        y0 = min(dy - f['hy'] for f, dx, dy in pieces)
        w = max(dx - f['hx'] + f['w'] for f, dx, dy in pieces) - x0
        h = max(dy - f['hy'] + f['h'] for f, dx, dy in pieces) - y0
        img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
        for f, dx, dy in pieces:
            img.alpha_composite(frame_image(f, self.pal, shadow_idx=BUILDING_SHADOW), (dx - f['hx'] - x0, dy - f['hy'] - y0))
        save_png(img, self.out / f'{key}.png')
        self.man['buildings'][key[4:]] = dict(file=f'{key}.png', w=w, h=h, hx=-x0, hy=-y0, name=u['name'], style=self.style)


def catalog(rules, civ=1):
    """Units and buildings the civ can ever have: what is enabled, trained or built, and everything it turns into."""
    U, E, T = rules['units'], rules['effects'], rules['techs']
    tree = rules['civs'][civ]['tech_tree']
    dis_t = {int(e[4]) for e in E[str(tree)] if e[0] == 102}
    dis_u = {e[1] for e in E[str(tree)] if e[0] == 2 and e[2] == 0}
    reach = [t for t in T.values() if t['id'] not in dis_t and t['civ'] in (-1, civ) and t['effect'] >= 0]
    have = {int(k) for k, u in U.items() if u['enabled'] or (u['type'] == 80 and u['loc'] == 118)}
    for t in reach:
        for e in E.get(str(t['effect']), []):
            if e[0] == 2 and e[2] == 1:
                have.add(e[1])
    for t in reach:                      # what gets upgraded is part of the set too (the Town Center itself has no enabler)
        for e in E.get(str(t['effect']), []):
            if e[0] == 3 and str(e[1]) in U and U[str(e[1])]['type'] == 80:
                have.add(e[1])
    have -= dis_u
    changed = True
    while changed:
        changed = False
        for t in reach:
            for e in E.get(str(t['effect']), []):
                if e[0] == 3 and e[1] in have and e[2] not in have:
                    have.add(e[2])
                    changed = True
    ok = lambda i: str(i) in U and U[str(i)]['name'] and not any(s in U[str(i)]['name'] for s in SKIP_NAMES)  # noqa: E731
    units = [i for i in sorted(have) if ok(i) and U[str(i)]['type'] == 70]
    blds = [i for i in sorted(have) if ok(i) and U[str(i)]['type'] == 80]
    return units, blds


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--game', type=Path, default=Path('/home/j3rry/AOE'))
    ap.add_argument('--out', type=Path, default=Path(__file__).resolve().parent.parent / 'godot_game' / 'assets' / 'aoe')
    ap.add_argument('--only', help='comma separated unit ids (testing)')
    ap.add_argument('--civ', type=int, default=0, help='one civ only (default: all)')
    a = ap.parse_args()
    ex = Extractor(a.game, a.out)
    units, style_blds = set(), {}
    for c in ex.rules['civ_info']:
        if a.civ and c['id'] != a.civ:
            continue
        u, b = catalog(ex.rules, c['id'])
        units |= set(u)
        style_blds.setdefault(c['style'], set()).update(b)
    units = sorted(units)
    blds = sorted(style_blds.get(0, []))
    if a.only:
        want = {int(x) for x in a.only.split(',')}
        units = [i for i in units if i in want]
        blds = [i for i in blds if i in want]
    if not a.only:
        units += [i for i in EXTRA_UNITS if str(i) in ex.U]
    else:
        units += [i for i in EXTRA_UNITS if i in want and str(i) in ex.U and i not in units]
    for uid in units:
        u = ex.U[str(uid)]
        red = bool(u['atk']) and (u['class'] in ENEMY_CLASSES or uid in NAVAL_WAR)
        ex.unit(uid, red)
    for uid in sorted(set().union(*style_blds.values())):
        if not a.only or uid in set(map(int, a.only.split(','))):
            ex.construction(uid)
    for st in sorted(style_blds):
        ex.style = st
        for uid in sorted(style_blds[st]) if not a.only else [i for i in sorted(style_blds[st]) if i in set(map(int, a.only.split(',')))]:
            ex.building(uid)
    if a.only and (a.out / 'units.json').exists():          # a partial run adds to what is there instead of replacing it
        old = json.loads((a.out / 'units.json').read_text())
        for part in ('anims', 'buildings', 'units', 'construction', 'cons_of'):
            old[part].update(ex.man[part])
        ex.man = old
    (a.out / 'units.json').write_text(json.dumps(ex.man, separators=(',', ':')))
    pngs = [p for p in a.out.glob('*.png') if p.name.startswith(('u', 'bld_'))]
    print(f'{len(units)} units, {len(ex.man["buildings"])} buildings, {len(pngs)} PNGs, {sum(p.stat().st_size for p in pngs) / 1e6:.1f} MB')


if __name__ == '__main__':
    main()
