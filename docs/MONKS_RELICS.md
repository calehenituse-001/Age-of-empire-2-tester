# Monks and relics (2026-10-22)

Tests: `tests/monks.tscn` (conversion, relics, gold, drops, saving) and the conversion check in `tests/rival.tscn`.
Code: `Soldier` (monk part: `_monk_ai`, `_convert_ai`, `_carry_ai`, `convert_to`), `Relic`, `ConvertAura`, `GameMap.convert_mob / add_relic / scatter_relics /
_relic_income`, `Building.relics / drop_relics`, controller taps, HUD texts, minimap dots, `SaveGame`.

## Conversion
- A monk (unit 125, class 18) already healed wounded friends by himself. Now he also **converts**: tap an enemy with monks selected (`Soldier.order_attack`
  turns into a conversion order for monks; a building is left alone). An idle monk with his faith back also converts the nearest enemy within his range
  on his own (like the original).
- Range is the data's (9 tiles; Block Printing adds 3), the chant takes a random 4 to 10 game seconds (the convert task's `work_value1/2` in the data) (`CONVERT_MIN/MAX`, divided by `Rules.GAME_SPEED`
  like every time in the game), then the unit changes sides: a ring that fills up (`ConvertAura`) shows it is being converted, and the chant starts over if
  the monk or the target moves out of range.
- After a conversion the monk must **recharge** 62 game seconds (`RECHARGE`; 1.5x faster with Illumination, resource 35 >= 3). While recharging he heals
  but does not convert.
- What can be converted: soldiers and villagers of the other side. Not wild animals or ships. **Enemy monks only with Atonement** (`tech.res[27]`), **siege
  only with Redemption** (`tech.res[28]`). Not done: buildings (Redemption), Heresy, Theocracy, Faith (conversion resistance), Herbal Medicine.
- `convert_mob`: a `Soldier` changes team in place (`Soldier.convert_to`: blue sheet, our research, same share of health, no difficulty factors); a rival worker
  (`FoeVillager`) is replaced by a `Villager` of ours with the same share of health and the rival loses a worker.
- The Monastery techs apply through the data: Fervor (speed), Sanctity (hit points), Block Printing (range) are ordinary unit stat effects in `TechState`.

## Relics
- Five relics (unit 285, the original golden reliquary) are placed on dry ground when a game starts (`GameMap.scatter_relics`: at least 24 tiles from your town
  and 14 from each other). A relic is on the ground, in a monk's arms or in a Monastery (`Relic.carrier / holder`). The minimap shows relics on the ground.
- Select a monk and tap a relic: he walks over and takes it (his picture changes to unit 286, "Monk with Relic", with the relic in your colour). While he carries
  it he neither converts nor heals. With him selected, tap one of your finished Monasteries and he carries it in.
- Each relic inside a Monastery pays **0.5 gold per game second** (`Relic.GOLD_RATE`, so 0.75 per real second at the game's speed). A monk that dies drops the
  relic where he fell; a destroyed Monastery drops all its relics around it.
- Saves: relics on the ground (`relics`), a monk's (`relic` in his entry) and a Monastery's (`rel`).
- The rival does not train monks or collect relics (yet).

## Speech
Monks have two lists of their own, `convert` and `relic` (see `docs/CHATTER.md`).

## Housing
A converted unit leaves the other side's population at once (the rival's `pop()` is counted from its live units) and counts for ours (`recalc_pop` after every
conversion). Your population may then stand above your housing cap, as in the original: nothing is lost, but you cannot train more until you build houses.
