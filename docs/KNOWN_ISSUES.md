# Known issues and what is left

Last updated 2026-10-22. Companion to `docs/FORMATS.md` (how the files work) and `docs/BALANCE.md`.

## 1. Extraction failures (what could not be extracted, why, and how to attack it)

Numbers come from the current import of an AoE2 HD install (`dat VER 5.7`, 7,014 graphics, 842 unit/building rows).

### 1.1 Ships (SOLVED 2026-10-22: composited from their delta graphics)
- Ships (Galley, War Galley, Galleon, Cannon Galleon, Demolition/Fire Ship families, Transport Ship, Trade Cog, Longboat, Turtle
  Ship) have graphics whose own `slp_id` (e.g. 2263) is in no DRS: they are **containers drawn from their deltas** (Galley idle
  4052 -> 4057 `SGAL_1HG` slp 4300, 3937 `BOATW4SW` slp 4227, 2763 `SGALY_W0` slp 4515, 16 angles each).
- Confirmed in the exe (REA, Ghidra, `AoK HD.exe`): the SLP object loader (0x50c6b0) tries a loose `slp\<name>` file when the id
  is negative or in HD graphics mode, otherwise the DRS table `'slp '` by id, otherwise the graphic has no picture of its own.
  Nothing else substitutes a picture, so a missing SLP means "container".
- `tools/extract_units.py` `Extractor.composite()` builds every frame from the deltas: same angle row and frame in each delta
  (row r of our 5 maps to stored angle `r*(stored-1)//4`, so 16-angle graphics use stored angles 0,2,4,6,8), each placed at
  `offset - hotspot`, drawn in list order (hull, sails, oars, shadow looked right in every ship tried), player colour applied.
  Result: idle, walk and attack for all ten ship types (see `docs/FORMATS.md`). Remaining gaps: ships have no corpse (they sink
  with the die animation) and the Fishing Ship has no attack.
- Naval gameplay (done 2026-10-22): the Dock trains the warships (`Defs.NAVAL`, minus `NO_TRAIN`), ships fight on `wastar`
  (deep water only) and shell the shore from a firing cell (`GameMap.firing_cell`), Demolition ships blow up on contact, and
  the director sends enemy ships out of the lake on hard/medium difficulty (`Director._naval_raid`). Still open: Transport/garrison.

### 1.1b Building assembly (SOLVED 2026-10-22)
- Town Center wings/hall and nested delta parts are now assembled like the data says (see `docs/FORMATS.md`, "Building assembly and construction").
  Open: gates (head units), wall construction composites, per-style damage/fire graphics.

### 1.2 Farm picture (by design, not a failure)
- `Farm` (id 50) has no building sprite: its idle graphic is a placeholder; the game draws farms from terrain tiles
  (`terrain_farm_fresh/grown`, hand-picked SLP ids in `extract_aoe_godot.py`). Not data-driven; fine as is.

### 1.3 Graphic names are unreliable (parser limitation)
- openage's reader skips the first name field (`name0`, 21 chars) and keeps only the second (`filename`, 13 chars). For
  **3,254 of 7,014** graphics that second string is a 1-2 character fragment (`E`, `W`, `N`, `None`, empty), so `graphics.json`'s
  `name` is only usable for about half the entries. Slp ids, frame counts, angles, deltas are fine.
- Impact: finding a sprite *by name* (`GALLY_*`, `SGAL*`) is unreliable; always go through unit rows -> graphic ids.
- **Fix idea**: patch `unit_mod`-style like the annex patch in `import_dat.py` (`keep(...)`) so `Graphic.name` is read
  (`READ_GEN` instead of `SKIP`), or write our own `Graphic` struct reader.

### 1.4 Graphics that point at SLP ids that are not in the DRS
- **4,590 of 6,615** graphics with an SLP id (1,348 distinct ids; 1,793 of them are id 0, then 2260, 2219, 2220, 2263, 5156
  about 280 times each) have no SLP in `graphics.drs`. Most are composite parents whose deltas *are* present (works for
  buildings), some are placeholders. `graphics.drs` holds only 1,768 SLPs (ids 2..5312); `gamedata_x1_p1.drs` 6 more.
- Not known: whether some of these live in a format we do not read (the HD edition ships SLD/SMP for DE only, not for this
  version, but this was not exhaustively checked). Worth a quick scan of the `Data/` folder and the `.exe` resources if a
  missing picture is ever found that is not a delta parent.

### 1.5 Civilization differences not extracted
- Aztec and Maya **Monk** (and Monk with relic) use different graphics (the unit rows of civs 15 and 16 differ); only the
  Britons' monk is used for everybody. Ships also differ per architecture style (see 1.1).
- `style_gfx` holds building graphics only (plus `construction` ids that the game does not use: foundations are the old
  hand-picked sprites `found_1..4`). Per-style construction sites and damage graphics (`damage_graphics`, fire) are not
  extracted; fire and rubble are the old generic ones.
- Land unit graphics are identical across civs (checked), so nothing is missing there.

### 1.4b Frame-count quirks
- A few SLPs carry spare frames (the Archer idle has 52 frames for 5 angles x 10); the extractor now keeps the first
  `stored * frames` frames. Other graphics may have the same; if an animation looks shifted, check `len(frames) % frame_count`.
- Annex pieces (Town Center wings/hall) are stacked at offset 0 because their SLP hotspots already place them
  (`ANNEX_SCALE = 0.0`); other buildings with annexes (none found) would need verification.

### 1.6 Not extracted at all (no attempt yet)
- **Unit sounds**: `rules.json` has the sound ids (train, select, command, die, damage) but only 51 hand-picked effects and
  2 music tracks (first 6 MB of each) are extracted (`SOUNDS`, `MUSIC` in `extract_aoe_godot.py`). The sound-id -> wav mapping
  was found by regex over the dat; the dat's own `sounds` table is parsed (506 entries) but not used.
- **Projectiles** (arrows, bolts, cannonballs, mangonel stones): the game draws one generated arrow; the data has projectile
  units (type 60) with graphics.
- **Villager task animations** are still the hand-picked ids in `VILLAGER_ANIMS` (the data holds them in the villager
  variants' `cmds`: `work_sprite_id`, `carry_sprite_id`, `move_sprite_id`; not exported yet).
- **Terrains**: 13 of 42 (three grasses, water 1/22/23, beach, shallows, three dirts, forest, palm). Snow, ice, roads,
  desert and the old terrains are not extracted; elevation/cliffs are not supported at all.
- **UI icons** (`interfac.drs`): deliberately unused (own interface).
- Mirrored angles of 16-angle graphics, damage/"burning" stages of units, garrison graphics: not handled.

### 1.7 Dependencies of the import
- `tools/import_dat.py` needs a checkout of openage (GPLv3) to parse the `.dat`; it runs the reader unchanged on the HD
  file (`HDEDITION`) and patches two members (`building_annex`). Without it nothing imports. A standalone reader is open
  work (section 3).

## 2. Verified only in headless tests (not seen on the tablet)
Tombstones, attack-target marker, tower and castle volleys with chatter, UI size switch, debug menu, Android back button,
pinch zoom (cannot be driven by adb), siege and mangonel blast, monk healing, Market trade window, fishing ships and docks
(placed and run headless only), hunting and carcasses, the Blacksmith/University card pages with many cards, civ bonuses
in play, the five architecture styles in game (only compared on a contact sheet), unique units. Tablet frame rate was not
measured (Godot's surface does not appear in `gfxinfo`; use `dumpsys SurfaceFlinger --latency` with the layer name while
the game is in the foreground).

## 3. What is left to do

**Gameplay mechanics (skipped on purpose)**
0. (done) Naval gameplay: see 1.1. Left over: Transport ships carrying units, ship corpses.
1. Trebuchet (pack/unpack) - excluded in `Defs.NO_TRAIN` (42, 331).
2. Trade: trade carts and routes between two Markets (excluded: 128, 204), Barter numbers are from the wiki, not the data.
3. Monk conversion and relics; Missionary (775); Monastery techs that need them.
4. (gates done, see `docs/GARRISONS_GATES.md`; diagonal gates left) Outpost, palisade/stone wall upgrades (Fortified Wall), Sea walls.
5. Fish Traps, Fishermen, naval combat (see 1.1), Transport/garrison.
6. (garrisons done, see `docs/GARRISONS_GATES.md`) Left: repairing by garrison, Transport ships, garrisoning in the Mill/Market/Wonder.
7. Unit abilities not implemented: Berserk regeneration, Chu Ko Nu / Longbowman multi-arrow, Petard suicide, War Elephant
   splash, Huskarl armour, Conquistador, Missionary, Mangudai, Janissary; minimum range of siege.
8. Civ team bonuses, and most numeric civ bonuses are applied through tech effects but only checked for *unique units and
   sprites* (`tests/civs.tscn`); no test proves e.g. Mongol hunting or Spanish builder speed.
9. Hunting extras: sheep and turkeys (data: Sheep 594, Turkey 833, 100 food), herding, boar luring, Wolf packs.
10. (group selection done: lasso, see `docs/LASSO.md`) Fog of war / line of sight (the data has `los`), stances, formations, attack-move, patrol, waypoints.

**Content**
11. (AI opponent and conquest win done, see `docs/RIVAL.md`; left: wonder win, rival navy/Castle and Monastery techs, fog of war) scenarios and campaigns; random map types
    (Arabia, Islands, Rivers), map sizes beyond 160x160, starting-resource settings.
12. Water: wide navigable rivers (current rivers are mostly fords), shallows-only crossings are walkable on purpose; docks
    only on shores; fish respawn.

**Tools and quality**
13. **Standalone importer** without openage (own `.dat` reader) so the project builds from the user's install alone.
14. Fix 1.3 (graphic names); export villager task sprites and unit sounds from the data (1.6).
15. Balance on the tablet after real sessions (`docs/BALANCE.md`), tablet fps, memory use of the blended terrain atlas
    (about 17 MB) and of the sprites (APK about 111 MB, 35 MB of extracted sprites).
16. Optional "sharp pixels" setting (nearest filtering) - the project uses linear filtering on purpose (see pixel-art notes).
17. Test hygiene: the headless suites (`tests/sim.tscn` about 5 minutes, `rules`, `terrain`, `civs`, `balance`) are
    deterministic per fixed seeds, but `sim.tscn` plays on a random map; a few checks were flaky for map reasons and were
    made robust (mangonel, monk, builder). Expect an occasional flake there.
