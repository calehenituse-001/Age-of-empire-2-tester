# Mod package format v1

A ZIP with `manifest.json`, `content.json`, optional `README.md`, and original PNGs below `sprites/`. No enclosing top-level folder. See `samples/ModernEraExpansion` for a complete installable example; `python3 tools/package_sample.py` builds the package.

```json
{
  "formatVersion": 1,
  "id": "npc.modern-era",
  "name": "Modern Era Expansion",
  "version": "0.1.0",
  "author": "Your name",
  "gameVersion": "aoe2hd-beta-source-1",
  "frameworkVersion": "1.0.0",
  "dependencies": [],
  "capabilities": ["buildings.add"]
}
```

IDs match `[a-z][a-z0-9_.-]{2,63}`. Versions are `major.minor.patch`, each part 1–4 digits. Dependencies contain `{ "id": "author.package", "version": "1.0.0" }`, require exact versions and must load earlier. Framework/game versions are exact for v1, intentionally conservative. Install does not enable. Duplicate installed IDs cannot overwrite data; disable/delete before replacing. Save profiles remain.

`content.json` contains only `{"buildings": [...]}` with 1–32 rows per package:

| Field | Meaning / bound |
|---|---|
| `id` | Unique integer 900000–999999; rejected on conflict |
| `key`, `name` | Unique identifier; display name 1–80 characters |
| `baseId` | 70 / 562 / 584 / 68; supported non-combat economic base row must exist in actual HD data |
| `size` | Square footprint, integer 1–4 tiles |
| `hp` | Integer 1–100000 |
| `seconds` | Construction time 1–3600 simulation seconds |
| `population` | Capacity 0–50 |
| `requiredAge` | 0–3; build menu checks current player's age |
| `cost` | Resource-name dictionary; food/wood/gold/stone, each integer 0–100000 |
| `dropoff` | List drawn from food/wood/gold/stone |
| `sprite` | Relative `sprites/*.png` path |
| `hotspotX`, `hotspotY` | Image-space isometric anchor within the image dimensions |

Sprites must be valid PNG, at most 2048×2048, at most 8 MB. Transparency is preserved. Supply Depot uses 256×192 and original artwork. Base construction stages use imported game data; new construction-stage/animation schemas are not supported in v1. Existing game directional animations remain supported through the original engine, not through arbitrary mod declarations.

ZIP validation rejects traversal, absolute paths, backslashes, ambiguous/duplicate names, code/PCK/native libraries, more than 256 entries, more than 8 MB per extracted file or 64 MB total. Metadata has stricter size bounds. Extraction uses staging and promotion after validation. The Godot runtime independently validates registry values, decodes sprites and checks engine ID/base conflicts before any definition changes.

All enabled mods are validated before activation. Conflicts stop launch with a useful error; Safe Mode ignores optional selection. Registration happens only in memory at startup; original raw/imported files are never patched. Disabling means a fresh engine process with no registration. A fingerprint of ordered package contents isolates saves. Normal gameplay progress is not retroactively undone by disabling a mod.

## Future adapters (not implemented)

`units.add`, `technologies.add`, `civilizations.add`, custom production/prerequisite graphs, maps/scenarios, economic rule hooks and bounded animation definitions need engine-specific registries and tests. Plan directional idle/walk/attack/death states, consistent anchors and shadows, capped sheets and AI support. Do not ship executable scripts in v1 or claim changing a PNG creates a functional new unit. Combat cheat hooks belong to the separate owner-scoped CheatPolicy.
