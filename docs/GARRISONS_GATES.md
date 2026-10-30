# Garrisons and gates (2026-10-22)

**Garrisons are switched off** (`Building.GARRISON = false`, so every capacity is 0): villagers and then soldiers hiding in buildings were taken out at the user's request. The code below stays dormant (a saved game with units inside puts them back beside the building). Gates are unaffected.

Tests: `tests/garrison.tscn` (player side), `tests/gates.tscn`, and the shelter and gate checks in `tests/rival.tscn`.

## Garrisons
- **Capacity** is the data's `garrison` value (`Building.garrison_cap`): Town Center 15, Castle 20, towers 5, Barracks / Archery Range / Stable /
  Siege Workshop / Monastery / Dock 10, everything else 0. **Only soldiers garrison** (not rams or ships): villagers were allowed to shelter at
  first and that was removed again at the user's request (the original has no such command in this game's version of the interface). Old saves
  with villagers inside put them back beside the building on load. `Building.accepts(m)` is the rule, `can_garrison` adds "has room".
- **Orders**: select soldiers, tap a finished building of yours: they walk there and go in (`Mob.order_garrison`; `Mob.garrison_tick` runs first
  in the tick of soldiers). As many as fit; a full building says so.
  With nothing that can enter selected, the tap still selects the building. A building with units inside shows "Garrison n / cap" and an
  **Unload** card; a destroyed building lets the survivors out.
- **Inside**: the unit is hidden (`visible = false`), off `GameMap.mobs` (so nothing targets or ticks it), `garrisoned_in` set, and still
  counts for the population (`recalc_pop` adds `garrison.size()`). Units inside heal 2 hit points per game second.
- **Arrows**: Town Center, Castle and towers shoot one arrow more for every garrisoned infantry, archer, cavalry archer or hand cannoneer
  (`Building.garrison_arrows`, `Soldier.shoots_from_garrison`; classes 6, 0, 36, 44).
- **Saves**: a unit inside is saved with its building's origin (`gb`, `gf` for the rival's) and put back in with `garrison_add`.
- The rival does not garrison (its villagers used to shelter in its buildings; removed with the player's villager garrison).

## Gates
- A gate is a building of 3 x 1 cells along x or y (`Building.rect()`, `gate_axis`), unit 487 (data: Gate, 2750 hit points, 30 stone, Feudal
  Age here), pictures `bld_487` (runs along y, the "/" diagonal) and `bld_490` (along x). The data's footprint is 4 x 1; we use 3 so it fits the
  3-cell openings of the rival's ring and a straight run of walls. It has no building foundation. An open gate (a unit of its team within
  2.8 tiles) is drawn half see-through.
- **Passability**: there are two walker grids. `astar` is the player's view and `bstar` the rival's (`GameMap.find_path(..., team)`,
  `blocked`, `adjacent_path`; `Mob` passes its own team). Everything is identical except the gate cells: the player's gates are open in
  `astar` and shut in `bstar`, the rival's the other way round, and a locked gate is shut in both. Enemies can therefore never walk through
  a gate (the original lets them slip in behind your units when it is open; we do not).
- **Placing** (Defense tab): tap a spot; the gate turns to lie along a wall beside it and replaces the wall pieces under it (those cells may be
  occupied by your own walls). **Turn** rotates it. Villagers build it like any building. Select a finished gate for **Lock / Unlock**.
- **No way through** (`GameMap.nearest_blocker`, `Mob.combat`): when a soldier's target cannot be reached it attacks the nearest wall or gate
  of the other team within 40 tiles. This holds for the player's soldiers against the rival's ring and for raiders against your walls, which used
  to stop in front of a closed ring.
- **The rival** (`Rival._gates`): once 70 percent of the ring stands it closes the four openings with gates (30 stone each, front first, one at a
  time, Medium and Hard). Its units pass through them; the player's must break the gates or walls. Gates count as walls for victory.
- Saves hold the direction (`ax`) and the lock (`lk`).
- Not done: diagonal gates, Fortified Wall upgrades, palisade gates, sea gates, letting enemies slip through an open gate.

## Selection and markers (changed afterwards)
- A villager that has been given a job (gather, build, farm, repair, hunt) is deselected at once (`Controller.release`), so that a tap elsewhere
  cannot send it away from the job. A move order keeps the selection.
- The marks where units are sent: a move shows four green arrows closing in on the spot, as in the original (graphic MOVETO). The pixel art
  of the original (graphics.drs slp 3405, red) looked coarse on the tablet, so `MoveMarker` redraws it as a vector: `assets/marker_arrow.svg`
  (one arrow, 3D green with a shadow; imported at 4x in `marker_arrow.svg.import`), four of them laid on the ground and squashed to the 2:1
  view, sliding in 29 -> 6 ground units over 0.8 s, looping 3 times and fading; about 70 pixels across. An attack target keeps the procedural red
  arrow with a crosshair (`TargetMarker`). The red pixel originals (`a_marker_*.png`, from `tools/extract_markers.py`, plus the cursor "arrow over
  ripples") are extracted but unused. I searched graphics.drs, interfac.drs, gamedata_x1_p1.drs, the loose `Data/Slp` files and the exe's
  resources for a green arrow: none exists. The interface's other cursors (sword, hammer, axe, horn, flag, door arrows) are in the same SLP, unused.
