#!/usr/bin/env python3
"""Adds only the move and target markers to an existing godot_game/assets/aoe (writes two PNGs and patches manifest.json).
Usage: python3 -I tools/extract_markers.py [GAME_DIR] [OUT_DIR]   (the same arguments as extract_aoe_godot.py)"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_aoe_godot as E  # noqa: E402
from aoe_formats import read_drs, read_pal  # noqa: E402

data = E.GAME / 'Data'
graphics = read_drs(data / 'graphics.drs')
interfac = read_drs(data / 'interfac.drs')
pal = read_pal(interfac[('bina', 50500)].decode('latin1'))
man_path = E.OUT / 'manifest.json'
man = json.loads(man_path.read_text())
man['markers'] = E.extract_markers(graphics, interfac, pal)
man_path.write_text(json.dumps(man, separators=(',', ':')))
print('markers:', {k: (v['file'], len(v['items'])) for k, v in man['markers'].items()})
