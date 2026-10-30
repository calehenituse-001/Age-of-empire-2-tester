#!/usr/bin/env python3
"""Repair exactly the two malformed ELF offsets in the Asfatre v1.3 mod library.

The original (user-supplied) APK must not be committed to GitHub. This helper
accepts a standalone extracted library and writes a corrected library. It
fails for unexpected or previously fixed binaries.

Usage:
    python3 asfatre_v13/repair_v13_elf_headers.py bad-libstronghold.so good-libstronghold.so

APK signing/packaging and Android runtime tests are separate steps.
"""
import hashlib
import pathlib
import struct
import sys

BROKEN_SHA = "9a117e5b7a9115a38fe36fb339b16851cf82dc49bd119d7ffbf6aa2f2495d8ac"
FIXED_SHA = "3cd2def5241b2fc7e6f8aba8e2bfe5af999bfe67a5ee7e53e8ae4ba16720dfed"
EXPECTED = {
    5: (2, 0x307e9b0, 0x30829b0),       # PT_DYNAMIC
    6: (0x6474e552, 0x3044090, 0x3048090), # PT_GNU_RELRO
}


def program_headers(blob):
    if blob[:6] != b"\x7fELF\x02\x01":
        raise ValueError("Expected ELF64 AArch64 little-endian")
    if struct.unpack_from("<H", blob, 18)[0] != 183:
        raise ValueError("Expected EM_AARCH64")
    phoff = struct.unpack_from("<Q", blob, 32)[0]
    size, count = struct.unpack_from("<HH", blob, 54)
    if phoff + count * size > len(blob):
        raise ValueError("Program header table out of bounds")
    result = []
    for i in range(count):
        pos = phoff + i * size
        typ, flags = struct.unpack_from("<II", blob, pos)
        offset, va, pa, filesz, memsz, alignment = struct.unpack_from("<QQQQQQ", blob, pos + 8)
        result.append((i, pos, typ, offset, va, filesz, memsz))
    return result


def check_mappings(blob):
    headers = program_headers(blob)
    loads = [p for p in headers if p[2] == 1]
    for p in headers:
        i, at, typ, offset, va, filesz, memsz = p
        if typ not in (1, 2, 0x6474e552) or not filesz:
            continue
        if not any(l[4] <= va and va + filesz <= l[4] + l[5]
                   and l[3] + (va - l[4]) == offset for l in loads):
            raise ValueError("Invalid ELF file mapping for program header %d (%#x)" % (i, typ))
    return True


def repair(bad):
    if hashlib.sha256(bad).hexdigest() != BROKEN_SHA:
        raise ValueError("Refusing to patch unknown libstronghold.so version")
    out = bytearray(bad)
    headers = program_headers(out)
    if len(headers) != 10:
        raise ValueError("Unexpected program header count")
    for i, (typ, old, new) in EXPECTED.items():
        header = headers[i]
        if header[2] != typ or header[3] != old:
            raise ValueError("Unexpected program header %d" % i)
        struct.pack_into("<Q", out, header[1] + 8, new)
    check_mappings(out)
    if hashlib.sha256(out).hexdigest() != FIXED_SHA:
        raise ValueError("Corrected library hash mismatch")
    return out


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    source, dest = map(pathlib.Path, sys.argv[1:])
    dest.write_bytes(repair(source.read_bytes()))
    print("Fixed ELF PT_DYNAMIC and PT_GNU_RELRO; SHA256:", FIXED_SHA)
