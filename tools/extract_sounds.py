#!/usr/bin/env python3
"""Re-writes only the sound effects (godot_game/assets/aoe/snd) from the install, without redoing the sprites.
Usage: python3 -I tools/extract_sounds.py [GAME_DIR] [OUT_DIR]   (the same arguments as extract_aoe_godot.py)"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import extract_aoe_godot as E  # noqa: E402

print('wrote', E.extract_sounds(E.GAME, E.OUT), 'sounds')
