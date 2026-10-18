# Crawl Live!

A turn-based roguelike in Python + pygame, inspired by the *Dungeon Crawler Carl* books by Matt Dinniman. It borrows the books' core ideas (the dungeon as an alien game show, collapsing floors, safe rooms, loot boxes, a companion pet) but all names, characters and text are original.

## Play

```bash
cd dungeon-crawler
pip install -r requirements.txt
python main.py            # or: python main.py --seed 1234 for a reproducible run
```

| Key | Action |
|---|---|
| Arrows / WASD / numpad | Move; bump into a monster to attack |
| Numpad 7 9 1 3 | Move diagonally |
| `.` / Space / numpad 5 | Wait a turn |
| `>` / Enter | Descend a stairwell |
| `R` | Rest to full HP (safe rooms only, costs floor time) |
| `?` | Help |
| Esc | Back to title |

## How it plays

Each floor has a collapse timer (1 turn = 1 in-game minute). When it hits zero, the floor collapses and you die. Each floor has two stairwells, usually in the rooms furthest from where you start. One room per floor is a safe room (green): monsters can't enter it and nobody can fight inside it, and you can rest there to full HP if you're willing to spend the time. Monsters notice you when they come into your field of view and lose interest after a while out of sight. Survive six floors to win.

## Concepts from the books

| Concept | Status |
|---|---|
| Collapsing floors, stairwells, safe rooms | Phase 1 (done) |
| Loot boxes, achievements, sarcastic System AI, viewers, sponsors | Phase 2 |
| Companion pet, class choice on floor 3, bosses, crafting, save/load | Phase 3 |
| Learning while playing: visible odds, gambles, sponsor deals, shop sim | Phase 4 |
| Telemetry, bot player, analysis notebooks | Phase 5 |

See [PHASES.md](PHASES.md) for progress.

## Code layout

`crawler/world.py` holds all game rules and has no pygame dependency, so tests (and later the bot) can play thousands of turns headless. `crawler/game.py` and `crawler/ui/` handle input and drawing. Monsters and balance numbers are data in `crawler/entities.py` and `crawler/config.py`.

## Tests

```bash
cd dungeon-crawler
python -m pytest -q
CRAWL_SCREENSHOTS=screenshots python -m pytest tests/test_render.py   # also saves PNGs of each screen
```
