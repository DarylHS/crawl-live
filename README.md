# Crawl Live!

A turn-based roguelike in Python + pygame, inspired by the *Dungeon Crawler Carl* books by Matt Dinniman. It borrows the books' core ideas (the dungeon as an alien game show, collapsing floors, safe rooms, loot boxes, a companion pet) but all names, characters and text are original.

## Play

```bash
git clone https://github.com/DarylHS/crawl-live.git
cd crawl-live
pip install -r requirements.txt
python main.py            # or: python main.py --seed 1234 for a reproducible run
```

### Views

You see the dungeon in one of two views, and `Tab` switches between them at any time outside a menu (it costs no turn):

- **First-person** (the default): through your crawler's eyes, like Wolfenstein 3D, with a minimap of the area around you and a compass in the corner. Out of combat you have free look: hold a turn key to look around smoothly (a tap turns 45 degrees), and walking steps one tile at a time towards the nearest of the 8 directions to where you look. In combat the view locks to the grid (see Combat below).
- **Map**: the classic top-down view of the floor.

Rules and turns are the same in both; only the view and the movement keys differ. The game remembers your last view between runs and launches in `saves/settings.json` (delete it to go back to first-person). `python fp_demo.py [--seed N]` starts the game in first-person; Tab still saves your choice. Press `?` in the game for the controls of the view you're in.

| First-person | Action |
|---|---|
| `W` / Up | Walk where you look (hold to keep walking, one turn per tile); bumps a monster ahead, or the one 45 degrees either side |
| `S` / Down | Walk back (hold) |
| `A` / `D` | Step left / right (strafe; hold) |
| `Q` / `E`, Left / Right | Turn: a tap turns 45 degrees, holding looks around smoothly (free: no turn passes) |
| Numpad | Move by the compass, 7 9 1 3 diagonally |

| Map | Action |
|---|---|
| Arrows / WASD / numpad | Move; bump into a monster to attack |
| Numpad 7 9 1 3 | Move diagonally |

| Both views | Action |
|---|---|
| `Tab` | Switch view: first-person / map |
| `.` / Space / numpad 5 | Wait a turn; in combat, end your turn |
| `>` / Enter | Descend a stairwell |
| `G` | Pick up items on your tile |
| `I` | Inventory: Enter uses/equips, `U` unequips, `D` drops |
| `R` | Rest to full HP (safe rooms only, costs floor time) |
| `M` | Safe-room menu: loot boxes (odds, open, trade up), shop, crafting, revive your pet, save |
| `R` | On a loot box reveal: hand the item back and reroll for a fee. On the end screen: run report |
| `Y` / `N` | Accept or decline a sponsor contract |
| `C` | Command your pet: follow / attack / stay |
| `K` | Practice skills: what you have levelled by doing it, and what each level gives |
| `L` | Attributes: Strength, Dexterity, Constitution, Intelligence and Charisma; spend the points you earn each level |
| `1` | Use your class skill (from floor 3) |
| `L` | On the title screen: continue a saved run |
| `?` | Help |
| Esc | Back to title |

In menus, Up/Down (or `W`/`S`) move the cursor in either view.

### Combat

A fight starts when a monster notices you or you attack one (never in a safe room), and everyone rolls initiative: d20 plus your Dexterity modifier for you, d20 for monsters and your pet. A "COMBAT: roll for initiative" banner shows, and a tracker in the top-left lists the fighters in order with their HP. Each round is one turn on the floor clock, and on your turn you get:

| Part of your turn | What it covers |
|---|---|
| Move | One step, or swapping places with your pet |
| Action | Attack (bump), throw a bomb, use your class skill, pick up, descend |
| Bonus action | Drink a potion |
| Free | Equip, unequip, drop, command your pet, open menus |

The tracker's Move / Action / Bonus pips go hollow as you use them. Your turn ends by itself once the move and the action are both spent, or press Space to end it early; then the monsters and your pet act in initiative order, each able to step and then attack. Stepping out of a hostile's reach (except by swapping with your pet) gives it an attack of opportunity: one free melee swing, once a round per creature (its reaction comes back when its turn starts). On the map, monsters you'd provoke get orange corner brackets; in first-person an orange label names the keys whose step would provoke ("S provokes the Knockoff Goblin"), and the side chevrons turn orange. It works both ways (a monster backing away from you or your pet gets swung at too), Riposte parries it like any attack, and nothing provokes across a safe-room edge. The fight ends when nothing chasing you is left alive, or when you reach a safe room or take the stairs.

In first-person, combat locks the view to the grid: the camera settles on your tile facing the nearest of the four directions, `W` / `S` / `A` / `D` step one tile (`W` attacks the monster ahead, or the one front-left or front-right), and `Q` / `E` turn 90 degrees. Free look comes back when the fight ends. `Tab` still switches view mid-fight.

## How it plays

Each floor has a collapse timer (1 turn = 1 in-game minute). When it hits zero, the floor collapses and you die. Floors are big (the map scrolls), with three stairwells in the rooms furthest from where you start. The stairwells stay locked until half the floor's time has passed, so you have to survive a while before you can leave; meanwhile new monsters wander in out of sight, more often as the clock runs down. Each floor has one safe room (green): a small enclosed room with a single doorway, a bed, a crafting bench and the shop counter. Monsters can't enter it and nobody can fight inside it, and you can rest there to full HP if you're willing to spend the time. Monsters notice you when they come into your field of view and lose interest after a while out of sight. Monsters carry their own items (a goblin might have a tonic or a party popper) and the dungeon has gear lying around. Loot boxes only come from achievements and sponsors (who send gifts as your viewer count grows), in five tiers, Bronze to Legendary, and can only be opened in a safe room. There are over 30 achievements, for feats like taking down a Headliner and for quirks like rolling a natural 1 or killing ten monsters bare-handed. Each one pops up on screen, the System tells you what you did and what you've won, and when you open the box it reminds you why you earned it. The System AI comments on everything you do, and your viewer count is your score.

You start by creating your crawler: a name, a gender (cosmetic; it changes how the System addresses you) and a backstory, then pick a companion: a vain cat, a loyal dog, a chatty budgie or a scheming, cowardly mouse. On floor 3 you choose a race and a class, each with a skill on key `1`. Bosses come in three tiers, like a show's running order. Opening Acts (several per floor) are elite monsters that drop a map of the surrounding area. Featured Acts (from floor 2) are tougher and drop a better haul. The Headliner guards the furthest stairwell and drops a stairwell key, which opens the stairs straight away, plus a top-shelf item. On the last floor the exits stay sealed until the final Headliner is dead. Safe rooms also have a crafting bench, the shop and a save point.

| Choice | Options |
|---|---|
| Backstory | Military Veteran, Mixologist, Dog Walker, Stand-up Comedian, Stay-at-home Parent, Tradie, Category Manager, Rideshare Driver |
| Race (floor 3) | Human, Elf, Dwarf, Hobgoblin, Bog Troll, Sentient Houseplant |
| Class (floor 3) | Brawler, Arcanist, Analyst, Alchemist, Beastmaster, Hype Man, Demolitionist, Quartermaster, Duellist |

The System AI's attitude is set by `SASS_LEVEL` in `crawler/config.py` (0-10, default 7).

Survive six floors to win.

### Dice and attributes

Combat works like a tabletop RPG, and every roll is shown in the log. An attack is a d20 plus your attack bonus against the target's Armour Class: `You hit the goblin for 6. (d20 14+4=18 vs AC 11)`. A natural 1 always misses and a natural 20 always crits (double damage dice). Weapons have damage dice: fists 1d4, frying pan 1d6, cleaver 1d8, katana 1d10. Bombs roll their dice and each monster makes a Dexterity save for half.

You have the five attributes from the books: Strength, Dexterity, Constitution, Intelligence and Charisma. Each sits around 10, and every 2 points above 10 is +1 to the rolls it governs. You start with 6 points to spend and get 2 more each level (`L` opens the attribute screen); your backstory, race and class nudge them too. Strength drives fists and blunt weapons, Dexterity drives Armour Class and blades, Constitution your HP, Intelligence your class skill, and Charisma your viewers and shop prices.

### Practice skills

Like the books, you get better at what you actually do. Twenty skills level up through use, from Stomping (squashing small monsters) and Pain Tolerance (getting hit and living) to Haggling, Power Napping and Pet Bonding. Each starts hidden as "???" until you first do the thing, then levels up to 15 with diminishing returns. Press `K` to see your levels, progress and what each level gives.

### Learning while you play

The game teaches a few ideas from probability and supply chains through the choices it asks you to make, not quizzes.

| Feature | What you do | The idea behind it |
|---|---|---|
| Loot box odds | Every box shows its drop table, expected value and spread before you open it | Probability distributions, expected value, standard deviation |
| Trade-ups and rerolls | Trade 3 boxes for 1 of the next tier, or pay to reroll what you got | Expected value vs variance, the house edge, when a gamble pays |
| Sponsor contracts | Accept or decline a deal for the next floor; the offer shows what it means in gold, viewers and danger, from your own run | Weighing return against risk; a good average can still go wrong |
| The shop | Buy and sell in safe rooms; stock, forecast demand, reorder points and deliveries are all on screen, and other crawlers buy too | Demand forecasting, safety stock, reorder points, lead time, stockouts |
| Fun facts | The System AI explains the maths when something happens: a miss streak, a loot drought, a bad trade | Gambler's fallacy, independence, survivorship bias |
| Run report | After a run, charts of damage by floor, your box luck against the average, and your viewer curve | Reading charts about your own play |

## Concepts from the books

| Concept | Status |
|---|---|
| Collapsing floors, stairwells, safe rooms | Phase 1 (done) |
| Loot boxes, achievements, sarcastic System AI, viewers, sponsor gifts | Phase 2 (done) |
| Companion pet, class choice on floor 3, bosses, crafting, save/load | Phase 3 (done) |
| Learning while playing: visible odds, gambles, sponsor deals, shop sim | Phase 4 (done) |
| Telemetry, bot player, analysis notebooks | Phase 5 (done) |
| Visible dice and attributes (STR, DEX, CON, INT, CHA), practice skills | Phase 6 (done) |
| Boss tiers (Opening Acts, Featured Acts, Headliners), achievement loot | Phase 6 (done) |
| First-person view with free look, Tab to switch, remembered in a settings file | Phase 7 (done) |
| Combat mode: initiative, a move, action and bonus action each turn, attacks of opportunity | Phase 7 (done) |

See [PHASES.md](PHASES.md) for progress.

## Code layout

`crawler/world.py` holds all game rules and has no pygame dependency, so tests (and later the bot) can play thousands of turns headless. `crawler/game.py` and `crawler/ui/` handle input and drawing. Monsters and balance numbers are data in `crawler/entities.py` and `crawler/config.py`; items, loot tables, achievements and announcer lines are data in `items.py`, `loot.py`, `achievements.py` and `showrunner.py`.

## Analysis

Every run you finish is logged to `runs/player_*.csv`. A headless bot plays thousands of runs for comparison:

```bash
pip install -r analysis/requirements.txt
python analysis/bot.py --runs 2000 --workers 4      # about 25 minutes on 4 cores; writes runs/bot_*.csv
jupyter lab analysis/                               # or open the notebooks on GitHub, outputs included
```

| Notebook | What it covers |
|---|---|
| [01 Run analysis](analysis/01_run_analysis.ipynb) | Outcomes, survival curves and per-floor hazard, causes of death, win rates with confidence intervals, a randomised experiment on sponsor deals, and reverse causality in practice skills |
| [02 Loot box statistics](analysis/02_loot_box_stats.ipynb) | Expected value and spread, a chi-square test of the stated odds and its power, the law of large numbers, the gambler's fallacy, pity timers, the house edge |
| [03 Shop forecasting](analysis/03_shop_forecasting.ipynb) | Forecast bias, MAE, WAPE vs MAPE on intermittent demand, backtesting methods, fill rate and cycle service level, the stock-vs-service frontier |
| [04 Predicting death](analysis/04_predict_death.ipynb) | Logistic regression vs gradient boosting, splitting by group, metrics for rare events, calibration, leakage, collinearity, permutation importance |

The committed data in `runs/` is 2,000 bot runs (the large events table is left out; regenerate it with the bot).

## Tests

```bash
python -m pytest -q
CRAWL_SCREENSHOTS=screenshots python -m pytest tests/test_render.py   # also saves PNGs of each screen
```
