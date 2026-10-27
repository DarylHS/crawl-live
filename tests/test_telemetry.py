"""Telemetry tables and the bot that generates them."""
import csv
import sys
from pathlib import Path

import pygame

from crawler import config as C
from crawler.telemetry import Telemetry, write_tables
from crawler.world import World

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "analysis"))
from bot import play  # noqa: E402


def test_bot_run_produces_consistent_tables():
    w, t = play(3, telemetry=True)
    run = t["runs"][0]
    assert run["outcome"] in ("victory", "killed", "collapse")
    floors = t["floors"]
    assert [f["depth"] for f in floors] == list(range(1, w.depth + 1))
    assert sum(f["died_here"] for f in floors) == (run["outcome"] != "victory")
    assert all(f["result"] == "cleared" for f in floors[:-1])
    assert len(t["boxes"]) == len(w.box_log)
    events = {e["event"] for e in t["events"]}
    assert "kill" in events and ("floor_start" in events or w.depth == 1)
    assert "turn" not in {e["event"] for e in t["events"]}


def test_bot_is_deterministic():
    a, ta = play(5, telemetry=True)
    b, tb = play(5, telemetry=True)
    assert ta["runs"] == tb["runs"] and ta["floors"] == tb["floors"]


def test_write_tables_appends_with_one_header(tmp_path):
    for seed in (1, 2):
        w = World(seed)
        tel = Telemetry(w, source="test", run_id=f"r{seed}")
        w._kill_player("test")
        write_tables(tel.tables(), tmp_path, prefix="t_")
    with (tmp_path / "t_runs.csv").open() as fh:
        rows = list(csv.DictReader(fh))
    assert [r["run_id"] for r in rows] == ["r1", "r2"]


def test_game_logs_finished_player_runs(tmp_path):
    from crawler.game import App
    pygame.init()
    app = App(screen=pygame.Surface((C.SCREEN_W, C.SCREEN_H)), seed=2, runs_dir=tmp_path,
              settings_path=None)
    ev = lambda k: pygame.event.Event(pygame.KEYDOWN, key=k, unicode="", mod=0)
    for _ in range(4):
        app.handle_key(ev(pygame.K_RETURN))
    app.world.timer = 1
    app.handle_key(ev(pygame.K_PERIOD))                  # the floor collapses
    assert app.world.state == "dead"
    with (tmp_path / "player_runs.csv").open() as fh:
        rows = list(csv.DictReader(fh))
    assert len(rows) == 1 and rows[0]["outcome"] == "collapse" and rows[0]["source"] == "player"
    app.handle_key(ev(pygame.K_PERIOD))                  # no second write
    with (tmp_path / "player_runs.csv").open() as fh:
        assert len(list(csv.DictReader(fh))) == 1
    pygame.quit()
