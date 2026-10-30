# Balance notes

Run the harness: `godot --headless --path godot_game res://tests/balance.tscn` (about 15 minutes; it prints and writes
`balance.txt`). It is not a pass/fail test: it measures, so the numbers can be tuned.

What it measures
- **Economy** with the real rates: wood 35, food 28 (berries) / 48 (farm), gold 34, stone 32 per villager-minute
  (data work rates x 1.5). Villager 16.7 s to train, house 16.7 s, Feudal Age 87 s.
- **Raids**: each difficulty and wave against 8 soldiers (Militia and Spearmen) and against 16 soldiers plus 2 Watch Towers.
- **Wildlife**: wolves and boars against a starting village (0 villagers lost in 5 minutes on every difficulty).
- **Cost**: one simulation step of a late-game map (171 units, 4,350 resources) takes about 0.7 ms on the desktop.

Findings (2026-10-21) and what was changed
- The Town Center did not shoot. In the original it fires at enemies in range, so it does now (1 arrow at the Dark and Feudal
  look, 2 in the Castle Age, 3 in the Imperial Age); wave 5 on Medium went from "8 soldiers wiped out" to "almost held".
- Medium raids ramped too fast at wave 5 (Man-at-Arms, Crossbowmen and Rams at once). Tiers are now Spearman 3, Man-at-Arms 6,
  Crossbowman 7, Ram 9, Mangonel 12.
- Rams are what finally break buildings: Militia and Spearmen do 1 damage a blow to a Town Center (melee armor 3).
- Hard: 8 soldiers fall at wave 2; that is intended (300 s first raid, 150 s between raids).

Unverified: how it feels on the tablet. The harness plays no economy; it only replays the fights.
