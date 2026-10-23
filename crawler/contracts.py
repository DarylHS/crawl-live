"""Sponsor contracts: a deal offered at the start of a floor, for that floor only.

Each one trades a reward for a risk. preview() turns the terms into numbers
from the player's own run so far, so accepting is an expected-value call.
"""
from . import config as C
from .combat import expected_damage

OFFER_FROM_FLOOR = 2
OFFER_CHANCE = 0.7

CONTRACTS = {
    "gloop_blitz": dict(sponsor="Gloop Energy", name="Gloop Blitz",
                        desc="A Silver box now and +50% gold this floor, but monsters get +1 attack.",
                        gold_mult=1.5, monster_power=1, bonus_box="silver"),
    "snack_sprint": dict(sponsor="Brightly Snacks", name="Snack Sprint",
                         desc="A Silver box now and +40% viewers, but the floor collapses 20% sooner.",
                         viewer_mult=1.4, timer_mult=0.8, bonus_box="silver"),
    "power_naps": dict(sponsor="Vantage Mattress Co.", name="Power Nap Package",
                       desc="Resting heals twice as fast, but you earn 30% less gold.",
                       rest_mult=2, gold_mult=0.7),
    "hazard_pay": dict(sponsor="The Consortium of Mild Concern", name="Hazard Pay",
                       desc="A Gold box now, double gold and +50% viewers. Monsters get +25% HP "
                            "and +2 attack.",
                       gold_mult=2.0, viewer_mult=1.5, monster_hp_mult=1.25, monster_power=2,
                       bonus_box="gold"),
}


def effect(world, name, default=1):
    """A modifier from the active contract, or the default."""
    c = CONTRACTS.get(world.contract) if world.contract else None
    return c.get(name, default) if c else default


def preview(world, key):
    """Plain-language numbers for this deal, based on the run so far."""
    c = CONTRACTS[key]
    lines = []
    done = world.floor_stats[:-1]
    if "bonus_box" in c:
        from .loot import BOX_TIERS, box_stats
        ev, sd = box_stats(c["bonus_box"])
        lines.append(f"Signing bonus: a {BOX_TIERS[c['bonus_box']]['name']} box, worth {ev:.0f} "
                     f"gold on average (give or take {sd:.0f}).")
    if "gold_mult" in c:
        base = (sum(f["gold"] for f in done) / len(done) if done
                else sum(m.xp_value for m in world.monsters) * C.GOLD_PER_XP * 0.6)
        lines.append(f"Gold: you average about {base:.0f} a floor, so expect "
                     f"{base * (c['gold_mult'] - 1):+.0f} gold.")
    if "viewer_mult" in c:
        gain = (sum(f["viewers_end"] - f["viewers_start"] for f in done) / len(done)
                if done else 300)
        lines.append(f"Viewers: about {max(0, gain) * (c['viewer_mult'] - 1):+.0f} on top of a "
                     f"typical floor.")
    if "monster_power" in c or "monster_hp_mult" in c:
        p = world.player
        mobs = [m for m in world.monsters if not m.boss] or world.monsters
        now = sum(expected_damage(m, p) for m in mobs) / len(mobs)
        for m in mobs:
            m.power += c.get("monster_power", 0)
        then = sum(expected_damage(m, p) for m in mobs) / len(mobs)
        for m in mobs:
            m.power -= c.get("monster_power", 0)
        lines.append(f"Danger: an average monster's hit on you goes from {now:.1f} to "
                     f"{then:.1f} expected damage ({(then / now - 1):+.0%}).")
        if "monster_hp_mult" in c:
            lines.append(f"Monsters take {c['monster_hp_mult'] - 1:.0%} longer to kill.")
    if "timer_mult" in c:
        lines.append(f"Time: {world.timer_text()} becomes "
                     f"{world.timer_text(round(world.timer * c['timer_mult']))}.")
    if "rest_mult" in c:
        lines.append("Resting to full takes half as long.")
    return lines
