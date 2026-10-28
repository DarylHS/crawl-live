"""Self-test of the parity trace tooling (plan S9): determinism, self-diff, perturbed diff,
and that tracing does not change the game."""
import json
import random
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import crawler.world as cw  # noqa: E402
import parity_diff as PD  # noqa: E402
import py_trace as PT  # noqa: E402


def trace(path, seed=3, policy="hunter", steps=300, **kw):
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        w = PT.run_trace(seed, policy, steps, fh, **kw)
    return w


def lines(path):
    return Path(path).read_text(encoding="utf-8").splitlines()


def test_counting_random_matches_plain_random():
    a, b = random.Random(123), PT.CountingRandom(123)
    for _ in range(50):
        assert a.random() == b.random()
        assert a.randint(1, 20) == b.randint(1, 20)
        assert a.choices("abc", (1, 2, 3)) == b.choices("abc", (1, 2, 3))
        assert a.uniform(0.6, 1.4) == b.uniform(0.6, 1.4)
    xs, ys = list(range(10)), list(range(10))
    a.shuffle(xs)
    b.shuffle(ys)
    assert xs == ys and a.sample(range(100), 7) == b.sample(range(100), 7)
    assert a.getstate() == b.getstate()
    assert b.words > 0
    c = PT.CountingRandom(1)
    c.random()
    assert c.words == 2
    c.getrandbits(5)
    assert c.words == 3
    c.getrandbits(33)
    assert c.words == 5
    c.getrandbits(0)
    assert c.words == 5


def test_hooks_are_restored(tmp_path):
    orig = (cw.EventBus, cw.MessageLog, cw.World.new_floor, random.Random)
    trace(tmp_path / "a.jsonl", steps=20)
    assert (cw.EventBus, cw.MessageLog, cw.World.new_floor, random.Random) == orig


@pytest.mark.parametrize("policy", ["walk", "hunter", "bot"])
def test_determinism_and_self_diff(tmp_path, policy):
    a, b = tmp_path / "a.jsonl", tmp_path / "b.jsonl"
    trace(a, seed=4, policy=policy, steps=250)
    trace(b, seed=4, policy=policy, steps=250)
    assert a.read_bytes() == b.read_bytes()
    res = PD.compare_files(a, b)
    assert res.ok and res.report.startswith("PARITY OK") and res.turns > 0
    first = json.loads(lines(a)[0])
    assert first["k"] == "header" and first["impl"] == "python" and first["policy"] == policy
    assert json.loads(lines(a)[-1])["k"] == "end"


def test_record_kinds_and_stream_order(tmp_path):
    p = tmp_path / "a.jsonl"
    trace(p, seed=7, policy="bot", steps=400)
    recs = [json.loads(x) for x in lines(p)]
    kinds = {r["k"] for r in recs}
    assert {"header", "ev", "turn", "floor", "act", "msg", "end"} <= kinds
    evs = [r for r in recs if r["k"] == "ev"]
    assert [e["i"] for e in evs] == list(range(1, len(evs) + 1))
    assert evs[0]["e"] == "floor_start" and len(evs[0]["r"]) == 5
    # the per-stream word counters never go backwards
    for prev, cur in zip(evs, evs[1:]):
        assert all(y >= x for x, y in zip(prev["r"], cur["r"]))
    # a turn record directly follows its "turn" event
    for i, r in enumerate(recs):
        if r["k"] == "ev" and r["e"] == "turn":
            assert recs[i + 1]["k"] == "turn" and recs[i + 1]["t"] == r["p"]["turn"]


def test_perturbed_copy_fails_at_the_right_turn(tmp_path):
    a, b = tmp_path / "a.jsonl", tmp_path / "b.jsonl"
    trace(a, seed=5, policy="walk", steps=200)
    recs = [json.loads(x) for x in lines(a)]
    idx = [i for i, r in enumerate(recs) if r["k"] == "turn" and r["t"] == 40][0]
    recs[idx]["hp"] += 1
    b.write_text("\n".join(json.dumps(r) for r in recs) + "\n", encoding="utf-8")
    res = PD.compare_files(a, b, context=3)
    assert not res.ok
    assert f"record {idx}" in res.report and "[.hp]" not in res.report and ".hp" in res.report
    assert "after turn 40" in res.report or "turn 39" in res.report
    # CLI exit codes
    cli = [sys.executable, str(ROOT / "scripts" / "parity_diff.py")]
    assert subprocess.run(cli + [str(a), str(a)], capture_output=True).returncode == 0
    bad = subprocess.run(cli + [str(a), str(b)], capture_output=True, text=True)
    assert bad.returncode == 1 and "PARITY FAIL" in bad.stdout


def test_rng_counter_delta_reported(tmp_path):
    a, b = tmp_path / "a.jsonl", tmp_path / "b.jsonl"
    trace(a, seed=5, policy="hunter", steps=150)
    recs = [json.loads(x) for x in lines(a)]
    idx = [i for i, r in enumerate(recs) if r["k"] == "ev" and r["e"] == "step"][3]
    recs[idx]["r"][0] += 2
    b.write_text("\n".join(json.dumps(r) for r in recs) + "\n", encoding="utf-8")
    res = PD.compare_files(a, b)
    assert not res.ok and "RNG word delta" in res.report and "[2, 0, 0, 0, 0]" in res.report


def test_truncated_trace_and_number_tolerance(tmp_path):
    a, b = tmp_path / "a.jsonl", tmp_path / "b.jsonl"
    trace(a, seed=2, policy="walk", steps=60)
    ls = lines(a)
    b.write_text("\n".join(ls[:-3]) + "\n", encoding="utf-8")
    assert not PD.compare_files(a, b).ok
    assert PD.values_equal(1, 1.0)[0] and not PD.values_equal(True, 1)[0]
    assert PD.values_equal({"a": 1, "b": 2}, {"b": 2.0, "a": 1})[0]


def test_core_scope_ignores_messages_and_show_stream(tmp_path):
    a, b = tmp_path / "a.jsonl", tmp_path / "b.jsonl"
    trace(a, seed=6, policy="walk", steps=120)
    recs = [json.loads(x) for x in lines(a)]
    out = []
    for r in recs:
        if r["k"] == "msg":
            continue
        if r["k"] == "ev":
            r["r"][4] += 7
            r["i"] += 100
        if r["k"] == "turn":
            r["viewers"] += 1
        out.append(r)
    b.write_text("\n".join(json.dumps(r) for r in out) + "\n", encoding="utf-8")
    assert PD.compare_files(a, b, scope="core").ok
    assert not PD.compare_files(a, b, scope="full").ok


def test_core_scope_ignores_showmanship_training(tmp_path):
    def ev(skill, many):
        return {"k": "ev", "i": 1, "t": 3, "d": 1, "e": "practice_level",
                "p": {"skill": skill, "level": 1, "title": "X", "many_at_3": many}, "r": [1, 0, 0, 0, 0]}
    other = {"k": "ev", "i": 2, "t": 3, "d": 1, "e": "step", "p": {"sneaky": False}, "r": [1, 0, 0, 0, 0]}
    a, b = tmp_path / "a.jsonl", tmp_path / "b.jsonl"
    a.write_text("\n".join(json.dumps(r) for r in [ev("showmanship", 0), ev("sneaking", 1), other]) + "\n")
    b.write_text("\n".join(json.dumps(r) for r in [ev("sneaking", 2), other]) + "\n")
    assert PD.compare_files(a, b, scope="core").ok          # showmanship dropped, many_at_3 ignored
    assert not PD.compare_files(a, b, scope="full").ok
    c = tmp_path / "c.jsonl"
    c.write_text("\n".join(json.dumps(r) for r in [ev("dodging", 1), other]) + "\n")
    assert not PD.compare_files(b, c, scope="core").ok      # a different skill still differs


def test_dirs_mode(tmp_path):
    da, db = tmp_path / "A", tmp_path / "B"
    for d in (da, db):
        PT.main(["--seeds", "0-2", "--policy", "walk", "--steps", "60", "--out-dir", str(d)])
    ok, text = PD.compare_dirs(da, db, (0, 2))
    assert ok and "3/3 traces identical" in text
    bad = (db / "walk_1.jsonl")
    ls = lines(bad)
    r = json.loads(ls[-1])
    r["turn"] += 1
    bad.write_text("\n".join(ls[:-1] + [json.dumps(r)]) + "\n", encoding="utf-8")
    ok, text = PD.compare_dirs(da, db, (0, 2))
    assert not ok and "walk_1.jsonl: FAIL" in text and "2/3" in text
    ok, _ = PD.compare_dirs(da, db, (0, 0))
    assert ok
    (db / "walk_2.jsonl").unlink()
    ok, text = PD.compare_dirs(da, db, (2, 2))
    assert not ok and "MISSING" in text


def test_tracing_does_not_change_the_game(tmp_path):
    from analysis import bot
    for seed in (1, 9):
        steps = 500
        plain, _ = bot.play(seed, max_steps=steps)
        traced = trace(tmp_path / f"b{seed}.jsonl", seed=seed, policy="bot", steps=steps)
        for attr in ("turn", "depth", "state", "death_cause", "gold", "viewers"):
            assert getattr(plain, attr) == getattr(traced, attr), attr
        assert (plain.player.x, plain.player.y, plain.player.hp) == \
               (traced.player.x, traced.player.y, traced.player.hp)
        assert [m.key for m in plain.monsters] == [m.key for m in traced.monsters]
        assert plain.rng.getstate() == traced.rng.getstate()
        assert plain.loot_rng.getstate() == traced.loot_rng.getstate()
        assert plain.showrunner.rng.getstate() == traced.showrunner.rng.getstate()


def test_floor_only_mode(tmp_path):
    from crawler.dungeon import generate_floor
    p = tmp_path / "f.jsonl"
    with open(p, "w", encoding="utf-8") as fh:
        PT.run_floors(11, 3, False, fh)
    recs = [json.loads(x) for x in lines(p)]
    assert recs[0]["mode"] == "floors" and [r["depth"] for r in recs[1:]] == [1, 2, 3]
    rng = random.Random(11)
    f1 = generate_floor(rng, 1)
    assert recs[1]["fp"] == PT.floor_fp(f1)
    assert len(recs[1]["tiles"]) == f1.height and len(recs[1]["tiles"][0]) == f1.width
    assert recs[1]["words"] > 0 and recs[1]["words"] < recs[2]["words"]
    pw = tmp_path / "w.jsonl"
    with open(pw, "w", encoding="utf-8") as fh:
        PT.run_floors(11, 2, True, fh)
    wr = [json.loads(x) for x in lines(pw)]
    assert wr[0]["mode"] == "floors_world" and [r["depth"] for r in wr[1:]] == [1, 2]
    assert wr[1]["monsters"] and "items" in wr[1] and len(wr[1]["rs"]) == 5
    # determinism
    pw2 = tmp_path / "w2.jsonl"
    with open(pw2, "w", encoding="utf-8") as fh:
        PT.run_floors(11, 2, True, fh)
    assert pw.read_bytes() == pw2.read_bytes()


def test_pet_and_hero_options(tmp_path):
    p = tmp_path / "p.jsonl"
    trace(p, seed=8, policy="hunter", steps=120, pet="cat",
          hero=dict(name="Bot", gender="female", backstory="veteran"))
    head = json.loads(lines(p)[0])
    assert head["pet"] == "cat" and head["hero"]["backstory"] == "veteran"
    assert any(json.loads(x)["k"] == "turn" and json.loads(x)["pet"] for x in lines(p))


def test_malformed_and_missing_files_fail_cleanly(tmp_path):
    a, bad = tmp_path / "a.jsonl", tmp_path / "bad.jsonl"
    trace(a, seed=2, policy="walk", steps=30)
    ls = lines(a)
    bad.write_text("\n".join(ls[:5] + ["{not json"] + ls[5:]) + "\n", encoding="utf-8")
    res = PD.compare_files(a, bad)
    assert not res.ok and "line 6 malformed" in res.report
    res = PD.compare_files(a, tmp_path / "nope.jsonl")
    assert not res.ok and "missing" in res.report
    cli = [sys.executable, str(ROOT / "scripts" / "parity_diff.py")]
    r = subprocess.run(cli + [str(a), str(bad)], capture_output=True, text=True)
    assert r.returncode == 1 and "Traceback" not in r.stderr
    da, db = tmp_path / "A", tmp_path / "B"
    for d in (da, db):
        PT.main(["--seeds", "0-1", "--policy", "walk", "--steps", "30", "--out-dir", str(d)])
    (db / "walk_0.jsonl").write_text("garbage\n", encoding="utf-8")
    ok, text = PD.compare_dirs(da, db)
    assert not ok and "1/2 traces identical" in text


def test_non_rng_divergence_shows_last_counters(tmp_path):
    a, b = tmp_path / "a.jsonl", tmp_path / "b.jsonl"
    trace(a, seed=5, policy="walk", steps=100)
    recs = [json.loads(x) for x in lines(a)]
    idx = [i for i, r in enumerate(recs) if r["k"] == "turn"][5]
    recs[idx]["gold"] += 1
    b.write_text("\n".join(json.dumps(r) for r in recs) + "\n", encoding="utf-8")
    assert "last ev RNG counters" in PD.compare_files(a, b).report


def test_pet_none_option(tmp_path):
    p = tmp_path / "p.jsonl"
    trace(p, seed=1, policy="bot", steps=20, pet="none")
    assert json.loads(lines(p)[0])["pet"] is None



def test_mute_lists_reject_unknown_names(capsys):
    import chaos_trace as CT
    assert CT.parse_mute("funfacts") == {"funfacts"} and CT.parse_mute("none") == set()
    assert CT.parse_mute("all") == set(CT.SUBSYSTEMS) == {"showrunner", "funfacts"}
    with pytest.raises(SystemExit):
        CT.parse_mute("achievements")
    with pytest.raises(SystemExit):
        CT.parse_mute("funfacts,bogus")
    with pytest.raises(SystemExit):
        PT.main(["--seed", "1", "--policy", "walk", "--steps", "5", "--mute", "achievements", "--out", "/dev/null"])


def test_chaos_trace_mutes_only_the_named_subsystems(tmp_path):
    import chaos_trace as CT
    outs = {}
    for name, mute in (("all", "all"), ("fun", "funfacts")):
        outs[name] = tmp_path / f"{name}.jsonl"
        CT.run(3, 200, str(outs[name]), CT.parse_mute(mute))

    def events(path):
        return [e[0] for line in lines(path) for e in json.loads(line)[-2]]
    assert "achievement" in events(outs["fun"]) and "achievement" in events(outs["all"])
    assert "viewers_gained" in events(outs["fun"]) and "viewers_gained" not in events(outs["all"])
    assert "fun_fact" not in events(outs["fun"])

# --- CSV compare mode (slice T4) and the chaos telemetry mode ---------------------------------------

def _csv_pair(tmp_path, text_a, text_b, name="t_runs.csv"):
    da, db = tmp_path / "A", tmp_path / "B"
    for d, text in ((da, text_a), (db, text_b)):
        d.mkdir(parents=True)
        (d / name).write_bytes(text.encode("utf-8"))
    return da, db


def test_csv_mode_identical_files(tmp_path):
    da, db = _csv_pair(tmp_path, "a,b\r\n1,x\r\n2,y\r\n", "a,b\r\n1,x\r\n2,y\r\n")
    ok, text = PD.compare_csv_dirs(da, db)
    assert ok and text == "CSV OK: 1 files, 3 rows, byte-identical"
    assert PD.main(["--csv", str(da), str(db)]) == 0


def test_csv_mode_byte_difference_is_reported_separately(tmp_path):
    # same cells by value, different bytes: float text and line endings
    da, db = _csv_pair(tmp_path, "a,b\r\n1,0.00001\r\n", "a,b\n1.0,1e-05\n")
    ok, text = PD.compare_csv_dirs(da, db)
    assert not ok and "t_runs.csv: BYTES DIFFER" in text and "cells agree; first byte difference" in text
    assert "CELLS DIFFER" not in text
    ok, text = PD.compare_csv_dirs(da, db, cells_only=True)
    assert ok and "cells identical (1 files differ in bytes)" in text
    assert PD.main(["--csv", str(da), str(db)]) == 1
    assert PD.main(["--csv", str(da), str(db), "--cells-only"]) == 0


def test_csv_mode_cell_differences_name_file_row_and_column(tmp_path, capsys):
    da, db = _csv_pair(tmp_path, "id,hp,note\r\n1,5,ok\r\n2,7,fine\r\n", "id,hp,note\r\n1,5,ok\r\n2,8,fine!\r\n")
    ok, text = PD.compare_csv_dirs(da, db)
    assert not ok and "CELLS DIFFER" in text
    assert "row 2 column hp: A '7' B '8'" in text and "row 2 column note: A 'fine' B 'fine!'" in text
    assert "CSV FAIL: 1 of 1 files differ" in text
    assert PD.main(["--csv", str(da), str(db), "--cells-only"]) == 1       # a wrong cell always fails
    assert "row 2 column hp" in capsys.readouterr().out


def test_csv_mode_structure_differences(tmp_path):
    ok, text = PD.compare_csv_dirs(*_csv_pair(tmp_path / "h", "a,b\r\n1,2\r\n", "a,c\r\n1,2\r\n"))
    assert not ok and "header differs" in text
    ok, text = PD.compare_csv_dirs(*_csv_pair(tmp_path / "r", "a,b\r\n1,2\r\n3,4\r\n", "a,b\r\n1,2\r\n"))
    assert not ok and "row count differs: A 3 B 2" in text
    ok, text = PD.compare_csv_dirs(*_csv_pair(tmp_path / "w", "a,b\r\n1,2\r\n", "a,b\r\n1,2,3\r\n"))
    assert not ok and "2 cells in A, 3 in B" in text


def test_csv_mode_quoted_cells_and_text_cells_compare_exactly(tmp_path):
    same = 'a,b\r\n"x, ""y""",True\r\n'
    ok, _ = PD.compare_csv_dirs(*_csv_pair(tmp_path / "s", same, same))
    assert ok
    ok, text = PD.compare_csv_dirs(*_csv_pair(tmp_path / "b", same, same.replace("True", "true")))
    assert not ok and "A 'True' B 'true'" in text
    ok, text = PD.compare_csv_dirs(*_csv_pair(tmp_path / "n", "a\r\n1\r\n", "a\r\n1.5\r\n"))
    assert not ok


def test_csv_mode_missing_files_and_empty_dirs(tmp_path):
    da, db = tmp_path / "A", tmp_path / "B"
    (da / "seed_1").mkdir(parents=True)
    (db / "seed_1").mkdir(parents=True)
    ok, text = PD.compare_csv_dirs(da, db)
    assert not ok and "no .csv files" in text
    (da / "seed_1" / "x_runs.csv").write_text("a\r\n1\r\n", newline="")
    ok, text = PD.compare_csv_dirs(da, db)
    assert not ok and "seed_1/x_runs.csv: MISSING in B" in text


def test_chaos_telemetry_mode_is_deterministic_and_covers_every_outcome(tmp_path):
    import csv
    import chaos_trace as CT
    outcomes = set()
    for run in ("a", "b"):
        for seed in (0, 4, 8, 12):          # (seed // 4) % 4 = 0, 1, 2, 3
            CT.run(seed, 600, tmp_path / f"{run}{seed}.jsonl", mute={"funfacts"},
                   telemetry_dir=tmp_path / run)
    ok, text = PD.compare_csv_dirs(tmp_path / "a", tmp_path / "b")
    assert ok and "byte-identical" in text
    for seed in (0, 4, 8, 12):
        with (tmp_path / "a" / f"seed_{seed}" / "chaos_runs.csv").open(newline="") as fh:
            row = next(csv.DictReader(fh))
        assert row["source"] == "chaos" and row["deals"] == "chaos" and row["run_id"] == f"chaos{seed}"
        outcomes.add(row["outcome"])
    assert outcomes == {"unfinished", "killed", "collapse", "victory"}
    events = (tmp_path / "a" / "seed_4" / "chaos_events.csv").read_bytes()
    assert b'"He said ""hi"", then\nleft"\r\n' in events and b",1e-05,0.30000000000000004\r\n" in events
    assert b",6,turn,1,\r\n" not in events and b",turn,1," not in events      # SKIP: the "turn" event is never logged
