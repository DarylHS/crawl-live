"""The Showrunner: the System AI announcer and the viewer count.

Viewers rise with entertaining play and slowly decay when nothing happens.
Crossing a viewer threshold makes a sponsor send a loot box. Announcer lines
are data (LINES); it uses its own RNG so chatter never changes the dungeon.
"""
import random

from . import config as C
from .entities import MONSTERS, PET_QUIPS
from .items import ITEMS
from .lines import JACKPOT_VALUE, LINES

START_VIEWERS = 50
MIN_VIEWERS = 20
SAMPLE_EVERY = 10               # viewer curve resolution for the post-run report
IDLE_TURNS = 10                 # turns without excitement before viewers drift away
DECAY = 0.97                    # applied every IDLE_TURNS while idle
MULTI_WINDOW = 4                # kills this close together count as a streak
CLUTCH_FRAC = 0.25
# Events the System only comments on some of the time (scaled by SASS_LEVEL); others always.
SPEAK_CHANCE = {"kill": 0.4, "damage_taken": 0.5, "shop_buy": 0.5, "shop_sell": 0.3, "craft": 0.7,
                "nat20": 0.8, "nat1": 0.6, "foe_nat20": 0.6, "foe_nat1": 0.4,
                "opportunity_attack": 0.5}
QUIP_CHANCE = 0.6               # how often the pet says something itself
FLEE_QUIP_GAP = 8               # turns between the mouse's excuses while it runs
PET_EVENTS = {"pet_kill": "kill", "pet_ability": "ability", "pet_level_up": "level_up",
              "pet_downed": "downed", "pet_flee": "flee"}

# (viewers needed, box tier, sponsor)
SPONSOR_GIFTS = [
    (300, "bronze", "Brightly Snacks"),
    (700, "silver", "Gloop Energy"),
    (1500, "gold", "Vantage Mattress Co."),
    (3000, "platinum", "Zorp Premium Hair Care"),
    (6000, "legendary", "The Consortium of Mild Concern"),
]



class Showrunner:
    def __init__(self, world):
        self.world = world
        self.rng = random.Random(world.seed ^ 0x5EED)
        self.viewers = START_VIEWERS
        self.peak = START_VIEWERS
        self.history = []                   # (turn, viewers) at each floor start and end
        self.samples = [(0, START_VIEWERS)]  # (turn, viewers) every SAMPLE_EVERY turns
        self._kill_turns = []
        self._last_fun = 0
        self._gift_idx = 0
        for ev in LINES:
            if ev not in ("multi_kill", "clutch") and not ev.startswith("box_") \
                    or ev in ("box_reroll", "box_trade"):
                world.events.subscribe(ev, self._announce)
        world.events.subscribe("box_opened", self._box_reaction)
        for ev in ("kill", "level_up", "descend", "achievement", "floor_start", "boss_kill"):
            world.events.subscribe(ev, self._viewers)
        world.events.subscribe("turn", self._idle)
        for ev in PET_EVENTS:
            world.events.subscribe(ev, self._pet_quip)
        self._last_flee_quip = -FLEE_QUIP_GAP

    # --- Viewers -------------------------------------------------------

    def _gain(self, amount):
        from .contracts import effect
        w = self.world
        amount = int(amount * effect(w, "viewer_mult") * (1 + 0.03 * w.practice("showmanship"))
                     * (1 + 0.05 * w.mod("cha")))
        self.viewers += amount
        w.events.emit("viewers_gained", amount=amount)
        self.peak = max(self.peak, self.viewers)
        self._last_fun = self.world.turn
        while self._gift_idx < len(SPONSOR_GIFTS) and self.viewers >= SPONSOR_GIFTS[self._gift_idx][0]:
            _, tier, sponsor = SPONSOR_GIFTS[self._gift_idx]
            self._gift_idx += 1
            self.world.events.emit("sponsor_gift", tier=tier, sponsor=sponsor)
            self.world.add_box(tier, f"A gift from {sponsor} for reaching {self.viewers:,} viewers.")

    def _viewers(self, name, d):
        w = self.world
        if name == "kill":
            xp = d["xp"] if "xp" in d else MONSTERS[d["monster"]]["xp"]
            gain = 5 + 2 * xp + (15 if d.get("by") == "pet" else 0)
            self._kill_turns = [t for t in self._kill_turns if w.turn - t <= MULTI_WINDOW]
            self._kill_turns.append(w.turn)
            if len(self._kill_turns) >= 2:
                gain += 25 * (len(self._kill_turns) - 1)
                self._say("multi_kill")
            if d["player_hp"] <= d["player_max_hp"] * CLUTCH_FRAC:
                gain += 60
                self._say("clutch")
            self._gain(gain)
        elif name == "level_up":
            self._gain(40)
        elif name == "achievement":
            self._gain(50)
        elif name == "descend":
            late = d["timer_left"] < 0.25 * d["timer_max"]
            self._gain(100 if late else 30)
        elif name == "boss_kill":
            self._gain(150)
        elif name == "floor_start":
            self.history.append((d["turn"], self.viewers))

    def _idle(self, name, d):
        t = d["turn"]
        if t % SAMPLE_EVERY == 0:
            self.samples.append((t, self.viewers))
        if t % IDLE_TURNS == 0 and t - self._last_fun >= IDLE_TURNS:
            self.viewers = max(MIN_VIEWERS, int(self.viewers * DECAY))

    # --- Announcer -----------------------------------------------------

    def _pet_quip(self, name, d):
        """The companion speaks for itself, in character."""
        lines = PET_QUIPS.get(d.get("species"), {}).get(PET_EVENTS[name])
        if not lines:
            return
        if name == "pet_flee":
            if self.world.turn - self._last_flee_quip < FLEE_QUIP_GAP:
                return
            self._last_flee_quip = self.world.turn
        elif self.rng.random() >= QUIP_CHANCE:
            return
        pet = self.world.pet
        self.world.messages.add(f"{d['pet']}: {self.rng.choice(lines)}",
                                pet.colour if pet else C.TEXT)

    def _say(self, kind, **ctx):
        """Pick a line for the event, spicier as SASS_LEVEL rises, and post it."""
        pools = LINES[kind]
        spicy = self.rng.random() < min(1.0, max(0.0, (C.SASS_LEVEL - 4) / 4))
        pool = pools["spicy"] if spicy and pools.get("spicy") else pools["mild"]
        w = self.world
        ctx = {"hero": w.hero_name, "address": w.address, **ctx}
        line = self.rng.choice(pool).format_map(_Safe(ctx))
        w.messages.add("SYSTEM: " + line, C.INFO)

    def _box_reaction(self, name, d):
        """React to what came out of a loot box, judged against the box's average."""
        from .loot import BOX_TIERS, box_stats
        item = ITEMS[d["item"]]
        self._say(box_kind(d["tier"], d["item"]), item=item["name"],
                  tier=BOX_TIERS[d["tier"]]["name"], value=item["value"],
                  ev=f"{box_stats(d['tier'])[0]:.0f}")

    def _announce(self, name, d):
        if name in ("kill", "pet_kill") and d.get("boss"):
            return                          # boss_kill has its own lines
        if name == "practice_level" and d["level"] not in (1, 5, 10, 15):
            return                          # milestones only, or it never shuts up
        if name == "damage_taken" and d["hp"] > self.world.player.max_hp * 0.4:
            return
        if name == "opportunity_attack" and (d["target"] != "player" or not d["hit"]):
            return                          # the lines are about you getting caught, and hit
        chattiness = min(1.3, max(0.3, C.SASS_LEVEL / 7))
        if self.rng.random() >= SPEAK_CHANCE.get(name, 1.0) * chattiness:
            return
        ctx = dict(d)
        if "monster_name" in d:
            ctx["name"] = d["monster_name"]
        elif "monster" in d:
            ctx["name"] = MONSTERS[d["monster"]]["name"]
        if "tier" in d:
            ctx["tier"] = d["tier"].capitalize()
        if name == "achievement":
            ctx["achievement"] = d["title"]
            ctx["why"], ctx["reward"] = d["why"], d["reward"]
        if "contract" in d:
            from .contracts import CONTRACTS
            ctx["deal"] = CONTRACTS[d["contract"]]["name"]
        self._say(name, **ctx)


def box_kind(tier, key):
    """Which reaction a box result gets: junk, jackpot, or bad/meh/good against EV +/- 1 SD."""
    from .loot import box_stats
    ev, sd = box_stats(tier)
    item = ITEMS[key]
    if item["kind"] == "junk":
        return "box_junk"
    if item["value"] >= JACKPOT_VALUE:
        return "box_jackpot"
    if item["value"] < ev - sd:
        return "box_bad"
    if item["value"] > ev + sd:
        return "box_good"
    return "box_meh"


class _Safe(dict):
    def __missing__(self, key):
        return "?"
