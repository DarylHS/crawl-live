"""Scripted action policies for the parity traces (plan section 6.4).

Each policy is a small deterministic object that, given the World, performs one
policy step (usually one action) through a callback.  The Godot mirror
(godot/tools/trace_policies.gd) must be written line for line alike, so the rules
here are deliberately plain: no set or dict iteration, lists in World order, ties
broken by first in list order, and every random choice drawn from the policy's own
stream (a CountingRandom the tracer supplies) in the documented order.

Usage (library only; scripts/py_trace.py drives it):

    policy = make_policy("hunter", seed, rng)      # rng: random.Random seeded policy_seed(name, seed)
    policy.step(world, do)                          # do(action, arg) -> bool (the action's ok)

Actions (the strings written to the trace's "act" records) and their args:

    move [dx, dy]      World.move_player          descend None   World.descend
    wait None          World.wait                 rest None      World.rest
    pickup None        World.pickup               use int        World.use_item(index)
    skill None         World.use_skill            revive None    World.revive_pet
    choose_class [race, cls]   World.choose_class accept None / decline None   contracts

perform() maps an action to the World call.  If the main action of a step returns
False (nothing was spent) the policy then calls do("wait", None), exactly like the
bot does, so every step spends game time.

Policies
--------
walk    Draw i = rng.randrange(9).  i < 8: move NEIGHBOURS_8[i]; i == 8: wait.
hunter  Decision order, first rule that yields an action wins (step_towards = one
        downhill step on floor.distance_map from the target, NEIGHBOURS_8 order,
        strictly smaller distance only, -1 ignored; no step available means the
        rule is skipped):
          1. hp * 100 < max_hp * 45 and not in a safe room: use the first inventory
             index holding a potion (tonic, brew or elixir), if any
          2. a monster at Chebyshev distance 1 (first in w.monsters order): move
             onto it (attack)
          3. standing on floor items with fewer than 16 carried: pickup
          4. visible monsters ((x, y) in w.visible, bosses only when exit_sealed): the
             nearest by Chebyshev distance to the player (first minimum in list
             order): step_towards it
          5. rooms in floor.rooms order whose centre is not explored: the nearest
             centre by Chebyshev distance (first minimum): step_towards it
          6. standing on stairs that are open (not stairs_locked, not exit_sealed): descend
          7. step_towards the nearest stairs (first minimum in floor.stairs order),
             unless already on them
          8. wait
bot     analysis/bot.py's choose / spend_points / manage_items driving the same loop
        as bot.play (class pick when pending, contract coin flip, free item
        management, one act, wait when refused).  The coin stream is
        random.Random(seed ^ 0xB07); the race/class/pet/hero come from run_config(seed).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from crawler.dungeon import NEIGHBOURS_8  # noqa: E402

POLICY_NAMES = ("walk", "hunter", "bot")
POTIONS = ("tonic", "brew", "elixir")


def policy_seed(name, seed):
    """Seed of the policy's own RNG stream (plan 6.4; the bot's coin stream is seed ^ 0xB07)."""
    return seed ^ (0xB07 if name == "bot" else 0x7ACE)


def cheb(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


def perform(w, action, arg):
    """Run one named action on the World; returns its ok flag."""
    if action == "move":
        return w.move_player(arg[0], arg[1])
    if action == "wait":
        return w.wait()
    if action == "descend":
        return w.descend()
    if action == "rest":
        return w.rest()
    if action == "pickup":
        return w.pickup()
    if action == "use":
        return w.use_item(arg)
    if action == "skill":
        return w.use_skill()
    if action == "revive":
        return w.revive_pet()
    if action == "choose_class":
        return w.choose_class(arg[0], arg[1])
    if action == "accept":
        return w.accept_contract()
    if action == "decline":
        return w.decline_contract()
    raise ValueError(f"unknown action {action!r}")


def step_towards(w, tx, ty):
    """One step downhill on a distance map from the target, or None."""
    f, p = w.floor, w.player
    dist = f.distance_map(tx, ty)
    best, move = dist[p.y * f.width + p.x], None
    for dx, dy in NEIGHBOURS_8:
        nx, ny = p.x + dx, p.y + dy
        if f.walkable(nx, ny):
            d = dist[ny * f.width + nx]
            if d != -1 and d < best:
                best, move = d, [dx, dy]
    return move


class WalkPolicy:
    name = "walk"

    def __init__(self, seed, rng):
        self.rng = rng

    def step(self, w, do):
        i = self.rng.randrange(9)
        if i < 8:
            ok = do("move", [NEIGHBOURS_8[i][0], NEIGHBOURS_8[i][1]])
        else:
            ok = do("wait", None)
        if not ok:
            do("wait", None)


class HunterPolicy:
    name = "hunter"

    def __init__(self, seed, rng):
        self.rng = rng              # unused (the hunter is fully deterministic), kept for symmetry

    def decide(self, w):
        p, f = w.player, w.floor
        pos = (p.x, p.y)
        if p.hp * 100 < p.max_hp * 45 and not w.in_safe_room:       # 1
            for i, key in enumerate(w.inventory):
                if key in POTIONS:
                    return "use", i
        for m in w.monsters:                                        # 2
            if cheb((m.x, m.y), pos) == 1:
                return "move", [m.x - p.x, m.y - p.y]
        if pos in w.floor_items and len(w.inventory) < 16:          # 3
            return "pickup", None
        best = None
        for m in w.monsters:                                        # 4
            if (m.x, m.y) in w.visible and (not m.boss or w.exit_sealed):
                d = cheb((m.x, m.y), pos)
                if best is None or d < best[0]:
                    best = (d, m)
        if best is not None:
            mv = step_towards(w, best[1].x, best[1].y)
            if mv:
                return "move", mv
        best = None
        for r in f.rooms:                                           # 5
            c = r.centre
            if not f.explored[c[1]][c[0]]:
                d = cheb(c, pos)
                if best is None or d < best[0]:
                    best = (d, c)
        if best is not None:
            mv = step_towards(w, best[1][0], best[1][1])
            if mv:
                return "move", mv
        if w.on_stairs and not w.stairs_locked and not w.exit_sealed:   # 6
            return "descend", None
        if not w.on_stairs:                                         # 7
            best = None
            for s in f.stairs:
                d = cheb(s, pos)
                if best is None or d < best[0]:
                    best = (d, s)
            if best is not None:
                mv = step_towards(w, best[1][0], best[1][1])
                if mv:
                    return "move", mv
        return "wait", None                                         # 8

    def step(self, w, do):
        action, arg = self.decide(w)
        if not do(action, arg):
            do("wait", None)


class BotPolicy:
    """analysis/bot.py's decision code (imported, not copied) in bot.play's loop."""
    name = "bot"

    def __init__(self, seed, rng):
        from analysis import bot
        self.bot = bot
        self.cfg = bot.run_config(seed)
        self.rng = rng              # the coin stream

    def step(self, w, do):
        bot, cfg = self.bot, self.cfg
        if w.pending_choice:
            do("choose_class", [cfg["race"], cfg["cls"]])
        if w.pending_offer:
            do("accept" if self.rng.random() < 0.5 else "decline", None)
        bot.spend_points(w, cfg["cls"])
        bot.manage_items(w)
        act, arg = bot.choose(w)
        if act == "move":
            ok = do("move", list(arg))
        elif act == "skill":
            ok = do("skill", None)
            if ok and w.remote_shop:
                for key in ("brew", "tonic"):
                    if w.shop.stock[key].on_hand and w.gold >= w.buy_price(key) and w.shop_buy(key):
                        break
                w.remote_shop = False
        elif act in ("descend", "rest", "pickup", "use", "revive", "wait"):
            ok = do(act, arg)
        else:
            ok = do("wait", None)
        if not ok:
            do("wait", None)


def make_policy(name, seed, rng):
    if name == "walk":
        return WalkPolicy(seed, rng)
    if name == "hunter":
        return HunterPolicy(seed, rng)
    if name == "bot":
        return BotPolicy(seed, rng)
    raise ValueError(f"unknown policy {name!r}; choose from {POLICY_NAMES}")


def default_setup(name, seed):
    """(pet species or None, hero dict or None) a policy uses unless the command line overrides it."""
    if name == "bot":
        from analysis import bot
        cfg = bot.run_config(seed)
        pet = cfg["pet"]
        return (pet if pet != "none" else None,
                dict(name="Bot", gender=cfg["gender"], backstory=cfg["backstory"]))
    return None, None
