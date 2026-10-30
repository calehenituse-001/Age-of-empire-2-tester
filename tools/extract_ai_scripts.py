"""Writes the original computer player's scripts out of the user's own AoE2 HD install, for reading.

The AI is a rule base ("defrule ... =>") in text resources of type 'bina', ids 60001..60029, inside Data/gamedata.drs (base game)
and Data/gamedata_x1.drs (Conquerors; this is the one the HD edition plays). Random map scripts (54xxx) and the map-type
tables sit beside them. Output is plain text for reading only; nothing in the game depends on it.

    python3 -I tools/extract_ai_scripts.py --game /path/to/AoE2HD --out some/new/folder
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from aoe_formats import read_drs  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--game', type=Path, default=Path('/home/j3rry/AOE'))
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--random-maps', action='store_true', help='also write the 54xxx/55xxx random map scripts')
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    n = 0
    for name, tag in (('gamedata.drs', 'base'), ('gamedata_x1.drs', 'x1')):
        for (kind, rid), data in sorted(read_drs(a.game / 'Data' / name).items()):
            if kind == 'bina' and (60000 <= rid < 60100 or (a.random_maps and 54000 <= rid < 56000)):
                (a.out / f'{tag}_{rid}.txt').write_bytes(bytes(data))
                n += 1
    print(f'{n} script files in {a.out}')


if __name__ == '__main__':
    main()
