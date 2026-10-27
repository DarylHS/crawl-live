"""Gold, box odds and gambles, the shop sim, sponsor contracts, fun facts, run report."""
import math
import random

import pytest

from crawler import config as C
from crawler import save
from crawler.contracts import CONTRACTS, preview
from crawler.dungeon import NEIGHBOURS_8
from crawler.entities import spawn_monster
from crawler.items import ITEMS
from crawler.loot import TIERS, TRADE_UP_COST, box_stats, odds, reroll_fee, roll_box
from crawler.report import run_report
from crawler.shop import BASE_DEMAND, Shop
from crawler.world import World


def _safe(w):
    w.player.x, w.player.y = w.floor.safe_room.centre
    w.update_fov()


def _adjacent_monster(w, key="gnawer", hp=None):
    p = w.player
    for dx, dy in NEIGHBOURS_8:
        x, y = p.x + dx, p.y + dy
        if w.floor.walkable(x, y) and not w.floor.is_safe(x, y):
            m = spawn_monster(key, x, y)
            if hp is not None:
                m.hp = hp
            w.monsters.append(m)
            return m, (dx, dy)
    raise AssertionError("no free tile")


# --- Gold and box maths -------------------------------------------------------

def test_every_item_has_a_value():
    assert all(it["value"] > 0 for it in ITEMS.values())


def test_kills_pay_gold():
    w = World(seed=1)
    w.monsters.clear()
    m, d = _adjacent_monster(w, hp=1)
    w.player.attack = 100
    for _ in range(5):
        if m not in w.monsters:
            break
        w.move_player(*d)
    assert w.gold > 0 and w.floor_stats[-1]["gold"] == w.gold


def test_box_stats_match_simulation():
    rng = random.Random(3)
    for tier in TIERS:
        ev, sd = box_stats(tier)
        vals = [ITEMS[roll_box(tier, rng)]["value"] for _ in range(20000)]
        mean = sum(vals) / len(vals)
        var = sum((v - mean) ** 2 for v in vals) / len(vals)
        assert mean == pytest.approx(ev, rel=0.03)
        assert math.sqrt(var) == pytest.approx(sd, rel=0.05)


def test_trade_up_in_safe_room():
    w = World(seed=2)
    w.boxes = ["bronze"] * TRADE_UP_COST
    assert not w.trade_up("bronze")                     # not in a safe room
    _safe(w)
    assert w.trade_up("bronze") and w.boxes == ["silver"]
    w.boxes = ["legendary"] * 3
    assert not w.trade_up("legendary")                  # nothing above legendary


def test_reroll_swaps_the_item_and_charges_the_fee():
    w = World(seed=4)
    _safe(w)
    w.boxes = ["platinum"]
    w.gold = 100
    assert w.open_box("platinum")
    first = w.last_reveal[1]
    assert w.reroll()
    assert w.gold == 100 - reroll_fee("platinum")
    assert len(w.inventory) == 1 and w.box_log[-1]["rerolled"]
    assert first not in w.inventory or w.inventory == [w.last_reveal[1]]
    w.gold = 0
    assert not w.reroll()                               # can't afford another


# --- Shop sim -----------------------------------------------------------------

def test_shop_opens_fully_stocked_with_sane_policy():
    shop = Shop(random.Random(1))
    for key in BASE_DEMAND:
        s = shop.stock[key]
        assert s.on_hand >= shop.reorder_point(key)
        assert shop.order_up_to(key) > shop.reorder_point(key) > 0
        assert shop.price(key) == ITEMS[key]["value"]   # no markup when well stocked


def test_shop_restocks_after_reorder_point_with_one_floor_lead_time():
    shop = Shop(random.Random(2))
    s = shop.stock["tonic"]
    s.on_hand = 0
    shop.end_of_floor(1)
    assert s.on_order > 0 and s.on_hand == 0            # ordered, not yet delivered
    ordered = s.on_order
    shop.end_of_floor(2)
    assert shop.log[-len(BASE_DEMAND):][0]["delivered"] == ordered


def test_stockout_counts_lost_sales_and_raises_price():
    shop = Shop(random.Random(3))
    s = shop.stock["elixir"]
    full_price = shop.price("elixir")
    s.on_hand = 1
    assert shop.price("elixir") > full_price            # scarcity markup
    assert shop.buy("elixir") and not shop.buy("elixir")
    shop.end_of_floor(1)
    row = next(r for r in shop.log if r["item"] == "elixir")
    assert row["lost"] >= 1 and row["sales"] >= 1


def test_forecast_follows_demand():
    shop = Shop(random.Random(4))
    s = shop.stock["tonic"]
    before = s.forecast
    shop.bought["tonic"] = 20                           # a huge spike
    shop.end_of_floor(1)
    assert s.forecast > before


def test_buying_and_selling_in_world():
    w = World(seed=5)
    w.gold = 50
    assert not w.shop_buy("tonic")                      # not in a safe room
    _safe(w)
    price = w.shop.price("tonic")
    assert w.shop_buy("tonic") and w.gold == 50 - price and w.inventory == ["tonic"]
    assert w.shop_sell(0) and w.inventory == [] and w.gold > 50 - price
    w.gold = 0
    assert not w.shop_buy("elixir")                     # can't afford it


def test_shop_turns_over_between_floors():
    w = World(seed=6)
    w.new_floor(2)
    assert len(w.shop.log) == len(BASE_DEMAND)


# --- Contracts ----------------------------------------------------------------

def test_contracts_offered_from_floor_two():
    offers = 0
    for seed in range(30):
        w = World(seed=seed)
        assert w.pending_offer is None
        w.new_floor(2)
        offers += w.pending_offer is not None
    assert 10 < offers < 30                              # OFFER_CHANCE is 70%


def test_accepting_hazard_pay_changes_monsters_and_gold():
    w = World(seed=7)
    w.new_floor(2)
    w.pending_offer = "hazard_pay"
    before = {id(m): (m.dmg_bonus, m.max_hp) for m in w.monsters}
    assert preview(w, "hazard_pay")
    w.accept_contract()
    assert w.contract == "hazard_pay" and w.pending_offer is None and "gold" in w.boxes
    for m in w.monsters:
        p, hp = before[id(m)]
        assert m.dmg_bonus == p + 2 and m.max_hp == round(hp * 1.25)
    w.new_floor(3)
    assert w.contract is None                            # one floor only


def test_snack_sprint_shortens_the_timer():
    w = World(seed=8)
    w.new_floor(2)
    w.pending_offer = "snack_sprint"
    t = w.timer
    w.accept_contract()
    assert w.timer == round(t * 0.8)


def test_every_contract_previews():
    w = World(seed=9)
    w.new_floor(2)
    for key in CONTRACTS:
        assert all(isinstance(line, str) for line in preview(w, key))
    # Preview must not leave monsters modified.
    assert all(m.dmg_bonus == spawn_monster(m.key, 0, 0).dmg_bonus for m in w.monsters if not m.boss)


# --- Fun facts ----------------------------------------------------------------

def test_miss_streak_fun_fact():
    w = World(seed=10)
    for _ in range(6):
        w.events.emit("player_attack", target="goblin", chance=0.8, hit=False, crit=False)
    text = [t for t, _ in w.messages.recent(10) if t.startswith("FUN FACT")]
    assert text and "no memory" in text[-1]


def test_box_drought_fun_fact():
    w = World(seed=11)
    rarest = min(odds("bronze"), key=lambda r: r[1])[0]
    common = max(odds("bronze"), key=lambda r: r[1])[0]
    assert rarest != common
    for _ in range(3):
        w.events.emit("box_opened", tier="bronze", item=common, rerolled=False)
    assert any("isn't 'due'" in t for t, _ in w.messages.recent(10))


def test_fun_facts_are_rate_limited():
    w = World(seed=12)
    w.events.emit("player_attack", target="g", chance=0.5, hit=True, crit=True)
    w.events.emit("contract_accepted", contract="gloop_blitz", depth=2)
    facts = [t for t, _ in w.messages.recent(20) if t.startswith("FUN FACT")]
    assert len(facts) == 1


# --- Report and save ----------------------------------------------------------

def test_run_report_data():
    w = World(seed=13)
    _safe(w)
    w.boxes = ["silver", "gold"]
    w.open_box("silver")
    w.open_box("gold")
    for _ in range(25):
        w.wait()
    rep = run_report(w)
    assert len(rep["box_expected"]) == 2 and rep["box_expected"][-1] == pytest.approx(
        box_stats("silver")[0] + box_stats("gold")[0], abs=0.02)
    assert rep["damage_by_floor"][0][0] == 1
    assert rep["viewers"][-1][0] == w.turn


def test_save_round_trip_keeps_phase4_state(tmp_path):
    w = World(seed=14, pet=("dog", "Rex"))
    w.player.max_hp = w.player.hp = 1000
    w.gold = 77
    w.new_floor(2)
    w.pending_offer = "gloop_blitz"
    w.accept_contract()
    _safe(w)
    w.boxes = ["silver"]
    w.open_box("silver")
    path = tmp_path / "slot.json"
    save.save(w, path)
    v = save.load(path)
    assert save.to_dict(v) == save.to_dict(w)
    for world in (w, v):                                 # identical future, shop included
        world.new_floor(3)
        world.new_floor(4)
    assert save.to_dict(v) == save.to_dict(w)
