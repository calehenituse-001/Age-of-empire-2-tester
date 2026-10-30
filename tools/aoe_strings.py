"""Reads the text strings (unit, building and tech names, descriptions) out of AoE2 HD's language*.dll files.

The DLLs only hold a Windows RT_STRING resource: blocks of 16 UTF-16 strings, block n holds string ids
(n-1)*16 .. (n-1)*16+15, each string is a 16-bit length followed by that many UTF-16 characters.
"""
import struct
from pathlib import Path


def _rva_to_off(secs, rva):
    for va, vsz, raw, rsz in secs:
        if va <= rva < va + max(vsz, rsz):
            return rva - va + raw
    raise ValueError("rva outside sections")


def read_strings(path):
    d = Path(path).read_bytes()
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    nsec, = struct.unpack_from("<H", d, pe + 6)
    optsz, = struct.unpack_from("<H", d, pe + 20)
    opt = pe + 24
    magic, = struct.unpack_from("<H", d, opt)
    dd = opt + (96 if magic == 0x10B else 112)
    res_rva, _ = struct.unpack_from("<II", d, dd + 2 * 8)
    secs = []
    for i in range(nsec):
        o = opt + optsz + i * 40
        vsz, va, rsz, raw = struct.unpack_from("<IIII", d, o + 8)
        secs.append((va, vsz, raw, rsz))
    base = _rva_to_off(secs, res_rva)

    def entries(off):
        named, ided = struct.unpack_from("<HH", d, off + 12)
        out = []
        for i in range(named + ided):
            nid, tgt = struct.unpack_from("<II", d, off + 16 + i * 8)
            out.append((nid, tgt))
        return out

    strings = {}
    for tid, tgt in entries(base):
        if tid != 6 or not tgt & 0x80000000:
            continue
        for bid, t2 in entries(base + (tgt & 0x7FFFFFFF)):
            if not t2 & 0x80000000:
                continue
            for _, t3 in entries(base + (t2 & 0x7FFFFFFF)):
                de = base + t3
                rva, size = struct.unpack_from("<II", d, de)
                p = _rva_to_off(secs, rva)
                for k in range(16):
                    n, = struct.unpack_from("<H", d, p)
                    p += 2
                    if n:
                        strings[(bid - 1) * 16 + k] = d[p:p + n * 2].decode("utf-16-le", "replace")
                    p += n * 2
    return strings


def read_all(game):
    out = {}
    for f in ("language.dll", "language_x1.dll", "language_x1_p1.dll"):
        p = Path(game) / "Bin" / "en" / f
        if p.exists():
            out.update(read_strings(p))
    return out
