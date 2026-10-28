"""Compare chaos traces from scripts/chaos_trace.py (Python) and godot/tools/chaos.gd (Godot).

    python scripts/chaos_diff.py PY.jsonl GD.jsonl [--no-msg]
    python scripts/chaos_diff.py --dirs PY_DIR GD_DIR --seeds 0-9 [--no-msg]

Compares every row field by value; on the first difference prints the row, the differing fields (for
events and messages the first differing entry) and the previous row's action. Exit 0 when every pair is
identical, 1 otherwise (a missing or malformed file counts as a difference).

--mute LIST (default achievements,showrunner,funfacts, as chaos_trace.py): when the showrunner is muted the
viewers fields of floor_stats are dropped, since the muted side does not track them. Pass the same list as
to chaos_trace.py and chaos.gd. --mute none (or --no-mute-standins) compares everything."""
import argparse
import json
import sys

NAMES = ("n tag ok turn depth state timer timer_max stairs_open px py hp max_hp xp level kills stat_points attrs ac attack "
         "dmg_n dmg_die dmg_bonus dr gold mon items pet combat riposte has_key exit_sealed inv equip boxes box_reasons "
         "box_log last_reveal last_reason race cls pending_choice skill_cd scout hype remote_shop contract pending_offer "
         "death_cause on_hand bought missed shoplog prac_lv prac_xp prac_steps floor_stats rng loot shop deal explored evs msgs").split()



def compare(a, b, nomsg=False, mute=True):
    """None when the two chaos traces agree, else a description of the first difference."""
    A = [json.loads(l) for l in open(a)]
    B = [json.loads(l) for l in open(b)]
    for i, (x, y) in enumerate(zip(A, B)):
        fi = NAMES.index("floor_stats")
        for r in (x, y):
            if not mute:
                break
            r[fi] = [{k: v for k, v in f.items() if not k.startswith("viewers")} for f in r[fi]]
        if nomsg:
            x = x[:-1]; y = y[:-1]
        if x != y:
            out = [f"DIFF row {i} (n={x[0]} tag={x[1]})"]
            for j, (u, v) in enumerate(zip(x, y)):
                if u != v:
                    if NAMES[j] in ("evs", "msgs"):
                        for k in range(max(len(u), len(v))):
                            eu = u[k] if k < len(u) else None
                            ev = v[k] if k < len(v) else None
                            if eu != ev:
                                out.append(f"  {NAMES[j]}[{k}]\n    PY {eu}\n    GD {ev}")
                                break
                    else:
                        out.append(f"  {NAMES[j]}\n    PY {str(u)[:400]}\n    GD {str(v)[:400]}")
            prev = A[i - 1] if i else None
            if prev:
                out.append(f"  prev row tag={prev[1]} ok={prev[2]} turn={prev[3]}")
            return "\n".join(out)
    if len(A) != len(B):
        return f"LEN {len(A)} {len(B)}"
    return None


def seeds_arg(text):
    lo, _, hi = text.partition("-")
    return list(range(int(lo), int(hi or lo) + 1))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("files", nargs="*", help="PY.jsonl GD.jsonl")
    ap.add_argument("--dirs", nargs=2, metavar=("PY_DIR", "GD_DIR"))
    ap.add_argument("--seeds", default="0-9")
    ap.add_argument("--no-msg", action="store_true", help="ignore the message lists")
    ap.add_argument("--mute", default="achievements,showrunner,funfacts")
    ap.add_argument("--mute-standins", action=argparse.BooleanOptionalAction, default=None)
    a = ap.parse_args()
    muted = set() if a.mute in ("", "none") else set(a.mute.split(","))
    if a.mute_standins is not None:
        muted = {"achievements", "showrunner", "funfacts"} if a.mute_standins else set()
    if a.dirs:
        pairs = [(f"{a.dirs[0]}/chaos_{s}.jsonl", f"{a.dirs[1]}/chaos_{s}.jsonl") for s in seeds_arg(a.seeds)]
    elif len(a.files) == 2:
        pairs = [tuple(a.files)]
    else:
        ap.error("give PY.jsonl GD.jsonl or --dirs PY_DIR GD_DIR")
    bad = 0
    for x, y in pairs:
        try:
            r = compare(x, y, a.no_msg, "showrunner" in muted)
        except (OSError, ValueError) as e:
            r = f"cannot compare: {e}"
        print(f"{x.rsplit('/', 1)[-1]}: {'SAME' if r is None else r}")
        bad += r is not None
    print(f"{len(pairs) - bad}/{len(pairs)} chaos traces identical")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
