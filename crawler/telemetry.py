"""Run telemetry: turns one game into tidy tables for analysis.

Attach a Telemetry to a World as soon as it's created. At the end of the run,
tables() returns plain lists of dicts:

  runs    one row per run: who played, how it ended, totals
  floors  one row per floor reached: the player's state on arrival, what
          happened there and how the floor ended (the unit for death models)
  boxes   one row per loot box opened
  shop    one row per shop item per floor turnover
  events  one row per game event (run_id, turn, floor, event, value, detail),
          the long format for anything the other tables don't cover

write_tables() appends them to CSVs in a folder (default runs/). The game
logs your own runs there with source "player"; analysis/bot.py logs "bot".
"""
import csv
import os
import uuid
from pathlib import Path

from .attributes import ATTRS
from .dice import average
from .items import ITEMS

RUNS_DIR = Path(__file__).resolve().parents[1] / "runs"
SKIP = {"turn"}                     # every tick; the viewer samples cover it
VALUE_KEYS = ("damage", "amount", "xp", "healed", "price", "kills", "level", "turns",
              "timer_left", "chance", "fee", "phase", "depth")
DETAIL_KEYS = ("monster", "item", "tier", "contract", "skill", "cause", "source", "ability",
               "recipe", "slot", "to", "boss", "cls", "attr")


class Telemetry:
    def __init__(self, world, source="player", run_id=None, meta=None):
        self.world, self.source = world, source
        self.run_id = run_id or uuid.uuid4().hex[:12]
        self.meta = meta or {}
        self.events, self.arrivals = [], []
        world.events.subscribe("*", self._on_event)
        world.events.subscribe("floor_start", lambda n, d: self._arrive())
        self._arrive()                  # floor 1 started before we subscribed

    def _arrive(self):
        w, p = self.world, self.world.player
        kinds = [ITEMS[k]["kind"] for k in w.inventory]
        pet = w.pet
        self.arrivals.append(dict(
            depth=w.depth, turn=w.turn, hp=p.hp, max_hp=p.max_hp, hp_frac=round(p.hp / p.max_hp, 3),
            level=p.level, **{a: w.score(a) for a in ATTRS}, attack=p.attack, ac=p.ac,
            dmg_avg=average(p.dmg_n, p.dmg_die, p.dmg_bonus), potions=kinds.count("potion"), bombs=kinds.count("bomb"),
            gold=w.gold, boxes=len(w.boxes), cls=w.cls or "none", race=w.race or "none",
            backstory=w.backstory or "none",
            pet=pet.species if pet else "none", pet_level=pet.level if pet else 0,
            pet_down=bool(pet and pet.downed), timer_max=w.timer_max, viewers=w.viewers))

    def _on_event(self, name, d):
        if name in SKIP:
            return
        value = next((d[k] for k in VALUE_KEYS if isinstance(d.get(k), (int, float))
                      and not isinstance(d.get(k), bool)), "")
        detail = next((str(d[k]) for k in DETAIL_KEYS if d.get(k) not in (None, "")), "")
        self.events.append(dict(run_id=self.run_id, turn=self.world.turn, floor=self.world.depth,
                                event=name, value=value, detail=detail))

    def tables(self):
        w, p = self.world, self.world.player
        ended = w.state != "playing"
        cause = w.death_cause or ""
        outcome = "victory" if w.state == "victory" else (
            "collapse" if "collapsed" in cause else "killed" if w.state == "dead" else "unfinished")
        run = dict(run_id=self.run_id, source=self.source, seed=w.seed,
                   pet=w.pet.species if w.pet else "none", race=w.race or "none",
                   backstory=w.backstory or "none", gender=w.gender or "none",
                   cls=w.cls or "none", outcome=outcome, depth=w.depth, turns=w.turn,
                   kills=p.kills, level=p.level, gold=sum(f["gold"] for f in w.floor_stats),
                   viewers=w.viewers, peak_viewers=w.showrunner.peak, boxes=len(w.box_log),
                   achievements=len(w.achievements.unlocked),
                   practice_levels=sum(w.training.levels.values()), death_cause=cause, **self.meta)
        floors = []
        by_depth = {f["depth"]: f for f in w.floor_stats}
        for a in self.arrivals:
            f = by_depth.get(a["depth"], {})
            last = a["depth"] == w.depth and a is self.arrivals[-1]
            result = outcome if (last and ended) else ("unfinished" if last else "cleared")
            floors.append(dict(run_id=self.run_id, source=self.source, **a,
                               contract=f.get("contract") or "none",
                               damage_taken=f.get("damage_taken", 0), gold_earned=f.get("gold", 0),
                               kills_here=f.get("kills", 0),
                               viewers_gained=f.get("viewers_end", 0) - f.get("viewers_start", 0),
                               result=result, died_here=int(result in ("killed", "collapse"))))
        boxes = [dict(run_id=self.run_id, source=self.source, **b) for b in w.box_log]
        shop = [dict(run_id=self.run_id, source=self.source, **r) for r in w.shop.log]
        practice = [dict(run_id=self.run_id, source=self.source, skill=k, level=w.training.levels[k],
                         used=int(k in w.training.used)) for k in w.training.levels]
        return dict(runs=[run], floors=floors, boxes=boxes, shop=shop, practice=practice,
                    events=self.events)


def write_tables(tables, out_dir=RUNS_DIR, prefix="", skip=()):
    """Append each table to <out_dir>/<prefix><name>.csv, writing a header for new files."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, rows in tables.items():
        if name in skip or not rows:
            continue
        path = out_dir / f"{prefix}{name}.csv"
        new = not path.exists() or os.path.getsize(path) == 0
        with path.open("a", newline="") as fh:
            writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
            if new:
                writer.writeheader()
            writer.writerows(rows)
