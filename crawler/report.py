"""Post-run report data (headless; the UI draws it in ui/report.py)."""


def run_report(world):
    """Everything the report screen plots, as plain lists."""
    floors = world.floor_stats
    expected, realised, ev_total, got_total = [], [], 0.0, 0
    for b in world.box_log:
        ev_total += b["ev"]
        got_total += b["value"]
        expected.append(ev_total)
        realised.append(got_total)
    samples = list(world.showrunner.samples)
    if not samples or samples[-1][0] != world.turn:
        samples.append((world.turn, world.viewers))
    return dict(
        damage_by_floor=[(f["depth"], f["damage_taken"]) for f in floors],
        gold_by_floor=[(f["depth"], f["gold"]) for f in floors],
        contracts=[(f["depth"], f["contract"]) for f in floors if f["contract"]],
        box_expected=expected, box_realised=realised,
        viewers=samples,
        totals=dict(gold=sum(f["gold"] for f in floors), kills=world.player.kills,
                    boxes=len(world.box_log), rerolls=sum(b["rerolled"] for b in world.box_log),
                    damage=sum(f["damage_taken"] for f in floors), turns=world.turn,
                    peak_viewers=world.showrunner.peak),
    )
