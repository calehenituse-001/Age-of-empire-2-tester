#!/usr/bin/env python3
"""Audit the menu bootstrap in a *built Stronghold APK*, without Android SDK.

Usage: python3 tools/verify_menu_apk.py path/to/signed-Stronghold.apk
Exit 0 only when the provider, secondary DEX, and native mod libraries exist.
This is a PACKAGE test, not proof the bubble renders or gameplay cheats work.
"""
import pathlib
import struct
import sys
import zipfile

PROVIDER = "org.stronghold.port.mod.ModInitProvider"
ACTIVITY = ".ExtremeGameActivity"


def chunk(blob, position):
    kind, header, size = struct.unpack_from("<HHI", blob, position)
    if header < 8 or size < header or position + size > len(blob):
        raise ValueError("Invalid AXML chunk")
    return kind, header, size


def string_pool(blob, position):
    kind, header, size = chunk(blob, position)
    if kind != 1 or header != 28:
        raise ValueError("Expected Android UTF-16 string pool")
    count, styles, flags, start, _ = struct.unpack_from("<IIIII", blob, position + 8)
    if styles or (flags & 0x100):
        raise ValueError("Unexpected string-pool encoding")
    names = []
    for i in range(count):
        offset = struct.unpack_from("<I", blob, position + 28 + i * 4)[0]
        p = position + start + offset
        length = struct.unpack_from("<H", blob, p)[0]
        names.append(blob[p + 2:p + 2 + 2 * length].decode("utf-16-le"))
    return names


def manifest_components(blob):
    if struct.unpack_from("<HHI", blob, 0) != (3, 8, len(blob)):
        raise ValueError("Invalid binary manifest")
    names = string_pool(blob, 8)
    position = 8
    result = []
    while position < len(blob):
        kind, header, size = chunk(blob, position)
        if kind == 0x102:  # RES_XML_START_ELEMENT_TYPE
            name_idx = struct.unpack_from("<I", blob, position + 20)[0]
            if name_idx >= len(names):
                raise ValueError("Unknown element name")
            element = names[name_idx]
            if element in ("provider", "activity"):
                attr_count = struct.unpack_from("<H", blob, position + 28)[0]
                attrs = {}
                for i in range(attr_count):
                    # XML node header=16; attrExt header=20; attr=20 bytes
                    ns, key, raw, value_size, reserved, data_type, value = struct.unpack_from(
                        "<IIIHBBI", blob, position + 36 + i * 20
                    )
                    if key >= len(names):
                        raise ValueError("Bad attribute name")
                    if data_type == 3:
                        decoded = names[value]
                    elif data_type == 0x12:
                        decoded = bool(value)
                    elif raw != 0xffffffff and raw < len(names):
                        decoded = names[raw]
                    else:
                        decoded = value
                    attrs[names[key]] = decoded
                result.append((element, attrs))
        position += size
    return result


def inspect(apk_path):
    with zipfile.ZipFile(apk_path) as archive:
        paths = set(archive.namelist())
        required = {
            "AndroidManifest.xml",
            "classes.dex",
            "classes2.dex",
            "lib/arm64-v8a/libstronghold.so",
            "lib/arm64-v8a/libstronghold_mod_runtime.so",
        }
        missing = sorted(required - paths)
        if missing:
            raise ValueError("Mod Menu files missing from APK: " + ", ".join(missing))
        components = manifest_components(archive.read("AndroidManifest.xml"))
        providers = [v for k, v in components if k == "provider" and v.get("name") == PROVIDER]
        if len(providers) != 1:
            raise ValueError("Expected one ModInitProvider, got " + str(len(providers)))
        p = providers[0]
        if p.get("process") != ":extreme" or p.get("exported") is not False:
            raise ValueError("Provider has incorrect process or exported flag: " + repr(p))
        if not any(k == "activity" and v.get("name") in (ACTIVITY, "org.stronghold.port.ExtremeGameActivity")
                   and v.get("process") == ":extreme" for k, v in components):
            raise ValueError("ExtremeGameActivity is not declared in :extreme process")
        dex = archive.read("classes2.dex")
        for needle in (b"ModInitProvider", b"StrongholdModOverlay", b"StrongholdNativeBridge"):
            if needle not in dex:
                raise ValueError("Secondary DEX lacks " + needle.decode())
        lib = archive.read("lib/arm64-v8a/libstronghold.so")
        if b"SHMOD033" not in lib:
            raise ValueError("Extreme library lacks expected v3.3 native signature")
        bridge = archive.read("lib/arm64-v8a/libstronghold_mod_runtime.so")
        if not bridge.startswith(b"\x7fELF"):
            raise ValueError("Invalid native JNI bridge")
        print("PASS: provider in :extreme, activity, classes2.dex, patched native + JNI present.")
        print("LIMIT: real Android overlay visibility and gameplay still require device tests.")


if __name__ == "__main__":
    try:
        inspect(pathlib.Path(sys.argv[1]))
    except (IndexError, OSError, ValueError, zipfile.BadZipFile, struct.error) as exc:
        sys.exit("FAIL: " + str(exc))
