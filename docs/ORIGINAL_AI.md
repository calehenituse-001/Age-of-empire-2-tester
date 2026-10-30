# How the original computer player works (from the user's AoE2 HD install)

Found 2026-10-22. Companion to `docs/RIVAL.md` (our own, simpler opponent).

## Where it is
- `AI/AI.txt` is a placeholder. The real scripts are **text resources inside `Data/gamedata.drs` and `Data/gamedata_x1.drs`**: type `bina`,
  ids 60001..60029 (about 790 KB of rules, 22,957 lines for the Conquerors set). `python3 -I tools/extract_ai_scripts.py --out <new dir>` writes them.
  File 60026/60027 load constants, 60001 the starting goals, 60019+ the age-by-age build orders, 60023 "the bully" (diplomacy personality).
- Language: `(defrule <conditions> => <actions>)`, run in a loop by the engine; `(set-goal ...)`, `(set-strategic-number sn-... n)`, timers
  (`enable-timer`, `timer-triggered`), `(build x)`, `(train x)`, `(research x)`, `(attack-now)`, `(build-wall 2 stone-wall-line)`.
  The script decides **what and when**. The engine does the **placement, pathing, grouping and fighting** (in `AoK HD.exe`, not decoded).
- The exe holds the table of all ~150 strategic numbers (names at 0x775270..0x77623c, found with REA/Ghidra). Many are never set by the
  scripts, so the engine has defaults we did not read: `sn-minimum-town-size`, `sn-random-placement-factor`, `sn-required-forest-tiles`,
  `sn-sentry-distance(-variation)`, `sn-defend-overlap-distance`, `sn-group-leader-defense-distance`, `sn-initial-attack-delay`,
  `sn-attack-group-size-randomness`, `sn-scale-*-attack-group-size`, `sn-attack-separation-time-randomness`, `sn-build-frequency`,
  `sn-number-build-attempts-before-skip`, and the target scoring `sn-target-evaluation-*` (distance, hit points, damage capability, kills,
  rate of fire, ally proximity, randomness, siege weapon, range, boat, continent).

## Where it builds (script side)
- Everything is placed **around its town**: `sn-maximum-town-size` is the radius in tiles: **15 in the Dark Age**, `feudal-town-size` **20**,
  `castle-town-size` and `imperial-town-size` **25 or 30** (constants by civilization in file 60027). The engine picks the actual cells.
- Economy buildings follow the resources: `sn-camp-max-distance` (lumber and mining camps) and `sn-mill-max-distance` start at **20**, rise to
  **35** in the Feudal and **50** in the later ages; drop-site limits `sn-maximum-wood/food/gold/stone-drop-distance` 20/8/20/20 (hunt 30).
  Builders are capped at 8 (`sn-cap-civilian-builders`); `sn-number-forward-builders` is for forward bases.
- **Walls**: goal `wall-build` goes NOTICE after the Dark Age, then YES unless it is rushing, going for a Castle, or on some maps. Then
  `(build-wall 2 stone-wall-line)` ("perimeter 2": a ring around the whole town, laid out by the engine) as soon as it can afford the
  complete wall or holds more than 125 stone (Feudal) / 300 stone (later). Up to 4 gates (`build-gate 2`), Fortified Wall research while
  walling. When the ring is complete (`wall-completed-percentage 2 == 100`) it stops; with no gates it deletes a closed wall again.
- **Towers**: timer `t-tower` (every 60 s when it can afford a wall or has 500 stone, otherwise every 300 s); a tower is built when
  `wall-build` is NO or the timer fires: Watch Tower in the Feudal Age (up to 3 while going for a castle), Watch Tower line (Guard Tower /
  Keep) in the Castle Age up to 6 and in the Imperial up to 9, Bombard Towers when available. After it has a Wonder it builds towers without limit.
  So walls and towers compete for stone.

## How its soldiers behave (script side)
- **Defence**: `sn-percent-enemy-sighted-response` (10 / 25 / 75 / 99 percent by difficulty, easiest to hardest) of its soldiers answer an enemy
  seen within `sn-enemy-sighted-response-distance` (10 in the Dark Age, 15 later). `sn-allow-civilian-defense 1`: villagers fight too (some
  personalities set 0). `sn-defense-distance 2`, `sn-gather-defense-units 1`; defend priorities per place: town 1, gold 2, stone 3, forage 0,
  relics 0 (`sn-*-defend-priority`): **defend groups are stationed at the town and at the gold and stone mines**, which is the "patrolling" you see.
- **Idle soldiers**: `sn-gather-idle-soldiers-at-center` is 1 once the military is over 30 percent of the population and 0 below 20 percent
  (otherwise they stand where they were trained). `sn-task-ungrouped-soldiers` switches whether loose soldiers get tasks. `ri-town-patrol` is
  the Town Patrol tech, not the behaviour.
- **Attack**: timer `t-attackgroup` sets `attack-control YES` and `sn-percent-attack-soldiers 100`; no attack while it has no siege
  (`goal siege-available NO`), while a Wonder stands, or with no enemy. Then `(attack-now)` sends the soldiers as groups (`sn-group-form-distance`
  10 / 20 / 30 by age). It tracks `military-parity` (NO when an enemy army is much bigger, e.g. enemy > 50 and its own < 45; SUPERIOR
  when it is far ahead) and `enemy-soldiers` (10 / 20 / 30 by enemy soldiers, towers, castles, town centers) to decide how much army to build.
- **Retreat / flee**: no script rule and no text in the exe (searched "retreat", "flee", "patrol": only `ri-town-patrol` and the UI's Patrol
  command). Whatever it does when overpowered is engine code. The only related numbers are `sn-ignore-attack-group-under-attack` (0: an
  attack group answers when it is attacked) and `sn-hits-before-alliance-change`. Not decoded.

## What our rival took from it (2026-10-22: walls, towers, defend groups, see `docs/RIVAL.md`)
Done: a stone wall ring with gate openings from the Feudal Age, towers on the timer (3 / 6 / 9), defend groups at the Town Center and the
mining camp, idle soldiers gathering at the center above 30 percent military, patrol around the post. Not done: town radius growing to 25-30
tiles, camps spreading 20 -> 35 -> 50 tiles, real gates, attacks only with siege available, the military-parity rule, retreat.
