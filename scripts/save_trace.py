"""Save/load parity harness, Python side (slice T5). godot/tools/save_trace.gd mirrors it line for line;
scripts/save_diff.py compares the two.

A seeded chaos player (the action mix of scripts/chaos_trace.py, without its tracing) plays a World to a
save point, the run is saved to DIR/save_<seed>.json with crawler.save, and play continues two ways:

    direct   the same World keeps going
    loaded   the saved file is read back (crawler.save.load) and that World keeps going

Both continuations use a fresh policy stream (random.Random(seed ^ 0xC0117)) and write one JSON line per
step to DIR/direct_<seed>.jsonl and DIR/loaded_<seed>.jsonl: a header line (turn, depth, sha256 of the save
text of the World about to be continued) then, per step, the action and a digest of the state (turn, depth,
hp, position, gold, monsters, the five RNG digests, viewers, last message, message count), with a sha256 of
the full save text every 25 steps and after the last step. If `loaded` differs from `direct`, a save did not
round-trip.

    python scripts/save_trace.py --seeds 0-9 --steps 300 --out-dir DIR
    python scripts/save_trace.py --seeds 0-9 --steps 300 --out-dir DIR --load-dir OTHER_DIR

--load-dir (cross-load): also load OTHER_DIR/save_<seed>.json (written by the other implementation),
continue it and write DIR/xload_<seed>.jsonl. Its header hash is that of the re-dumped loaded World, so it
equals the original save's hash exactly when the load lost nothing.

The save point: the policy plays 60 + (seed * 53) % 700 steps, then more until the World is playing and
out of combat; odd seeds are then moved into the safe room first (the game only saves there).
"""
import argparse
import hashlib
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts"))
from crawler import save  # noqa: E402
from crawler.world import World  # noqa: E402
from crawler.dungeon import NEIGHBOURS_8  # noqa: E402
from py_trace import mon_string, state_digest  # noqa: E402

RACES = ['human', 'elf', 'dwarf', 'hobgoblin', 'bog_troll', 'houseplant']
CLASSES = ['brawler', 'arcanist', 'analyst', 'alchemist', 'beastmaster', 'hype_man', 'demolitionist', 'quartermaster', 'duellist']
TIERS = ['bronze', 'silver', 'gold', 'platinum', 'legendary']
SHOPKEYS = ['tonic', 'brew', 'elixir', 'popper', 'fireworks', 'jersey', 'vest', 'pan', 'cleaver']
ATTRS = ['str', 'dex', 'con', 'int', 'cha']
PETS = ['none', 'cat', 'dog', 'budgie', 'mouse']
GENDERS = ['female', 'male', 'nonbinary']
BACKS = ['veteran', 'mixologist', 'dog_walker', 'comedian', 'parent', 'tradie', 'category_mgr', 'rideshare']


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def save_text(w):
    return json.dumps(save.to_dict(w))


class Chaos:
    """The chaos player: setup(), then step(n) once per game step with its own random stream."""

    def __init__(self, seed, world=None):
        self.seed = seed
        pet = PETS[seed % 5]
        hero = None if seed % 4 == 0 else {"name": "H", "gender": GENDERS[seed % 3], "backstory": BACKS[(seed // 3) % 8]}
        c = seed % 54
        self.race = RACES[c % 6]
        self.cls = CLASSES[(c // 6) % 9]
        self.w = world if world is not None else World(seed, pet=(pet, "") if pet != "none" else None, hero=hero)
        self.rng = random.Random(seed ^ 0x5C8)

    def cheb(self, ax, ay, bx, by):
        return max(abs(ax - bx), abs(ay - by))

    def free(self, x, y):
        w, p = self.w, self.w.player
        return (w.floor.walkable(x, y) and not w.floor.is_safe(x, y) and w.monster_at(x, y) is None
                and w.pet_at(x, y) is None and not (x == p.x and y == p.y))

    def ring(self, cx, cy, d):
        for dy in range(-d, d + 1):
            for dx in range(-d, d + 1):
                if max(abs(dx), abs(dy)) == d and self.free(cx + dx, cy + dy):
                    return (cx + dx, cy + dy)
        return None

    def put(self, xy):
        if xy is not None:
            self.w.player.x, self.w.player.y = xy
            self.w.update_fov()

    def to_safe(self):
        w, p = self.w, self.w.player
        r = w.floor.safe_room
        for y in range(r.y, r.y + r.h):
            for x in range(r.x, r.x + r.w):
                if w.floor.walkable(x, y) and w.floor.is_safe(x, y) and w.monster_at(x, y) is None and w.pet_at(x, y) is None:
                    p.x, p.y = x, y
                    w.update_fov()
                    return

    def first_idx(self, keys):
        for i, k in enumerate(self.w.inventory):
            if k in keys:
                return i
        return -1

    def setup(self):
        w, p, seed = self.w, self.w.player, self.seed
        p.level = 6 + (seed % 7) * 2
        w.refresh_stats()
        p.hp = p.max_hp
        for k in ["popper", "fireworks", "popper", "tonic", "brew", "sock", "mug", "remote", "trophy", "pan", "jersey"]:
            if len(w.inventory) < 16:
                w.inventory.append(k)
        w.gold += 300
        for i, t in enumerate(["bronze", "bronze", "bronze", "bronze", "silver", "silver", "silver", "gold"]):
            w.add_box(t, "r%d" % i)
        if seed % 5 == 0:
            for k, v in [("tinkering", 8), ("power_napping", 5), ("first_aid", 5), ("lobbing", 5), ("haggling", 5), ("gambling", 5)]:
                w.training.levels[k] = v
        if seed % 3 != 0:
            if self.first_idx(["jersey"]) >= 0:
                w.use_item(self.first_idx(["jersey"]))
            w.choose_class(self.race, self.cls)

    def safe_block(self):
        w, rng = self.w, self.rng
        self.to_safe()
        w.rest()
        w.craft(rng.randrange(4))
        if self.first_idx(["popper", "fireworks"]) >= 0:
            w.use_item(self.first_idx(["popper", "fireworks"]))
        w.use_skill()
        w.shop_buy(SHOPKEYS[rng.randrange(9)])
        w.shop_sell(rng.randrange(max(1, len(w.inventory))))
        w.revive_pet()
        if w.boxes:
            w.open_box(w.boxes[rng.randrange(len(w.boxes))])
        if rng.random() < 0.6:
            w.reroll()
        w.trade_up(TIERS[rng.randrange(5)])
        if self.first_idx(["tonic", "brew", "elixir"]) >= 0:
            w.use_item(self.first_idx(["tonic", "brew", "elixir"]))

    def stairs_block(self):
        w, p, rng = self.w, self.w.player, self.rng
        s = w.floor.stairs[rng.randrange(len(w.floor.stairs))]
        if w.monster_at(s[0], s[1]) is None and w.pet_at(s[0], s[1]) is None:
            p.x, p.y = s[0], s[1]
            w.update_fov()
        if rng.random() < 0.75:
            w.has_key = True
        if not w.descend():
            w.wait()

    def step(self, n):
        """One chaos step; returns (tag, ok) of the main action."""
        w, p, rng, seed = self.w, self.w.player, self.rng, self.seed
        if w.pending_choice:
            w.choose_class(self.race, self.cls)
        if w.pending_offer:
            if rng.random() < 0.5:
                w.accept_contract()
            else:
                w.decline_contract()
        if p.stat_points > 0 and rng.random() < 0.3:
            w.spend_point(ATTRS[rng.randrange(5)])
        if n % 20 == 0:
            kind = (n // 20) % 10
            if kind in (0, 6):
                self.safe_block()
            elif kind in (2, 7):
                self.stairs_block()
            elif kind in (1, 9):
                if w.monsters:
                    m = w.monsters[rng.randrange(len(w.monsters))]
                    self.put(self.ring(m.x, m.y, 1))
                    if kind == 9:
                        w.use_skill()
            elif kind == 3:
                for k in ["fireworks", "popper", "tonic", "elixir", "sock", "mug", "trophy", "remote", "cleaver", "vest"]:
                    if len(w.inventory) < 16 and rng.random() < 0.5:
                        w.inventory.append(k)
                w.add_box(TIERS[rng.randrange(3)], "grant%d" % n)
                if seed % 2 == 1 and (n // 200) % 2 == 1:
                    w.gold = 0
                else:
                    w.gold += 100
            elif kind == 4:
                if w.monsters:
                    m = w.monsters[rng.randrange(len(w.monsters))]
                    self.put(self.ring(m.x, m.y, 2 + rng.randrange(2)))
                    if rng.random() < 0.5:
                        for o in w.monsters:
                            if self.cheb(o.x, o.y, m.x, m.y) <= 2:
                                o.hp = min(o.hp, 2)
                    i = self.first_idx(["fireworks", "popper"])
                    if i >= 0:
                        w.use_item(i)
                    w.use_skill()
            elif kind == 5:
                tgt = None
                for m in w.monsters:
                    if m.boss or m.tier:
                        tgt = m
                        break
                if tgt is not None:
                    self.put(self.ring(tgt.x, tgt.y, 1))
            elif kind == 8:
                p.hp = max(1, p.max_hp // 2)
                if w.pet is not None and not w.pet.downed:
                    w.pet.hp = 1
        if w.state != "playing":
            return "over", None
        if seed % 4 != 3 and p.hp < p.max_hp // 4:
            p.hp = p.max_hp // 2
        a = rng.randrange(24)
        if a <= 1 or (a <= 7 and not any(self.cheb(m.x, m.y, p.x, p.y) == 1 for m in w.monsters)):
            d = NEIGHBOURS_8[rng.randrange(8)]
            tag, ok = "move", w.move_player(d[0], d[1])
        elif a <= 7:
            m = next(m for m in w.monsters if self.cheb(m.x, m.y, p.x, p.y) == 1)
            tag, ok = "attack", w.move_player(m.x - p.x, m.y - p.y)
        elif a == 8:
            tag, ok = "wait", w.wait()
        elif a == 9:
            tag, ok = "pickup", w.pickup()
        elif a == 10:
            tag, ok = "drop", w.drop(rng.randrange(max(1, len(w.inventory))))
        elif a <= 12:
            tag, ok = "use", w.use_item(rng.randrange(max(1, len(w.inventory))))
        elif a == 13:
            tag, ok = "unequip", w.unequip(["weapon", "armour"][rng.randrange(2)])
        elif a <= 15:
            tag, ok = "skill", w.use_skill()
        elif a == 16:
            tag, ok = "rest", w.rest()
        elif a == 17:
            tag, ok = "craft", w.craft(rng.randrange(4))
        elif a == 18:
            tag, ok = "buy", w.shop_buy(SHOPKEYS[rng.randrange(9)])
        elif a == 19:
            tag, ok = "sell", w.shop_sell(rng.randrange(max(1, len(w.inventory))))
        elif a == 20:
            tag, ok = "command", w.command_pet()
        elif a == 21:
            tag, ok = "revive", w.revive_pet()
        elif a == 22:
            r = rng.randrange(3)
            if r == 0:
                tag, ok = "open", w.open_box(TIERS[rng.randrange(5)])
            elif r == 1:
                tag, ok = "reroll", w.reroll()
            else:
                tag, ok = "trade", w.trade_up(TIERS[rng.randrange(5)])
        else:
            tag, ok = "descend", w.descend()
        if not ok and w.state == "playing":
            w.wait()
        return tag, ok


def play_to_save_point(seed):
    """The World at the save point (playing, out of combat; odd seeds in the safe room)."""
    c = Chaos(seed)
    c.setup()
    w = c.w
    before = 60 + (seed * 53) % 700
    n = 0
    while n < before and w.state == "playing":
        c.step(n)
        n += 1
    while w.state == "playing" and w.combat is not None and n < before + 400:
        c.step(n)
        n += 1
    if w.state == "playing" and w.combat is None and seed % 2 == 1:
        c.to_safe()
    return c, w


def continue_run(w, seed, steps, path):
    """Continue `w` with a fresh policy stream and write the trace to `path`."""
    c = Chaos(seed, w)
    c.rng = random.Random(seed ^ 0xC0117)
    out = open(path, "w")
    text = save_text(w) if w.combat is None else ""
    out.write(json.dumps(["header", seed, w.turn, w.depth, w.state, len(text), sha(text)], separators=(",", ":")) + "\n")

    def digest(n, tag, ok):
        p = w.player
        rec = [n, tag, bool(ok) if ok is not None else None, w.turn, w.depth, w.state, p.hp, p.x, p.y, w.gold,
               sha(mon_string(w.monsters)), state_digest(w.rng)[:16], state_digest(w.loot_rng)[:16],
               state_digest(w.shop.rng)[:16], state_digest(w.deal_rng)[:16], state_digest(w.showrunner.rng)[:16],
               w.viewers, w.messages.lines[-1][0] if w.messages.lines else None, len(w.messages.lines)]
        if n % 25 == 24 and w.combat is None:
            rec.append(sha(save_text(w)))
        out.write(json.dumps(rec, separators=(",", ":")) + "\n")

    for n in range(steps):
        if w.state != "playing":
            break
        tag, ok = c.step(n)
        digest(n, tag, ok)
    text = save_text(w) if w.combat is None else ""
    out.write(json.dumps(["end", w.turn, w.depth, w.state, len(text), sha(text)], separators=(",", ":")) + "\n")
    out.close()


def seeds_arg(text):
    lo, _, hi = text.partition("-")
    return list(range(int(lo), int(hi or lo) + 1))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--seeds", required=True, help="A-B or N")
    ap.add_argument("--steps", type=int, default=300)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--load-dir", help="also continue the saves found here (written by the other implementation)")
    a = ap.parse_args()
    out = Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    for seed in seeds_arg(a.seeds):
        _, w = play_to_save_point(seed)
        if w.state != "playing" or w.combat is not None:
            (out / f"skip_{seed}").write_text("no save point\n")
            continue
        path = out / f"save_{seed}.json"
        save.save(w, path)
        v = save.load(path)
        continue_run(v, seed, a.steps, out / f"loaded_{seed}.jsonl")
        continue_run(w, seed, a.steps, out / f"direct_{seed}.jsonl")
        if a.load_dir:
            other = Path(a.load_dir) / f"save_{seed}.json"
            if other.exists():
                continue_run(save.load(other), seed, a.steps, out / f"xload_{seed}.jsonl")


if __name__ == "__main__":
    main()
