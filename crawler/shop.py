"""The safe-room shop: a small inventory simulation.

One shop franchise serves every safe room, so its stock carries between
floors. Other crawlers buy from it too (Poisson demand per floor). At the end
of each floor the shop:
  1. sells to the other crawlers (unmet demand is a lost sale, a stockout),
  2. updates its demand forecast by exponential smoothing,
  3. receives last floor's order (lead time: one floor),
  4. reorders up to its target if stock is at or below the reorder point.
Prices rise as stock runs low. Everything is exposed so the player (and the
Phase 5 notebook) can see the forecast, safety stock and reorder point.
"""
import math
from dataclasses import dataclass, field

from .items import value

# Other crawlers' average demand per floor, before the depth multiplier.
BASE_DEMAND = {"tonic": 3.0, "brew": 1.5, "elixir": 0.5, "popper": 1.5, "fireworks": 0.7,
               "jersey": 0.8, "vest": 0.5, "pan": 0.8, "cleaver": 0.4}
DEMAND_GROWTH = 0.1             # demand rises 10% per floor as crawlers get desperate
ALPHA = 0.3                     # forecast smoothing weight on the newest floor
LEAD_TIME = 1                   # floors between ordering and delivery
SAFETY_Z = 1.0                  # safety stock in standard deviations of lead-time demand
SCARCITY_MARKUP = 0.6           # up to +60% on price as stock runs out
SELL_RATE = 0.4                 # the shop buys items from you at 40% of value


@dataclass
class Stock:
    on_hand: int
    forecast: float
    on_order: int = 0
    history: list = field(default_factory=list)     # total demand per floor


class Shop:
    def __init__(self, rng):
        self.rng = rng
        self.stock = {k: Stock(on_hand=0, forecast=d) for k, d in BASE_DEMAND.items()}
        for k, s in self.stock.items():
            s.on_hand = math.ceil(self.order_up_to(k))      # open fully stocked
        self.log = []                               # one row per item per floor
        self.bought = {k: 0 for k in BASE_DEMAND}   # player purchases this floor
        self.missed = {k: 0 for k in BASE_DEMAND}   # player tried to buy, sold out

    # --- Policy numbers ------------------------------------------------

    def safety_stock(self, key):
        # Poisson demand: variance equals the mean.
        return SAFETY_Z * math.sqrt(self.stock[key].forecast * LEAD_TIME)

    def reorder_point(self, key):
        return self.stock[key].forecast * LEAD_TIME + self.safety_stock(key)

    def order_up_to(self, key):
        f = self.stock[key].forecast
        return f * (LEAD_TIME + 1) + SAFETY_Z * math.sqrt(f * (LEAD_TIME + 1))

    def price(self, key):
        s = self.stock[key]
        scarcity = max(0.0, 1 - s.on_hand / max(1.0, self.order_up_to(key)))
        return max(1, round(value(key) * (1 + SCARCITY_MARKUP * scarcity)))

    @staticmethod
    def sell_price(key):
        return max(1, round(value(key) * SELL_RATE))

    # --- Player trades ----------------------------------------------------

    def buy(self, key):
        """Take one unit for the player; None if sold out."""
        s = self.stock[key]
        if s.on_hand <= 0:
            self.missed[key] += 1
            return None
        s.on_hand -= 1
        self.bought[key] += 1
        return key

    def take_back(self, key):
        if key in self.stock:
            self.stock[key].on_hand += 1

    # --- Floor turnover ---------------------------------------------------

    def _poisson(self, mean):
        # Knuth's method; fine for the small means used here.
        limit, k, p = math.exp(-mean), 0, 1.0
        while True:
            p *= self.rng.random()
            if p <= limit:
                return k
            k += 1

    def end_of_floor(self, depth):
        for key, s in self.stock.items():
            wanted = self._poisson(BASE_DEMAND[key] * (1 + DEMAND_GROWTH * depth))
            sold = min(s.on_hand, wanted)
            s.on_hand -= sold
            demand = wanted + self.bought[key] + self.missed[key]
            lost = (wanted - sold) + self.missed[key]
            s.history.append(demand)
            s.forecast = ALPHA * demand + (1 - ALPHA) * s.forecast
            delivered, s.on_hand, s.on_order = s.on_order, s.on_hand + s.on_order, 0
            rop, target = self.reorder_point(key), self.order_up_to(key)
            if s.on_hand <= rop:
                s.on_order = max(0, math.ceil(target - s.on_hand))
            self.log.append(dict(depth=depth, item=key, demand=demand, sales=sold + self.bought[key],
                                 lost=lost, delivered=delivered, on_hand=s.on_hand,
                                 forecast=round(s.forecast, 2), reorder_point=round(rop, 2),
                                 ordered=s.on_order))
            self.bought[key] = self.missed[key] = 0

    # --- Save / load ------------------------------------------------------

    def to_dict(self):
        return dict(stock={k: vars(s) for k, s in self.stock.items()}, log=self.log,
                    bought=self.bought, missed=self.missed)

    def load(self, d):
        self.stock = {k: Stock(**v) for k, v in d["stock"].items()}
        self.log, self.bought, self.missed = d["log"], d["bought"], d["missed"]
