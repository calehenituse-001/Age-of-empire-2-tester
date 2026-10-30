#!/usr/bin/env python3
"""Imports the game rules from an Age of Empires II HD install: units, buildings, techs, effects, tech tree,
terrains and graphics, plus the English names. Writes JSON that the Godot game reads; nothing from the game
is shipped with this repository.

    python3 -I tools/import_dat.py --game /path/to/AoE2HD --openage /path/to/openage/src --out godot_game/assets/aoe/data

The .dat file is parsed with openage's reader (GPLv3, https://github.com/SFTtech/openage), which is only needed
while importing. See docs/FORMATS.md.
"""
import argparse, json, sys, time, zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import aoe_strings

CIV_NAMES = ["Gaia", "Britons", "Franks", "Goths", "Teutons", "Japanese", "Chinese", "Byzantines", "Persians",
             "Saracens", "Turks", "Vikings", "Mongols", "Celts", "Spanish", "Aztecs", "Mayans", "Huns", "Koreans"]
AGE_TECHS = {"feudal": 101, "castle": 102, "imperial": 103}


def read_dat(game: Path, openage: Path):
    sys.path.insert(0, str(openage))
    sys.setrecursionlimit(10000)
    from openage.convert.value_object.read.media.datfile.empiresdat import EmpiresDatWrapper
    from openage.convert.value_object.read.value_members import ArrayMember, ContainerMember

    # openage skips the building annexes (the Town Center's wings and hall are separate units placed around the
    # main one); make the reader keep them
    import functools
    from openage.convert.value_object.read.media.datfile import unit as unit_mod
    from openage.convert.value_object.read.member_access import READ_GEN, SKIP

    def keep(cls, names):
        orig = cls.get_data_format_members.__func__.__wrapped__

        def patched(klass, version):
            return [(READ_GEN,) + tuple(m[1:]) if m[0] is SKIP and m[1] in names else m for m in orig(klass, version)]
        cls.get_data_format_members = classmethod(functools.cache(patched))

    keep(unit_mod.BuildingAnnex, ("unit_id", "misplaced0", "misplaced1"))
    keep(unit_mod.BuildingUnit, ("building_annex",))

    class Edition:
        game_id = "HDEDITION"

    class Version:                      # the reader only looks at the edition and caches by this object
        edition = Edition()
        expansions = ()

    raw = zlib.decompress((game / "Data" / "empires2_x1_p1.dat").read_bytes(), -15)
    end, gs = EmpiresDatWrapper().read(raw, 0, Version())
    if end != len(raw):
        raise SystemExit(f"dat parse stopped at {end} of {len(raw)} bytes: unknown format")
    gs = gs[0]
    if isinstance(gs, ArrayMember) and len(gs.value) == 1:
        gs = gs.value[0]

    def conv(m):
        v = m.value
        if isinstance(m, ContainerMember):
            return {k: conv(x) for k, x in v.items()}
        if isinstance(m, ArrayMember):
            return [conv(x) for x in v]
        return v.decode("latin1") if isinstance(v, bytes) else v

    return conv(gs)


UNIT_DEFAULTS = {
    "resource_cost": [], "attacks": [], "armors": [], "resource_storage": [], "drop_sites": [], "damage_graphics": [],
    "weapon_range_max": 0.0, "weapon_range_min": 0.0, "attack_speed": 0.0, "accuracy": 0, "projectile_id0": -1,
    "creation_time": 0, "train_location_id": -1, "creatable_type": 0, "work_rate": 0.0, "resource_capacity": 0,
    "attack_sprite_id": -1, "move_graphics": -1, "speed": 0.0, "train_sound_id": -1, "selection_sound_id": -1,
    "dying_sound_id": -1, "command_sound_id": -1, "damage_sound_id": -1, "garrison_graphic": -1,
    "projectile_min_count": 0, "projectile_max_count": 0, "dead_unit_id": -1, "garrison_capacity": 0,
    "idle_graphic0": -1, "dying_graphic": -1, "enabled": False, "language_dll_name": -1, "unit_class": -1,
    "hit_points": 0, "line_of_sight": 0.0, "research_id": -1, "construction_graphic_id": -1, "stack_unit_id": -1,
    "foundation_terrain_id": -1, "head_unit_id": -1, "transform_unit_id": -1, "terrain_restriction": -1,
    "search_radius": 0.0, "trait": 0, "blast_range": 0.0, "blast_level_offence": 0,
}


def unit_row(u, header, S):
    u = UNIT_DEFAULTS | u
    cost = [[c["type_id"], c["amount"]] for c in u["resource_cost"] if c["enabled"] and c["amount"]]
    row = {
        "id": u["id0"], "name": S.get(u["language_dll_name"], ""), "type": u["unit_type"], "class": u["unit_class"],
        "hp": u["hit_points"], "los": u["line_of_sight"], "speed": round(u["speed"], 4),
        "radius": [round(u["radius_x"], 3), round(u["radius_y"], 3)],
        "atk": [[a["type_id"], a["amount"]] for a in u["attacks"]],
        "arm": [[a["type_id"], a["amount"]] for a in u["armors"]],
        "range": round(u["weapon_range_max"], 3), "min_range": round(u["weapon_range_min"], 3),
        "reload": round(u["attack_speed"], 3), "accuracy": u["accuracy"], "projectile": u["projectile_id0"],
        "cost": cost, "time": u["creation_time"], "loc": u["train_location_id"], "creatable": u["creatable_type"],
        "enabled": u["enabled"], "work_rate": round(u["work_rate"], 4), "capacity": u["resource_capacity"],
        "gfx": {"idle": u["idle_graphic0"], "die": u["dying_graphic"], "move": u["move_graphics"],
                "attack": u["attack_sprite_id"], "garrison": u["garrison_graphic"]},
        "dead": u["dead_unit_id"], "garrison": u["garrison_capacity"], "sound": {
            "train": u["train_sound_id"], "select": u["selection_sound_id"], "die": u["dying_sound_id"],
            "command": u["command_sound_id"], "damage": u["damage_sound_id"]},
        "resource_storage": [[r["type"], r["amount"]] for r in u["resource_storage"] if r["type"] >= 0],
        "drop_sites": [d for d in u["drop_sites"] if d >= 0],
        "projectiles": [u["projectile_min_count"], u["projectile_max_count"]],
        "blast": round(u.get("blast_range", 0.0), 3), "blast_level": u.get("blast_level_offence", 0),
        "min_range": round(u["weapon_range_min"], 3),
        "damage_gfx": u.get("damage_graphics", []),
    }
    cmds = [{k: c[k] for k in ("type", "class_id", "unit_id", "resource_in", "resource_multiplier", "resource_out",
                               "work_value1", "work_value2")}
            for c in header.get("unit_commands", []) if c["type"] != 7 or c["unit_id"] != -1]
    if cmds:
        row["cmds"] = cmds
    if u["unit_type"] == 80:
        # research_id: marker tech that counts as researched once this building stands (feeds the age requirement)
        row["research_id"] = u["research_id"]
        row["construction_gfx"] = u["construction_graphic_id"]
        row["stack"] = u["stack_unit_id"]
        row["head"] = u["head_unit_id"]
        row["foundation_terrain"] = u["foundation_terrain_id"]
        row["pop"] = sum(r["amount"] for r in u["resource_storage"] if r["type"] == 4)
        row["size"] = [round(u["clearance_size_x"], 2), round(u["clearance_size_y"], 2)]
        row["annex"] = [[a["unit_id"], round(a["misplaced0"], 3), round(a["misplaced1"], 3)] for a in u.get("building_annex", []) if a["unit_id"] > 0]
    row["terrain_restriction"] = u["terrain_restriction"]
    row["search_radius"] = u["search_radius"]
    return row


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--game", required=True, type=Path)
    ap.add_argument("--openage", required=True, type=Path, help="openage's src directory")
    ap.add_argument("--out", required=True, type=Path)
    a = ap.parse_args()
    t = time.time()
    d = read_dat(a.game, a.openage)
    S = aoe_strings.read_all(a.game)
    print(f"dat read in {time.time() - t:.1f}s, {len(S)} strings")

    civ = d["civs"][1]
    heads = d["unit_headers"]
    units = {}
    for u in civ["units"]:
        i = u["id0"]
        units[i] = unit_row(u, heads[i] if i < len(heads) else {}, S)

    for u in d["civs"][0]["units"]:       # Gaia's own units: fish, animals, trees, mines (not in any player's list)
        i = u["id0"]
        if i not in units:
            units[i] = unit_row(u, heads[i] if i < len(heads) else {}, S)
            units[i]["gaia"] = True

    # architecture sets: civs whose Feudal-and-later buildings share their graphics look the same
    sig_of = {}
    style_of = {}
    for ci in range(1, len(d["civs"])):
        byid = {u["id0"]: u for u in d["civs"][ci]["units"]}
        sig = tuple(byid[i]["idle_graphic0"] for i in (463, 498, 71, 141, 142, 87, 103, 84, 104, 82, 45))
        style_of[ci] = sig_of.setdefault(sig, len(sig_of))
    style_gfx = {}                      # style -> {building unit id: its gfx dict}; style 0 is the Britons' set (= units above)
    for ci in range(1, len(d["civs"])):
        st = style_of[ci]
        if st in style_gfx:
            continue
        style_gfx[st] = {}
        for u in d["civs"][ci]["units"]:
            if u["unit_type"] == 80:
                row = unit_row(u, {}, S)
                style_gfx[st][u["id0"]] = row["gfx"] | {"construction": u.get("construction_graphic_id", -1)}
    civ_info = []
    for ci in range(1, len(d["civs"])):
        text = S.get(20149 + ci, "").replace("<b>", "").replace("<br>", "\n")
        civ_info.append({"id": ci, "name": S.get(10230 + ci, CIV_NAMES[ci]), "style": style_of[ci],
                         "tech_tree": d["civs"][ci]["tech_tree_id"], "text": text})

    techs = {}
    for i, r in enumerate(d["researches"]):
        if r["research_location_id"] < 0 and not any(c["amount"] for c in r["research_resource_costs"]) and r["tech_effect_id"] < 0:
            continue
        techs[i] = {
            "id": i, "name": S.get(r["language_dll_name"], ""), "desc": S.get(r["language_dll_description"], ""),
            "cost": [[c["type_id"], c["amount"]] for c in r["research_resource_costs"] if c["enabled"] and c["amount"]],
            "time": r["research_time"], "loc": r["research_location_id"], "effect": r["tech_effect_id"],
            "req": [x for x in r["required_techs"] if x >= 0], "req_count": r["required_tech_count"],
            "civ": r["civilization_id"], "button": r["button_id"], "type": r["tech_type"],
        }
    effects = {i: [[e["type_id"], e["attr_a"], e["attr_b"], e["attr_c"], e["attr_d"]] for e in b["effects"] if e["type_id"] != 255]
               for i, b in enumerate(d["effect_bundles"]) if any(e["type_id"] != 255 for e in b["effects"])}

    terrains = [{k: t_[k] for k in ("internal_name", "filename", "slp_id", "blend_priority", "blend_mode", "map_color_hi",
                                    "map_color_med", "map_color_low", "sound_id", "is_animated", "animation_frame_count")}
                | {"id": i} for i, t_ in enumerate(d["terrains"])]
    tree = {
        "buildings": d["building_connections"], "units": d["unit_connections"], "techs": d["tech_connections"],
        "ages": d["age_connections"],
    }
    rules = {
        "source": "AoE2 HD dat " + d["versionstr"], "age_techs": AGE_TECHS,
        "civs": [{"id": i, "name": CIV_NAMES[i] if i < len(CIV_NAMES) else str(i), "tech_tree": c["tech_tree_id"],
                  "team_bonus": c["team_bonus_id"], "start": c["resources"][:6]} for i, c in enumerate(d["civs"])],
        "civ_info": civ_info, "style_gfx": style_gfx, "units": units, "techs": techs, "effects": effects, "terrains": terrains,
        "terrain_restrictions": [[round(x, 2) for x in r["passable_buildable_dmg_multiplier"]] if "passable_buildable_dmg_multiplier" in r else [] for r in d["terrain_restrictions"]],
        "tree": tree, "names": {str(k): v for k, v in S.items() if 3000 <= k < 10000 or 120000 <= k < 190000},
    }
    graphics = {str(g["graphic_id"]): {"name": g["filename"], "slp": g["slp_id"], "layer": g["layer"], "frames": g["frame_count"],
                         "angles": g["angle_count"], "speed": round(g["frame_rate"], 3), "replay": round(g["replay_delay"], 3),
                         "seq": g["sequence_type"], "mirror": g["mirroring_mode"],
                         "deltas": g["graphic_deltas"]} for g in d["graphics"] if g["slp_id"] >= 0 or g["filename"]}
    a.out.mkdir(parents=True, exist_ok=True)
    (a.out / "rules.json").write_text(json.dumps(rules, separators=(",", ":")))
    (a.out / "graphics.json").write_text(json.dumps(graphics, separators=(",", ":")))
    print(f"{len(units)} units, {len(techs)} techs, {len(effects)} effect bundles, {len(graphics)} graphics -> {a.out}")


if __name__ == "__main__":
    main()
