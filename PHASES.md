# Build phases

This file is the hand-off between build sessions. Each session does the next unchecked phase, makes sure `python -m pytest -q` passes, ticks the phase off, adds notes below, commits and pushes to `claude/dungeon-crawler-game-6qy35n`. If a phase is left broken, the next session fixes that before starting anything new.

## Ground rules (apply to every phase)
- Original names and text only. The game is *inspired by* Dungeon Crawler Carl, so no character names, places or quotes from the books.
- Game rules belong in headless modules (`crawler/world.py` and friends, no pygame). pygame code stays in `crawler/game.py` and `crawler/ui/`.
- Content is data (lists/dicts) so new items, achievements and lines can be added without code changes. Ship the starter set; don't over-build content.
- Australian spelling in player-facing text (defence, colour, armour).
- Every new system gets pytest coverage. Rendering gets a headless draw test in `tests/test_render.py`.
- Keep the game playable at the end of every phase.

## Checklist

- [x] **Phase 1: Core crawl.** Dungeon generation, FOV, movement, bump combat, monster AI, levelling, collapse timer, stairwells, safe rooms (rest), 6 floors, title/help/death/victory screens.
- [x] **Phase 2: Loot & show.**
  - Items (~15: 3 weapons, 3 armour, potions, bombs, junk), inventory screen (`i`), equip/use/drop, pick up (`g`), items on the floor.
  - Loot boxes: 5 tiers (Bronze, Silver, Gold, Platinum, Legendary), ~4 items each, weighted roll tables in `crawler/loot.py`. Boxes are opened only in safe rooms, with a reveal screen.
  - Achievements (`crawler/achievements.py`): subscribe to the existing `EventBus`; 8 starter achievements, each awarding a tiered box. Show a toast when one triggers.
  - Showrunner (`crawler/showrunner.py`): System AI announcer with ~5 snarky lines per event type, a viewer count that rises with entertaining play (multi-kills, clutch survival on low HP, kills, descending with little time left) and decays when idle. Viewer thresholds trigger sponsor gift boxes. Viewer count goes on the HUD and the death/victory screens as the score.
  - Safe-room menu (open boxes, rest, later shop/crafting/save).
- [ ] **Phase 3: Pet & depth.**
  - Companion pet: pick from 2 species at the start and name it. Own stats and XP, follow/stay/attack commands (`c`), one ability each, chimes in through the announcer. If downed, it can be revived in a safe room.
  - Race/class choice when reaching floor 3 (3 classes x 2 races, one skill each on `1`-`3`). One of the classes must be **Analyst**, whose skill shows enemy hit chance and expected damage using `combat.hit_chance` / `combat.expected_damage` (needed in Phase 4).
  - A boss on each floor guarding the stairs or holding a key, with a multi-phase final boss on floor 6. Victory requires beating it.
  - Crafting bench in safe rooms (4 recipes, e.g. junk into bombs or potions).
  - Save/load (JSON in `saves/`) from safe rooms only; round-trip test.
  - Ranged monster AI (deferred from Phase 1).
- [ ] **Phase 4: Learn while playing.** (No quizzes or blocking pop-ups; the learning comes from decisions and the announcer.)
  - Odds disclosure: each loot box shows its real drop table before opening.
  - Box gambles: trade 3 lower boxes for 1 higher one, or reroll a box for a fee. Show EV and variance.
  - Sponsor contracts: offers like "+20% gold, but monsters hit 10% harder this floor"; accept or decline.
  - Shop sim in safe rooms: stock forecast from crawler demand, reorder points, stockouts and price changes, with stock carried between floors.
  - System AI "Fun Facts": stats one-liners triggered by real events (gambler's fallacy after a losing streak, base rates, independence).
  - Post-run report screen: damage taken by floor, box EV realised vs expected, viewer curve.
- [ ] **Phase 5: Analysis & balance.**
  - `crawler/telemetry.py`: subscribe to `"*"` on the EventBus and write tidy CSV (`runs/*.csv`: run_id, turn, floor, event, value columns).
  - `analysis/bot.py`: headless bot (see the notes on the Phase 1 balance probe below); generate ~2,000 runs.
  - Notebooks in `analysis/`: `01_run_analysis.ipynb` (EDA, survival by floor, viewer growth, causes of death), `02_loot_box_stats.ipynb` (EV per tier, chi-square test of observed vs stated rates, pity timers), `03_shop_forecasting.ipynb` (MAPE, bias, stockouts vs safety stock), `04_predict_death.ipynb` (scikit-learn classifier, train/test split by run to avoid leakage, feature importance). All must run with `jupyter nbconvert --execute`.
  - Balance pass using the bot's data; final README update.

## Notes from finished phases

### Phase 1
- The plan's `game.py` "state machine" is split in two: headless rules in `crawler/world.py` (`World`) and the pygame front end in `crawler/game.py` (`App`). Keep that split.
- Events already emitted: `floor_start`, `player_hit`, `kill`, `level_up`, `damage_taken`, `player_death`, `descend`, `victory`, `rest`, `timer_warning`. Phase 2 systems should subscribe rather than add calls into `World`.
- Floor timer: 1 turn = 1 minute, 720 turns on floor 1 plus 60 per floor after that (`config.floor_turns`). Resting heals 1 HP a turn and stops with 60 turns left.
- Monster pathing uses one BFS distance map from the player per turn (`Floor.distance_map`), with safe tiles excluded.
- Balance probe (`analysis/balance_probe.py`: a bot that explores, fights what it sees, rests when hurt, then takes the stairs), 200 seeds with no items: about 4% win; deaths spread over floors 2-5; timer collapses about 2% per floor. Starting HP was raised to 36 and regen set to 1 HP per 7 turns. Expect a retune once items and potions exist.
- All monsters are melee for now; ranged AI is deferred to Phase 3.

### Phase 2
- New modules (all headless): `items.py` (15 items as data: 3 weapons, 3 armour, 3 potions, 2 bombs, 4 junk; `FLOOR_LOOT` table; `describe()`), `loot.py` (`BOX_TIERS`, `TIERS`, `odds(tier)` giving exact probabilities for Phase 4's odds disclosure, `roll_box`), `achievements.py` (`ACHIEVEMENTS` data, 8 starters, each awards a box), `showrunner.py` (`LINES`, `SPONSOR_GIFTS`, viewer logic). UI: `ui/menus.py` (inventory, safe-room menu, box reveal).
- `World` now owns `inventory` (keys, max `C.INVENTORY_SIZE`=16), `equipment` {weapon, armour}, `boxes` (list of tier strings), `floor_items` {(x, y): [keys]}, `toasts`, `last_reveal`, `achievements`, `showrunner`, `viewers` (property). Actions: `pickup()` (takes a turn), `drop(i)`, `equip(i)`, `unequip(slot)` (free), `use_item(i)` (potion/bomb take a turn; equip is free), `add_box(tier, source)`, `open_box(tier)` (safe room only, needs a free pack slot).
- Equipment applies flat bonuses straight onto the player's stats, so `combat.hit_chance` / `expected_damage` already include gear (the Phase 3 Analyst skill needs nothing extra).
- Bombs hit the nearest visible monster within `C.BOMB_RANGE` and everything within the item's `radius` of it, ignoring defence. Monsters have a `C.ITEM_DROP_CHANCE` of dropping floor loot; each non-start room has a `C.FLOOR_ITEM_CHANCE` of holding one item.
- Loot rolls use `world.loot_rng` and the announcer uses its own RNG, so neither perturbs dungeon generation for a given seed.
- Events added: `turn` (every clock tick, data `turn`), `item_pickup`, `item_drop`, `item_use`, `equip`, `unequip`, `bomb` (`kills`), `box_gained` (`tier`, `source`: achievement/sponsor), `box_opened` (`tier`, `item`), `achievement` (`key`, `title`, `tier`), `sponsor_gift` (`tier`, `sponsor`). `kill` gained a `by` field ("melee"/"bomb"). Note `emit(name, **data)` means a payload can't use `name` as a key. Telemetry (Phase 5) should expect `turn` to be frequent.
- Viewers: start 50. Kill = 5 + 2 x monster XP, +25 per extra kill within 4 turns, +60 for a kill at 25% HP or less; level up +40; achievement +50; descend +30 (+100 under 25% timer). Decays 3% per 10 idle turns (floor 20), so long rests cost viewers. Sponsor boxes at 300/700/1500/3000/6000 viewers (Bronze to Legendary). The announcer only speaks on some kills and on damage when HP is under 40%. `Showrunner.history` records (turn, viewers) at each floor start, and `peak` is tracked, for the Phase 4 report screen.
- Keys: `G` pick up, `I` inventory (Enter use/equip, `U` unequip, `D` drop), `M` safe-room menu (rest, open boxes), `R` still rests directly. The menu has room for shop/crafting/save entries via `menus.menu_options`.
- Balance probe now equips the best gear, drinks potions under 45% HP, throws bombs at crowds and big monsters, picks up non-junk items and opens boxes in safe rooms. 100 seeds: about 46% win (was about 4% without items); deaths mostly floor 5 (16%) and spread over floors 2-6; collapses about 7% total. Viewers median about 1,000, p90 about 1,900; Gold and above sponsor boxes are rare for this bot. `cutting_it_fine` never fired (the bot descends early). The probe takes about 2.5s per run.
- Deferred: the bot is a competent item user, so 46% is likely generous for a human, but a proper retune waits for the Phase 5 bot and data (candidates: item frequency, potion strength, viewer thresholds). Junk has no use yet (Phase 3 crafting). Box odds are not yet shown in the UI (Phase 4).
