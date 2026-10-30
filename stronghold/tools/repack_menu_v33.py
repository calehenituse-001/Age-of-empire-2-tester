#!/usr/bin/env python3
"""Replace ONLY classes2.dex of a known, user-supplied Stronghold Mod v3.3 APK.

No original copyrighted game files are checked in or embedded by this tool.
Native libraries, original classes.dex, manifest, assets and other game entries
must remain byte-identical at the ZIP-entry content level.
"""
import hashlib
import pathlib
import sys
import zipfile

EXPECTED_SOURCE = "f29c2c918f9880f958f720df6844682d4824c3de16b334111abd693b3728902"
EXPECTED_NATIVE = "9baf2492b96b14b83414fb166694cb94ffd634d16a4c570ff0d242a295290bfb"

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def main(source, dex_path, out):
    source, dex_path, out = map(pathlib.Path, (source, dex_path, out))
    if sha(source.read_bytes()) != EXPECTED_SOURCE:
        raise ValueError("Input is not the exact supplied Stronghold v3.3 APK; refusing to patch unknown file")
    dex = dex_path.read_bytes()
    if not dex.startswith(b"dex\n"):
        raise ValueError("New menu classes2.dex is not DEX")
    with zipfile.ZipFile(source) as base:
        entries = set(base.namelist())
        required = {"classes.dex", "classes2.dex", "AndroidManifest.xml", "lib/arm64-v8a/libstronghold.so",
                    "lib/arm64-v8a/libstronghold_mod_runtime.so"}
        if required - entries:
            raise ValueError("Missing required v3.3 components: " + repr(required - entries))
        if sha(base.read("lib/arm64-v8a/libstronghold.so")) != EXPECTED_NATIVE:
            raise ValueError("Unexpected Extreme native binary")
        out.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(out, "w", allowZip64=True) as target:
            for info in base.infolist():
                if info.filename.upper().startswith("META-INF/"):
                    continue  # v3.3 signatures must not survive a changed DEX
                data = dex if info.filename == "classes2.dex" else base.read(info)
                target.writestr(info, data, compress_type=info.compress_type, compresslevel=6)
    with zipfile.ZipFile(source) as base, zipfile.ZipFile(out) as target:
        if target.testzip() is not None:
            raise ValueError("Repacked APK ZIP CRC error")
        for entry in base.namelist():
            if entry.upper().startswith("META-INF/") or entry == "classes2.dex":
                continue
            if sha(base.read(entry)) != sha(target.read(entry)):
                raise ValueError("Unexpected change to original APK entry " + entry)
        if target.read("classes2.dex") != dex:
            raise ValueError("New DEX not correctly packed")
    print("Repacked Stronghold v3.3 with updated Java MOD menu; native and other APK entries unchanged.")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("Usage: repack_menu_v33.py supplied-v3.3.apk new-classes2.dex unsigned.apk")
    main(*sys.argv[1:])
