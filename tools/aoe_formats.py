"""Readers for the Genie-engine file formats used by Age of Empires II (HD): DRS archives, SLP v2.0N sprites, JASC palettes.
Everything here only reads; nothing writes to the game folder."""
import struct
from pathlib import Path

from PIL import Image


def read_drs(path):
    d = Path(path).read_bytes()
    ntab, _first = struct.unpack_from('<II', d, 0x38)
    files = {}
    for t in range(ntab):
        off = 0x40 + t * 12
        ext = d[off:off + 4][::-1].decode('latin1').strip()
        toff, nfiles = struct.unpack_from('<II', d, off + 4)
        for i in range(nfiles):
            fid, foff, fsz = struct.unpack_from('<III', d, toff + i * 12)
            files[(ext, fid)] = d[foff:foff + fsz]
    return files


def read_pal(text):
    parts = text.split()
    n = int(parts[2])
    vals = list(map(int, parts[3:3 + n * 3]))
    return [tuple(vals[i * 3:i * 3 + 3]) for i in range(n)]


def decode_slp(b):
    """Return frames: dict(w, h, hx, hy, px) where px[y][x] is -1 (clear), 0-255 palette index,
    256+i player-colour index, 512 shadow, 513 outline."""
    nframes = struct.unpack_from('<i', b, 4)[0]
    frames = []
    for f in range(nframes):
        cmd_off, out_off, _pal, _props, w, h, hx, hy = struct.unpack_from('<IIIIiiii', b, 0x20 + f * 32)
        px = [[-1] * w for _ in range(h)]
        for y in range(h):
            left, right = struct.unpack_from('<HH', b, out_off + y * 4)
            if left == 0x8000 or right == 0x8000:
                continue
            x = left
            p = struct.unpack_from('<I', b, cmd_off + y * 4)[0]
            while True:
                c = b[p]; p += 1
                if c == 0x0F:
                    break
                lo = c & 3
                if lo == 0:                               # colour list
                    for _ in range(c >> 2):
                        px[y][x] = b[p]; p += 1; x += 1
                elif lo == 1:                             # skip
                    n = c >> 2
                    if n == 0:
                        n = b[p]; p += 1
                    x += n
                elif c & 0x0F == 2:                       # big colour list
                    n = ((c & 0xF0) << 4) + b[p]; p += 1
                    for _ in range(n):
                        px[y][x] = b[p]; p += 1; x += 1
                elif c & 0x0F == 3:                       # big skip
                    x += ((c & 0xF0) << 4) + b[p]; p += 1
                else:
                    cmd = c & 0x0F
                    n = c >> 4
                    if cmd in (6, 7, 10, 11) and n == 0:
                        n = b[p]; p += 1
                    if cmd == 6:                          # player colour list
                        for _ in range(n):
                            px[y][x] = 256 + b[p]; p += 1; x += 1
                    elif cmd == 7:                        # fill
                        col = b[p]; p += 1
                        for _ in range(n):
                            px[y][x] = col; x += 1
                    elif cmd == 10:                       # player colour fill
                        col = b[p]; p += 1
                        for _ in range(n):
                            px[y][x] = 256 + col; x += 1
                    elif cmd == 11:                       # shadow
                        for _ in range(n):
                            px[y][x] = 512; x += 1
                    elif cmd == 14:                       # extended commands
                        ext = c >> 4
                        if ext in (4, 6):                 # single outline pixel
                            px[y][x] = 513; x += 1
                        elif ext in (5, 7):               # outline run
                            n = b[p]; p += 1
                            for _ in range(n):
                                px[y][x] = 513; x += 1
                    else:
                        raise ValueError('unknown SLP command %#x' % c)
        frames.append(dict(w=w, h=h, hx=hx, hy=hy, px=px))
    return frames


def frame_image(fr, pal, shadow_idx=(), pc_offset=0):
    im = Image.new('RGBA', (fr['w'], fr['h']), (0, 0, 0, 0))
    put = im.load()
    for y, row in enumerate(fr['px']):
        for x, v in enumerate(row):
            if v == -1 or v == 513:
                continue
            if v == 512 or v in shadow_idx:           # shadow command, or the near-black index buildings use for shadows
                put[x, y] = (0, 0, 0, 90)
                continue
            idx = (v & 0xFF) + (pc_offset if v >= 256 else 0)
            r, g, b = pal[idx]
            put[x, y] = (r, g, b, 255)
    return im


