# Age of Empires II HD: how the game files work (and how this project reads them)

Everything here was verified against an AoE2 HD install (dat version `VER 5.7`, 2019 repack). Nothing from the game
is stored in this repository; `tools/` reads your own install and writes `godot_game/assets/aoe/` (keep it out of any repository).

## Pipeline

    tools/import_dat.py      -> assets/aoe/data/rules.json, graphics.json   (stats, techs, effects, tech tree, terrains)
    tools/extract_aoe_godot.py -> assets/aoe/*.png, manifest.json, snd/, music/   (sprites, sounds, music)
    godot_game/scripts/rules.gd + tech_state.gd -> the rules at run time

Run: `python3 -I tools/import_dat.py --game <AoE2HD dir> --openage <openage>/src --out godot_game/assets/aoe/data`
The importer needs a checkout of https://github.com/SFTtech/openage (GPLv3) only to parse the .dat; its reader runs
unchanged on the HD file when told the edition is `HDEDITION`. A built-in reader is the next step if this should
ever run without it.

## Files in the install

| File | Content |
|---|---|
| `Data/empires2_x1_p1.dat` | raw-deflate (`zlib.decompress(data, -15)`) game database, ~5.6 MB inflated |
| `Data/*.drs` (`graphics`, `gamedata*`, `sounds`, `interfac`) | archives of SLP sprites, WAV sounds, palettes (BIN) |
| `Bin/en/language*.dll` | text: unit, building and tech names as a Windows RT_STRING table (`tools/aoe_strings.py`) |
| `Data/blendomatic*.dat`, `TileEdge.Dat`, `FilterMaps.dat` | terrain blending masks (shorelines, phase 3) |
| `Sound/`, `Avi/` | music (mp3) and videos |

### DRS
Header at 0; at 0x38 table count and first file offset; table entries at 0x40 (12 bytes each: 4-byte reversed
extension e.g. `pls`->"slp", offset, count); each file entry `<id, offset, size>`. Files are looked up by (type, id).

### SLP (sprites)
Header `version[4]`, frame count, comment; per frame (32 bytes at 0x20): cmd table offset, outline table offset,
palette offset, properties, width, height, hotspot x, hotspot y. Outline table: per row `<left, right>` (0x8000 = empty).
Commands per row, low bits select: `0` colour list, `1` skip, `2` big list, `3` big skip, `6` player-colour list, `7` fill,
`0x0f` end of row (shadow/outline codes in the 0x0a-0x0e range). Palette index 0..255; **player colour pixels have
index+16*player: offset 0 = blue, +32 = red** (palette `50500.bin`). Building shadows use indices 0 and 206.

### Graphics table (dat `graphics`)
`filename, slp_id, layer, frame_count, angle_count, frame_rate, replay_delay, sequence_type, graphic_deltas[]`.
Naming: `AN` attack, `DN` die, `FN` idle, `SN` corpse decay, `WN` walk; buildings `N...` pieces, deltas give extra
pieces (left wing, right wing, main hall) drawn on one hotspot, in the order of the delta list.

### Units / buildings (dat `civs[c].units[]`)
Indexed by position; the `id0` field is the real unit id. `unit_headers[id].unit_commands` holds the tasks (gather,
build, attack...). Important fields: `hit_points`, `speed` (tiles per game-second), `attacks`/`armors` as
`[class, amount]` pairs, `weapon_range_max`, `attack_speed` (reload s), `resource_cost[3]` (type 0 food, 1 wood,
2 stone, 3 gold), `creation_time`, `train_location_id` (**base id of the building**), `enabled` (available at start),
`research_id` (marker tech a finished building adds), `resource_storage` (type 4 = population provided),
`construction_graphic_id`, `idle_graphic0`, `dying_graphic`, `move_graphics`, `attack_sprite_id`.
Villager task variants have their own unit ids with the real gather rates in `work_rate`: Forager 120 (0.31),
Hunter 122 (0.41), Lumberjack 123 (0.39), Stone miner 124 (0.36), Farmer 214 (0.53), Gold miner 579 (0.38),
Fisherman 56 (0.43), Fishing Ship 13 (0.28); carry capacity 10 (hunter 35).
Class ids used by armour/attack: 3 pierce, 4 melee, 8 cavalry..., 11 stone defence..., 13 siege...; see openage's
`armor_types`.

### Techs and effects
`researches[id]`: costs, time, `research_location_id` (base building), `required_techs[6]` with `required_tech_count`,
`tech_effect_id` -> `effect_bundles[id]`. Effect `(type, a, b, c, d)`:

| type | meaning |
|---|---|
| 0 / 4 / 5 | set / add / multiply attribute `c` of unit `a` (or of all units of class `b` when `a = -1`) by `d` |
| 1 / 6 | set-or-add / multiply resource `a` (resource 6 is the **age**: 0 Dark, 1 Feudal, 2 Castle, 3 Imperial) |
| 2 | enable (`b=1`) or disable unit `a` |
| 3 | unit `a` is upgraded into `b` (Militia 74 -> Man-at-Arms 75; Town Center 109 -> 71 -> 141 -> 142) |
| 101 / 103 | change cost (resource `c`) / research time of tech `a` |
| 102 | disable tech `d` (this is how a civ's tech tree is expressed) |

Attributes: 0 hit points, 1 line of sight, 5 speed, 8 armour (`d = class*256 + amount`), 9 attack (same), 10 reload,
12 range, 13 work rate, 14 carry capacity, 101 train time, 103/104/105/106 food/wood/stone/gold cost.

**Free techs** (location -1, no cost) are researched automatically once their prerequisites are met. That is how the
game unlocks buildings (Barracks <- tech 220 needs Dark Age 104) and checks the age requirements: Feudal 101 needs
Dark Age 104 plus tech 120, which needs 2 of the marker techs that Dark Age buildings add (`research_id`). Castle needs
2 Feudal-age buildings (tech 135), Imperial 2 Castle-age ones (tech 142). `TechState._auto()` implements this.
Dark Age = tech 104; the civ's `tech_tree` bundle is applied first and disables what the civ lacks.

### Terrains
`terrains[id]`: `internal_name`, `slp_id`, `blend_priority`, `blend_mode`, map colours. Water is terrain 1 (`g_wtr`),
shallows 4, ice... (phase 3 will document the blending: `blendomatic.dat` holds the edge masks).

### Strings
Language DLL string id `n` lives in resource block `n//16 + 1`, slot `n%16`. Unit name = `language_dll_name`, tech
description = `language_dll_description`.

## Combat (scripts/combat.gd)
Attack and armour are `[class, amount]` pairs. Damage = sum over the **target's** armour classes of
`max(0, attack[class] - armour[class])` (an attack class the target has no armour entry for is ignored), at least 1.
Classes: 1 infantry, 3 pierce, 4 melee, 5 war elephant, 8 cavalry, 11 buildings (standard), 13 stone defences, 15 archers,
17 rams, 20 siege weapons, 21 buildings (attack bonus), 22 walls and gates, 25 monks, 27 spearmen, 29 eagle warriors.
So a Spearman (+15 vs class 8) pierces cavalry, a Ram (+125 vs class 11) flattens buildings, a Militia does 4 to a
house. Blacksmith techs are effects on classes (attribute 8/9 with `class*256+amount`), unit upgrades are type-3 effects.
`reload` (attack_speed) and `speed` are in game seconds/tiles per game second, times `Rules.GAME_SPEED` for real ones.
Which building trains what: `train_location_id` = base building id (Barracks 12, Archery Range 87, Stable 101,
Town Center 109); `TechState.train_list()` returns the newest form of everything enabled there. Tower upgrades are techs
at the University (Guard Tower 140, Keep 63); arrows per volley are not in the data in a usable form (`Defs.TOWER_SHOTS`).

## Roster notes (phase 4)
- Buildings by base id: Barracks 12, Archery Range 87, Stable 101, Siege Workshop 49, Blacksmith 103, University 209,
  Monastery 104, Castle 82, Market 84, Dock 45, Watch Tower 79. Units come from `train_location_id`; techs from
  `research_location_id`. Some units are techs, not free: the Scorpion is tech 94 (Castle Age) at the Siege Workshop.
- Siege: a Ram is class 13 with range 0 (buildings only); a Mangonel is class 13 too but ranged (7, min 3) with
  `blast_range` 1: its blow hits every hostile within that radius of the target (`Projectile._blast`).
- Monk (125, class 18): no attack; task 105 = heal, `work_value1` 2.0 hit points per game second, range 9.
- Castle (82): shoots like a tower (range 8, pierce 11); arrows per volley are a game setting (`Defs.TOWER_SHOTS`).
- Market barter is not in the dat. Used: prices start at 100, +-3 per 100 traded, drift back 1 per 10 s, fee 30% (resource 78
  is set to 0.15 by Guilds, tech 15) and trades only against gold. These numbers are from the wiki, not the data.
- Skipped on purpose: Trebuchet (pack/unpack), trade carts and trade routes, monk conversion and relics, gates, unique
  techs of other civs (the importer applies the Britons' tree and Britons' civ bonuses only).

## Civilizations (phase 5)
- `civs[c]` holds `tech_tree_id` (an effect bundle of type-102 disables: the techs the civ lacks), `team_bonus_id` (not used,
  multiplayer only) and a full unit table. **Unit stats are identical in every civ**; only graphics and sounds differ.
- Civ bonuses are techs with `civilization_id == c` and no cost/building: `TechState._auto` researches them at the start
  (Britons: Town Centers -50% wood in Castle Age, archer range ...). Unique techs sit at the Castle (82) and Imperial.
- Unique units are enabled by civ techs once a Castle stands (the Castle's marker tech 266 is `research_id` of unit 82), so
  `TechState.building_done(82)` is needed before `train_list(82)` offers them.
- **Architecture sets**: 5 groups of civs share the Feudal-and-later building graphics: 0 West European (Britons, Franks,
  Celts, Spanish), 1 Central European (Goths, Teutons, Vikings, Huns), 2 Eastern (Japanese, Chinese, Mongols, Koreans),
  3 Middle Eastern (Byzantines, Persians, Saracens, Turks), 4 Mesoamerican (Aztecs, Mayans). Dark Age buildings look the same
  for all. The importer detects the sets by comparing idle graphics of ids 463, 498, 71, 141, 142, 87, 103, 84, 104, 82, 45
  and exports `style_gfx[set][building id]`; `extract_units.py` writes `bld_<set>_<id>.png` only where a set differs from set 0.
- Text: civ names are language strings 10231+, the bonus descriptions 20150+ (`civ_info[].text`).
- Not in the data: some start modifiers exist only in those texts (Chinese +3 villagers -50 wood -200 food, Persians +50
  wood and food, Mayans +1 villager -50 food, Huns no houses -100 wood): `Defs.CIV_START`.
- Land unit graphics are the same for all civs; Aztec/Maya monks and the ships differ (not done).

## Hunting (wild animals)
- Gaia units: Wild Boar 48 (75 hp, attack 7, 340 food), Deer 65 (5 hp, harmless, 140 food, speed 0.737), Wolf 126 (25 hp, attack
  3, no meat); `resource_storage[0]` type 0 is the food. Hunter villager variant 122: rate 0.41 (x1.5), carries 35.
- A killed animal that has food leaves a `Carcass` (a food `ResNode` with `hunt = true`, gathered at the hunter's rate and
  capacity, rotting after 160 s). Villagers kill deer and boars themselves (`Villager.order_hunt`), soldiers and towers kill
  what threatens; towers and soldiers ignore harmless prey (`Mob.is_threat`).

## Sprites by unit id (tools/extract_units.py)
- `graphics.json` is keyed by the dat's `graphic_id` (openage's list is compacted: the list position is NOT the id).
- Unit animations: `gfx.idle/move/attack/die` of the unit row; the corpse is the idle graphic of `dead` (unit type 30).
  Each SLP stores 5 of the 8 angles (the rest are mirrors: `flip_h` in the game); a few SLPs hold spare frames at the end.
  Red enemy sheets = player colour offset +32.
- Buildings: the idle graphic is the first piece, its `deltas` (other graphic ids, shadow `N0`, garden `N1`, wings) are
  drawn over it; the Town Center's other parts are **annex units** (`annex` list, ids 618-620, openage skips them, the
  importer patches the reader to keep them) whose graphics carry their own hotspots, so they are stacked at offset 0.
- Age looks: Feudal/Castle/Imperial (techs 101-103) contain type-3 effects turning each building (and each annex) into the
  next look; `TechState.current(id)` follows them, `extract_units.py` extracts every id in those chains.
- **Names are not what the file prefixes suggest.** In the dat the Militia uses SPRMN_* (a club-armed peasant), the
  Man-at-Arms SWDMN_*, the Spearman PKEMN_*, the Long Swordsman THSWD_*. Always go through the unit row.
- Britons' Town Center chain 109 -> 71 -> 141 -> 142 is a western set (thatch, then slate roofs); the E-suffixed graphics
  are another architecture set.
- Ships and other composite graphics: see "Composite graphics" below.

## Terrain, shorelines and water (tools/extract_terrain.py, scripts/terrain_blend.gd)
- `terrain.drs` holds each terrain as an SLP of 100 tiles (97x49 diamonds, a 10x10 pattern: frame = x%10 + (y%10)*10).
  The terrain table (dat) gives `blend_priority` and `blend_mode` per terrain: grass 12 (100, mode 0), water 1 (140, mode 3),
  beach 2 (110, mode 2), shallows 4 (60, mode 4), dirt 6, forest 10 ...
- **Blending** (`blendomatic_x1.dat`: 9 modes x 31 masks, each a 97x49 diamond of weights 0..128; **128 = keep the base
  pixel, 0 = take the neighbour's**): for every tile look at its 8 neighbours (0 up, 1 up-right, 2 right ... = map offsets
  (-1,-1),(0,-1),(1,-1),(1,0),(1,1),(0,1),(-1,1),(-1,0)); a different terrain with a HIGHER priority lays its own tile over
  this one through a mask. Mask choice: the edge neighbours (bits 1,3,5,7) pick 0..3 (single edge, variant = x&3), 4..7, 8..15,
  or 20..30 for combinations; corner neighbours (bits 0,2,4,6) add 16..19 unless an edge neighbour beside them is the same
  terrain. Blend mode = LOOK[mode of this tile][mode of the neighbour] (table in `terrain_blend.gd`). Higher priorities are
  drawn last. `TerrainBlend.apply` builds the blended tiles with `Image.blend_rect_mask` and packs them in one atlas.
- Walkers cannot enter deep water; shallows are walkable but not buildable; ships sail on deep water only (their own
  AStarGrid2D); a dock needs >= 3 water/shallows cells and >= 1 land cell under it and open deep water beside it.
- Fish are Gaia units (importer adds `civs[0]` units): Perch 53, Shore Fish 69, Marlin 450/451, Dorado/Salmon/Tuna/Snapper
  455-458 (food 200-350 in `resource_storage` type 17); their idle graphic is a looping swim/jump animation (frames 1x1
  while hidden). Fishing ship: unit 13, `work_rate` 0.28 x task value 1.75 (class 5 fish), capacity 15.
- Open: the other ships (Galley, Transport, ...) point at graphics whose names/SLP ids the openage reader does not resolve
  (names come out as "W"/"E"); they are probably loose SLPs under Data/Slp. Fish Traps, Fishermen and sea walls are not done.

## Open extraction problems
See `docs/KNOWN_ISSUES.md` (ships, unreliable graphic names, graphics whose SLP is not in the DRS, sounds, projectiles).

## Composite graphics (graphics without a picture of their own)
A graphic whose `slp_id` is in no DRS is a **container**: the picture is the sum of its `graphic_deltas`. For every angle row and
frame, take the same angle and frame from each delta graphic (a delta with one angle or one frame uses its only one; a delta with
`n` stored angles supplies row `r*(n-1)//4` for our 5 rows), place it at `offset - hotspot`, draw in list order. 16-angle graphics
(ships) store 9 angles (0..8, the others are mirrors). Confirmed in the exe: the SLP loader falls back to nothing when the DRS
has no such id (`AoK HD.exe` 0x50c6b0). Implemented in `tools/extract_units.py` (`composite`, `pack_images`); buildings use the
same idea with annexes (`pieces`).

## Gotchas
- Unit index != unit id; always use `id0`. Headers are indexed by id.
- `unit_type` 70 creatable, 80 building, 60 projectile, 30 moving, 20 flag, 10 eye candy.
- HD durations are in game seconds; the original runs at 1.5x at "normal" speed (`Rules.GAME_SPEED`).
- Godot class names are cached: run `godot --headless --path godot_game --import` after adding a `class_name`.

## Naval gameplay
- `Defs.NAVAL` lists ship unit ids; `Defs.is_ship()`/`is_warship()`. Only id 13 (Fishing Ship) uses the `Ship` gatherer script; the others are `Soldier`s with `naval = true`.
- Pathing: `GameMap.wastar` allows deep water only; `order_move` snaps a ship's target to the nearest water cell.
- Ranged ships attack land targets from `GameMap.firing_cell(from, target, range)`, a water cell within range of the target.
- Kamikaze (Demolition ship: blast > 0, range <= 0.5, naval) deals blast damage on arrival and dies.
- Raids: `Director._naval_raid` spawns red-sheet ships at `GameMap.naval_spawn()` per `Defs.DIFFICULTY[..]["naval"]`.

## Building assembly and construction (found 2026-10-22)
- **Draw order is the graphic's `layer`** (5 ground, 10 shadows/floors, 20 structure), list order within a layer. Delta graphics nest: a part
  lists its neighbours again, so expand recursively and keep one piece per (graphic, offset). `Extractor.expand()` / `pieces()`.
- **The Town Center is assembled by its head unit.** TC 109/71/141/142 (dark, feudal, castle, imperial) all point at head unit 621; the
  head chain (621 -> 617 -> 484 -> 597 by age) holds the finished picture: graphic 3345 = ground (433), hall 435 at y -48, wing 3240 at
  y +24, wing 3239 at y +48, each with a roof delta. The three annexes' tile offsets give the same numbers: screen y = -(dx - dy) * 24,
  screen x = 0. Piling the main graphic and the annexes at offset 0 (the old method) scatters the roofs. Mills (sails), gates, the
  Wonder and other multi-piece buildings also changed when nested deltas and layers were honoured (121 images).
- Pitfall: `age_of` (id -> age) must come from base units only and keep the first age; otherwise the Castle TC (141) is taken for age 3.
- Gates use head units 487/490/665/673 with annexes; they were not reworked (no gate mechanics yet).
- **Construction sites**: each building row names `construction_gfx`. The generic ones are CNST1..CNST8 (graphics 118..123, SLPs 236..241),
  one SLP of three frames (stakes, frame, scaffold) per footprint size, identical in every architecture style. The Dock (4248, CNSTD) and
  Fish Trap (5441) have their own; walls and gates (WCON*, GTAX*) are composites with 5 angles x 4 frames. openage's converter shows the
  construction animation at 0, 25, 50, 75 and 100 percent (farms use terrain overlays at 0/33/66/100). Our game shows frame 0/1/2 of the
  site at <34% / <67% / later and lets the finished building rise out of it (clipped from the bottom); `Assets.site(uid, size)`.
  Not verified in the exe: whether the original clips the finished sprite or crossfades.
