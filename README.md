# Crawl Live!

A turn-based roguelike in Python + pygame, inspired by the *Dungeon Crawler Carl* books by Matt Dinniman. It borrows the books' core ideas (the dungeon as an alien game show, collapsing floors, safe rooms, loot boxes, a companion pet) but all names, characters and text are original.

## Play

```bash
git clone https://github.com/DarylHS/crawl-live.git
cd crawl-live
pip install -r requirements.txt
python main.py            # or: python main.py --seed 1234 for a reproducible run
```

| Key | Action |
|---|---|
| Arrows / WASD / numpad | Move; bump into a monster to attack |
| Numpad 7 9 1 3 | Move diagonally |
| `.` / Space / numpad 5 | Wait a turn |
| `>` / Enter | Descend a stairwell |
| `G` | Pick up items on your tile |
| `I` | Inventory: Enter uses/equips, `U` unequips, `D` drops |
| `R` | Rest to full HP (safe rooms only, costs floor time) |
| `M` | Safe-room menu: loot boxes (odds, open, trade up), shop, crafting, revive your pet, save |
| `R` | On a loot box reveal: hand the item back and reroll for a fee. On the end screen: run report |
| `Y` / `N` | Accept or decline a sponsor contract |
| `C` | Command your pet: follow / attack / stay |
| `K` | Practice skills: what you have levelled by doing it, and what each level gives |
| `1` | Use your class skill (from floor 3) |
| `L` | On the title screen: continue a saved run |
| `?` | Help |
| Esc | Back to title |

## How it plays

Each floor has a collapse timer (1 turn = 1 in-game minute). When it hits zero, the floor collapses and you die. Each floor has two stairwells, usually in the rooms furthest from where you start. One room per floor is a safe room (green): monsters can't enter it and nobody can fight inside it, and you can rest there to full HP if you're willing to spend the time. Monsters notice you when they come into your field of view and lose interest after a while out of sight. Kills and floor loot give you gear, potions and bombs. Achievements and sponsors (who send gifts as your viewer count grows) award loot boxes in five tiers, Bronze to Legendary, which can only be opened in a safe room. The System AI comments on everything you do, and your viewer count is your score.

You start by creating your crawler: a name, a gender (cosmetic; it changes how the System addresses you) and a backstory, then pick a companion: a vain cat, a loyal dog, a chatty budgie or a scheming, cowardly mouse. On floor 3 you choose a race and a class, each with a skill on key `1`. Every floor has an optional boss guarding its furthest stairwell; on the last floor the exits stay sealed until the final boss is dead. Safe rooms also have a crafting bench, the shop and a save point.

| Choice | Options |
|---|---|
| Backstory | Military Veteran, Mixologist, Dog Walker, Stand-up Comedian, Stay-at-home Parent, Tradie, Category Manager, Rideshare Driver |
| Race (floor 3) | Human, Elf, Dwarf, Hobgoblin, Bog Troll, Sentient Houseplant |
| Class (floor 3) | Brawler, Arcanist, Analyst, Alchemist, Beastmaster, Hype Man, Demolitionist, Quartermaster, Duellist |

The System AI's attitude is set by `SASS_LEVEL` in `crawler/config.py` (0-10, default 7).

Survive six floors to win.

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

See [PHASES.md](PHASES.md) for progress.

## Code layout

`crawler/world.py` holds all game rules and has no pygame dependency, so tests (and later the bot) can play thousands of turns headless. `crawler/game.py` and `crawler/ui/` handle input and drawing. Monsters and balance numbers are data in `crawler/entities.py` and `crawler/config.py`; items, loot tables, achievements and announcer lines are data in `items.py`, `loot.py`, `achievements.py` and `showrunner.py`.

## Analysis

Every run you finish is logged to `runs/player_*.csv`. A headless bot plays thousands of runs for comparison:

```bash
pip install -r analysis/requirements.txt
python analysis/bot.py --runs 2000 --workers 4      # about 6 minutes on 4 cores; writes runs/bot_*.csv
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
