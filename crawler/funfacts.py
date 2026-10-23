"""The System AI's stats one-liners, triggered by things that just happened.

Facts are rate-limited (one per MIN_GAP turns) so they stay a garnish.
Each uses the game's real numbers, not generic trivia.
"""
from . import config as C
from .loot import BOX_TIERS, TRADE_UP_COST, box_stats, next_tier, odds

MIN_GAP = 25
MISS_STREAK = 4                 # misses in a row before the gambler's fallacy fact
BOX_DROUGHT = 3                 # boxes of a tier opened without its rarest item


class FunFacts:
    def __init__(self, world):
        self.world = world
        self.last_turn = -MIN_GAP
        self.said = set()               # facts that only appear once per run
        self.miss_streak, self.streak_chance = 0, 1.0
        self.drought = {}               # tier -> boxes opened without the rarest item
        ev = world.events
        ev.subscribe("player_attack", self._attack)
        ev.subscribe("box_opened", self._box)
        ev.subscribe("box_trade", self._trade)
        ev.subscribe("contract_accepted", self._contract)
        ev.subscribe("shop_sold_out", self._sold_out)
        ev.subscribe("damage_taken", self._close_call)

    def _say(self, text, once=None, force=False):
        w = self.world
        if once in self.said or (not force and w.turn - self.last_turn < MIN_GAP):
            return False
        if once:
            self.said.add(once)
        self.last_turn = w.turn
        w.messages.add(f"FUN FACT: {text}", C.INFO)
        w.events.emit("fun_fact", text=text)
        return True

    def _attack(self, name, d):
        if d["hit"]:
            self.miss_streak = 0
            if d["crit"]:
                self._say("Crits land 5% of the time: one swing in 20 on average, but they "
                          "cluster and gap at random.", once="crit")
            return
        self.miss_streak += 1
        self.streak_chance *= 1 - d["chance"] if self.miss_streak > 1 else 1
        if self.miss_streak == 1:
            self.streak_chance = 1 - d["chance"]
        if self.miss_streak >= MISS_STREAK and d["chance"] >= 0.6:
            if self._say(f"{self.miss_streak} misses in a row at {d['chance']:.0%} each: odds of "
                         f"that were {self.streak_chance:.2%}. Your next swing is still "
                         f"{d['chance']:.0%}. Dice have no memory."):
                self.miss_streak = 0

    def _box(self, name, d):
        tier = d["tier"]
        rarest, p = min(odds(tier), key=lambda r: r[1])
        if d["item"] == rarest:
            self.drought[tier] = 0
            return
        n = self.drought.get(tier, 0) + 1
        self.drought[tier] = n
        if n >= BOX_DROUGHT:
            from .items import ITEMS
            self._say(f"{n} {BOX_TIERS[tier]['name']} boxes without a {ITEMS[rarest]['name']} "
                      f"({p:.0%} each). Chance of that: {(1 - p) ** n:.0%}. It isn't 'due': "
                      f"every box is a fresh roll.", force=True)

    def _trade(self, name, d):
        ev_in, _ = box_stats(d["tier"])
        ev_out, sd_out = box_stats(d["to"])
        edge = TRADE_UP_COST * ev_in - ev_out
        if edge > 0:
            verdict = (f"loses about {edge:.0f} gold on average. That's the house edge: it only "
                       f"pays if you want something only the bigger box has")
        else:
            verdict = f"gains about {-edge:.0f} gold on average"
        self._say(f"That trade {verdict}. You swapped {TRADE_UP_COST} boxes worth "
                  f"{TRADE_UP_COST * ev_in:.0f} in total for one worth {ev_out:.0f}, give or take "
                  f"{sd_out:.0f}.", force=True)

    def _contract(self, name, d):
        self._say("A deal can have positive expected value and still end your run. Averages "
                  "describe many runs; you only get this one.", once="contract")

    def _sold_out(self, name, d):
        from .items import ITEMS
        self._say(f"Sold out of {ITEMS[d['item']]['name']}. The shop carries safety stock for "
                  f"about one standard deviation of demand, so it runs dry roughly one floor "
                  f"in six. This was one of them.", once=f"sold_out_{d['item']}", force=True)

    def _close_call(self, name, d):
        p = self.world.player
        if 0 < d["hp"] <= p.max_hp * 0.1:
            self._say("Still standing on almost nothing. Close calls feel common because "
                      "you only remember the ones you survived (survivorship bias).",
                      once="close_call")
