# The rival (AI opponent)

Added 2026-10-22. Default for new games; Settings -> "Opponent" switches back to the old timed raids (`Defs.OPPONENTS`, applies to the next
new game). Code: `scripts/rival.gd` (the player), `scripts/foe_building.gd` (its buildings), soldier guard mode in `scripts/soldier.gd`,
map hooks in `scripts/game_map.gd` (`start_rival`, `place_foe_building`, `on_foe_destroyed`, `foes`, `victory`), test `tests/rival.tscn`.

## How it plays
- **Base**: `Rival.start()` picks the dry spot (no water/beach within 9 tiles) farthest from the player that is reachable by land, clears
  trees and mines within 8 tiles, lays out the starting resources like the player's (berries, gold, stone, a stand of trees about
  10 tiles away, on the side of the map the base faces) and builds a finished Town Center. Its buildings use a random architecture style other than the player's
  and the player's sprites recoloured by `assets/red_team.gdshader` (blue team colour -> red), so no extra art.
- **Economy is real** (changed 2026-10-22; it used to be an income per head): its villagers (`scripts/foe_villager.gd`, up to
  `Defs.DIFFICULTY[..].rival.workers`, 50 food each) fell trees, mine gold and stone, forage berries and work farms, carry the load to the
  nearest drop-off of the rival (Town Center, lumber/mining camp, mill) and only then does it become stock (`Rival.stock`, `Rival.gathered`
  counts the deliveries). Rates and capacity are the data's villager values times the difficulty's `gather` (0.8 / 1.0 / 1.25).
  Killing villagers hurts. `Rival.assign()` gives an idle villager something to build (at most 8 builders, walls fewer) else a resource:
  the wanted shares are food 38 / wood 32 / gold 16 / stone 14 percent, nudged towards what the stock lacks (a stock over about 800 of
  a resource lowers its share); a villager keeps its resource unless another is short by more than 12 points.
- **Camps follow the resources** (`Rival._camps()`, the original's camp distances 20 / 35 / 50 tiles by age): when fewer than 10 trees /
  4 berry bushes / 2 mines lie within 9 tiles of one of its drop-offs it builds a lumber camp / mill / mining camp beside the nearest
  cluster that is not yet covered (and reachable by land; at most 5 / 3 / 4 of them). **Farms** (`_farms()`): about 0.4 per villager
  minus the berry bushes still covered, up to 10, in the ring 3-7 tiles around the Town Center (kept free of other buildings, which start at
  8 tiles) and around mills; a farm is re-sown for 60 wood when empty. Other buildings wait for a lumber camp and a food source
  (or four minutes).
- **Build order** (`Defs.RIVAL_PLAN`: kind, age needed, target count): houses when pop is within 4 of the cap, Barracks, then
  Archery Range / Stable / Blacksmith / towers in the Feudal Age, Siege Workshop / Castle in the Castle Age. Production building counts
  are capped by the difficulty (`prod`). At most two unfinished buildings at a time; they build themselves (as with one builder).
- **Ages**: at the difficulty's age times it saves food (stops training) and pays 500f / 800f+200g / 1000f+800g, then researches for
  130/160/190 s (/1.5). The Town Center changes look and strength (109 -> 71 -> 141 -> 142) and the roster improves.
- **Army**: `Defs.RIVAL_ROSTER` per building and age (Militia -> Man-at-Arms -> Long Swordsman -> Two-Handed; Archer -> Crossbow ->
  Arbalest; Scout -> Knight -> Cavalier; Ram, Mangonel, Onager). Units gather at a rally point in front of the base in `guard` mode
  and defend (anything of the player's within 15 tiles of the rally point; the whole guard answers when a building is hit).
- **Attacks**: from `first_attack` seconds, once `army + wave * step` soldiers stand guard, all of them switch to `attack` mode (the old
  raider AI: march on the nearest player building, fight what they meet). The next wave can gather once a wave is down to a quarter.
- **Win**: destroy every building of the base -> Victory window (keep playing or new game). **Lose**: as before, all Town Centers gone.
- Player soldiers attack enemy buildings that are within 4 tiles on their own; tapping an enemy building with soldiers selected orders
  the attack; the minimap shows the base as red squares.
- Saves (version 6) hold the rival's state, its buildings and the guard/attack mode of its soldiers.

- **Played like a player** (2026-10-22): nothing is built without a villager: every unfinished building and every unworked farm gets the nearest
  free villager (`Rival._dispatch()`; an idle one first, else one taken off gathering, never one carrying a load). Houses: it builds when
  population (villagers, soldiers, siege) + 6 would pass the cap, up to two at a time (`housing_short()`); a short housing also raises the
  wood share. Farms are posts (a farmer does not leave on a rebalance), 0.3-0.45 per villager depending on food stock, up to 12. Towers go on
  the side the player's town lies (`Rival.enemy`, saved), spread at least 5 tiles. It starts saving for an age at 75 percent of the
  difficulty's age time, so ages come earlier (about minute 10 and 19 on Medium in the test) and food is no longer the only thing it does.
- **Workers**: all of them are visible red villagers. It starts with six villagers and two guarding soldiers. A site nobody comes to builds
  itself slowly after 25 s. A site or resource no villager can reach is skipped for two minutes (an A* that fails is expensive).

## Technologies (2026-10-22)
- The rival has its own `TechState` (`Rival.tech`) of a civilization that builds in its architecture style (`_pick_civ`, shown in the debug
  output; its bonuses and tech tree apply), saved with the game (`civ`, `techs`, and a building's running research `rt`/`rtt`). Its age
  research also researches the age technology (`Rules.AGE_TECHS`), which opens its technologies; a finished building counts as a marker
  technology (`FoeBuilding._finish`), so techs that need a Blacksmith or University work.
- **What follows from it**: villager hit points and armour (Loom), gather rate and load size (`Rival.rate/cap`: Double-Bit Axe, Horse Collar,
  Gold Mining, Wheelbarrow, ...), soldier stats and unit upgrades (`Soldier._tech()`, `on_tech_changed`: Militia -> Man-at-Arms when it
  researches that, with the difficulty's hit point factor kept in `hp_mult`), training time, and hit points and range of its buildings.
- **What it researches** (`Rival._research()`, list per building in `Defs.RIVAL_TECHS`): at each finished Town Center, Mill, Lumber Camp and
  Mining Camp the economy techs (Loom, Wheelbarrow, Hand Cart, Horse Collar, Heavy Plow, Crop Rotation, the axes and saws, gold and stone
  mining and shaft mining); with `techs: "all"` (Medium and Hard) and four soldiers, at the Blacksmith (Forging, armour, Fletching ...),
  Barracks, Archery Range, Stable, Siege Workshop (unit upgrades) and University (Masonry, Architecture, Ballistics). One technology per
  building at a time, paid from its stock; not while it saves for an age. A technology it cannot yet afford is reserved: soldiers are
  not trained out of its price. Easy researches the economy only. Roughly a dozen technologies by minute 16 on Medium.
- Not done: Castle unique technologies, Monastery and Market technologies, Fortified Wall, Keep and Guard Tower upgrades (its towers follow its age).

## Walls, towers and defend groups (from the original AI scripts, see `docs/ORIGINAL_AI.md`)
- **Walls**: Feudal Age on (not on Easy), once it holds 125 stone (300 from the Castle Age) it lays a stone wall ring `Rival.WALL_R` = 17 tiles
  from the Town Center centre, up to 8 pieces at a time, built by its villagers. A 3 cell opening in the middle of each side stands in for the
  original's gates; once most of the ring stands it closes them with real gates (`docs/GARRISONS_GATES.md`). Cells with water, trees or buildings are skipped.
  Wall pieces use the player's wall art, recoloured; walls are not auto-attacked by the player's soldiers (order them or use siege), and are
  not needed for victory.
- **Towers**: `Defs.RIVAL_TOWERS` 3 / 6 / 9 by age (x difficulty `tower_mult` 0.5 / 1 / 1.3), Watch Tower -> Guard Tower (Castle) -> Keep
  (Imperial). While a wall is being built a tower waits for the `t-tower` timer (60 s, or 300 s when stone is short); otherwise it is
  built at once. Placed inside the wall, spread at least 6 tiles apart. Towers, the Town Center and the Castle shoot at the player's units.
- **Defend groups** (`Rival.posts()`): the front of the Town Center (weight 3) and each finished mining camp (weight 2); each new soldier
  goes to the post with the lowest load. With the military over 30 percent of the population every new soldier goes to the Town Center post.
  Idle guards stroll within 3 cells of their post every 6 to 14 s (the original's sentry distance 4) and chase the player's units that come
  within 15 tiles of the post. A post that is lost (camp destroyed) re-assigns its guards.
- A wave that has not ended after 420 s (stuck soldiers) is called home so that the next wave can form.

## Not done
No hunting, fishing or trade, no scouting or retreat, no navy, no Castle unique units, no Blacksmith or
University techs (its soldiers use the data's base stats), no fog of war, no repairs. It rebuilds a lost Town Center when it can pay.
