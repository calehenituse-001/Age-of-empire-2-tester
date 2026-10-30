#!/usr/bin/env python3
"""Writes godot_game/data/dat_schema.json: the layout of AoE2 HD's empires2_x1_p1.dat (which fields follow each other, their
types and how arrays and sub-structures are counted), generated from the structure definitions of openage
(https://github.com/SFTtech/openage, GPLv3). The Godot game's own reader (scripts/importer/dat_reader.gd) interprets this file
on the device. The schema holds no game data.

    python3 -I tools/make_dat_schema.py --openage /path/to/openage/src --out godot_game/data/dat_schema.json
"""
import argparse, functools, json, sys
from pathlib import Path

SIZES = {"char": 1, "int8_t": 1, "uint8_t": 1, "int16_t": 2, "uint16_t": 2, "int32_t": 4, "uint32_t": 4, "float": 4, "int": 4, "unsigned int": 4,
         "short": 2, "unsigned short": 2}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--openage", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    a = ap.parse_args()
    sys.path.insert(0, str(a.openage))
    sys.setrecursionlimit(10000)
    from openage.convert.value_object.read.media.datfile.empiresdat import EmpiresDat
    from openage.convert.value_object.read.media.datfile import unit as unit_mod
    from openage.convert.value_object.read.member_access import READ, READ_GEN, READ_UNKNOWN, SKIP
    from openage.convert.value_object.read.read_members import (ContinueReadMember, EnumLookupMember, IncludeMembers, GroupMember,
                                                                MultisubtypeMember, SubdataMember)
    from openage.convert.value_object.read.value_members import StorageType

    def keep(cls, names):                       # the same patch import_dat.py applies: keep the building annexes
        orig = cls.get_data_format_members.__func__.__wrapped__

        def patched(klass, version):
            return [(READ_GEN,) + tuple(m[1:]) if m[0] is SKIP and m[1] in names else m for m in orig(klass, version)]
        cls.get_data_format_members = classmethod(functools.cache(patched))
    keep(unit_mod.BuildingAnnex, ("unit_id", "misplaced0", "misplaced1"))
    keep(unit_mod.BuildingUnit, ("building_annex",))

    class Edition:
        game_id = "HDEDITION"

    class Version:
        edition = Edition()
        expansions = ()

    ACC = {SKIP: 0, READ: 1, READ_GEN: 2, READ_UNKNOWN: 1}
    ST = {StorageType.INT_MEMBER: "i", StorageType.ID_MEMBER: "i", StorageType.BITFIELD_MEMBER: "i", StorageType.FLOAT_MEMBER: "f",
          StorageType.BOOLEAN_MEMBER: "b", StorageType.STRING_MEMBER: "s", StorageType.ARRAY_INT: "ai", StorageType.ARRAY_ID: "ai",
          StorageType.ARRAY_FLOAT: "af", StorageType.ARRAY_BOOL: "ab", StorageType.ARRAY_STRING: "as",
          StorageType.ARRAY_CONTAINER: "ac", StorageType.CONTAINER_MEMBER: "c"}
    classes = {}

    def length(v):
        if callable(v):
            # the only one the HD file uses: graphic attack sounds exist for every angle when the flag is set
            return {"if": ["attack_sound_used", "angle_count"]}
        return v

    def walk(cls):
        name = cls.__name__
        if name in classes:
            return name
        classes[name] = []
        ops = []
        for acc, var, st, vt in cls.get_data_format_members(Version()):
            a_ = ACC[acc]
            if isinstance(vt, IncludeMembers):
                ops.append({"k": "inc", "c": walk(vt.cls), "a": a_})
            elif isinstance(vt, GroupMember):
                ops.append({"k": "grp", "n": var, "c": walk(vt.cls), "a": a_, "st": ST[st]})
            elif isinstance(vt, SubdataMember):
                sub = vt.class_lookup[None]
                op = {"k": "sub", "n": var, "c": walk(sub), "a": a_, "len": length(vt.length)}
                if vt.passed_args:
                    op["pass"] = [vt.passed_args] if isinstance(vt.passed_args, str) else sorted(vt.passed_args)
                if vt.offset_to:
                    assert vt.offset_to[1](1) and not vt.offset_to[1](0)
                    op["off"] = vt.offset_to[0]
                ops.append(op)
            elif isinstance(vt, MultisubtypeMember):
                sd = vt.subtype_definition
                lk = {str(k): walk(c) for k, c in vt.class_lookup.items()}
                inv = {v: k for k, v in sd[3].lookup_dict.items()}       # class name (enum string) -> raw number
                op = {"k": "multi", "n": var, "a": a_, "len": length(vt.length), "sub": {"a": ACC[sd[0]], "n": sd[1], "t": sd[3].raw_type},
                      "cls": {str(inv[k]): c for k, c in lk.items()}}
                if vt.passed_args:
                    op["pass"] = [vt.passed_args] if isinstance(vt.passed_args, str) else sorted(vt.passed_args)
                if vt.offset_to:
                    assert vt.offset_to[1](1) and not vt.offset_to[1](0)
                    op["off"] = vt.offset_to[0]
                ops.append(op)
            else:
                op = {"k": "p", "a": a_, "n": var, "st": ST.get(st, "?")}
                if isinstance(vt, str):
                    t = vt
                    cnt = None
                    if "[" in t:
                        t, c = t.split("[")
                        c = c.rstrip("]; ")
                        cnt = int(c) if c.isdigit() else c
                    op["t"] = t
                    if cnt is not None:
                        op["c"] = cnt
                        if t == "char":
                            op["str"] = True
                elif isinstance(vt, ContinueReadMember):
                    op["t"] = vt.raw_type
                    op["abort0"] = True
                elif isinstance(vt, EnumLookupMember):
                    op["t"] = vt.raw_type
                    if st is StorageType.STRING_MEMBER:
                        op["lk"] = {str(k): v for k, v in vt.lookup_dict.items()}
                elif type(vt).__name__ in ("ArrayMember", "CharArrayMember"):
                    op["t"] = "char" if vt.raw_type == "char[]" else vt.raw_type
                    op["c"] = length(vt.length)
                    if vt.raw_type == "char[]":
                        op["str"] = True
                else:
                    raise SystemExit(f"{name}.{var}: unhandled member type {vt!r}")
                ops.append(op)
        classes[name] = ops
        return name

    root = walk(EmpiresDat)
    # fuse neighbouring fixed-size members that are skipped into one jump (a long run of unused fields costs one step)
    for name, ops in classes.items():
        out = []
        for op in ops:
            if op["k"] == "p" and op["a"] == 0 and isinstance(op.get("c", 1), int) and op["t"] in SIZES:
                n = SIZES[op["t"]] * op.get("c", 1)
                if out and out[-1]["k"] == "skip":
                    out[-1]["n"] += n
                else:
                    out.append({"k": "skip", "n": n})
            else:
                out.append(op)
        classes[name] = out
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps({"root": root, "classes": classes}, separators=(",", ":")))
    print(f"{len(classes)} structures, {sum(len(v) for v in classes.values())} steps -> {a.out}")


if __name__ == "__main__":
    main()
