"""Combat mode: starting a fight, initiative, the turn budget and ending it."""
import sys
from pathlib import Path

import pytest

from crawler import config as C
from crawler import save
from crawler.ai import cheb
from crawler.dungeon import NEIGHBOURS_8, STAIRS
from crawler.encounter import Encounter
from crawler.entities import spawn_monster
from crawler.world import World

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "analysis"))


def _world(seed=3, pet=None):
    w = World(seed=seed, pet=pet)
    w.monsters.clear()
    w.floor_items.clear()
    w.player.max_hp = w.player.hp = 999       # nobody dies by accident
    return w


def _record(w, name):
    seen = []
    w.events.subscribe(name, lambda n, d: seen.append(d))
    return seen


def _open(w, x, y):
    return w.floor.walkable(x, y) and not w.floor.is_safe(x, y) and w.floor.tiles[y][x] != STAIRS


def _row(w, n=4):
    """A non-safe tile with n open tiles to its east, so tests can line things up."""
    f = w.floor
    for y in range(f.height):
        for x in range(f.width):
            if all(_open(w, x + i, y) for i in range(n + 1)):
                return x, y
    raise AssertionError("no open row")


def _goblin(w, x, y, **kw):
    g = spawn_monster("goblin", x, y)
    g.hp = g.max_hp = kw.pop("hp", 999)
    for k, v in kw.items():
        setattr(g, k, v)
    w.monsters.append(g)
    return g


def _fight(w, gap=2, **kw):
    """Player at the west end of an open row, a goblin `gap` tiles east, combat on with the
    goblin stunned (so it waits) unless told otherwise."""
    x, y = _row(w)
    w.player.x, w.player.y = x, y
    w.update_fov()
    stunned = kw.pop("stunned", 0)
    g = _goblin(w, x + gap, y, **kw)
    w.wait()                                    # it sees you: roll for initiative
    assert w.combat and g in w.combat
    g.x, g.stunned = x + gap, stunned           # back in place if it already stepped closer
    return g


# --- Starting ----------------------------------------------------------------

def test_out_of_combat_nothing_changes():
    w = _world()
    turn = w.turn
    assert w.combat is None
    x, y = _row(w)
    w.player.x, w.player.y = x, y
    assert w.move_player(1, 0) and w.turn == turn + 1      # every act is a whole turn
    assert w.wait() and w.turn == turn + 2 and w.combat is None


def test_monster_in_view_starts_combat():
    w = _world()
    starts, rolls = _record(w, "combat_start"), _record(w, "initiative")
    g = _fight(w, gap=3)
    assert g.alerted and starts[0]["by"] == "monster"
    assert {r["who"] for r in rolls} == {"you", g.name}
    assert any(text.startswith("COMBAT! Initiative: ") for text, _ in w.messages.lines)


def test_no_combat_while_in_a_safe_room():
    w = _world()
    from crawler.ai import take_monster_turns
    w.player.x, w.player.y = w.floor.safe_room.centre
    w.update_fov()
    g = _goblin(w, w.player.x + 1, w.player.y)
    w.visible.add((g.x, g.y))
    take_monster_turns(w)
    assert g.alerted and w.combat is None and not w.join_combat(g)


def test_bump_attacking_starts_combat_and_spends_the_action():
    w = _world()
    starts = _record(w, "combat_start")
    x, y = _row(w)
    w.player.x, w.player.y = x, y
    w.update_fov()
    g = _goblin(w, x + 1, y)
    g.alerted = False
    turn = w.turn
    assert w.move_player(1, 0)
    enc = w.combat
    assert enc and g in enc and g.alerted and starts[0]["by"] == "player"
    assert not enc.has("action") and enc.has("move") and enc.has("bonus")
    assert w.turn == turn and enc.round == 1               # still your first turn
    assert not w.move_player(1, 0)                         # second attack refused
    assert "action" in w.messages.lines[-1][0] and w.turn == turn


def test_a_bomb_starts_combat_as_your_action():
    w = _world()
    x, y = _row(w)
    w.player.x, w.player.y = x, y
    w.update_fov()
    g = _goblin(w, x + 3, y)
    w.inventory.append("popper")
    assert w.use_item(len(w.inventory) - 1)
    assert w.combat and g in w.combat and not w.combat.has("action")


# --- Initiative ----------------------------------------------------------------

def test_initiative_is_seeded_and_dex_applies():
    orders = []
    for _ in range(2):
        w = _world(seed=11, pet=("dog", "Rex"))
        w.player.attrs["dex"] = 18
        rolls = _record(w, "initiative")
        g = _fight(w, gap=3)
        you = next(r for r in rolls if r["who"] == "you")
        assert you["bonus"] == w.mod("dex") == 4 and you["total"] == you["roll"] + 4
        assert w.pet in w.combat
        enc = w.combat
        totals = [enc.total(e) for e in enc.entities]
        assert totals == sorted(totals, reverse=True)
        orders.append([(r["who"], r["total"]) for r in rolls])
    assert orders[0] == orders[1]


def test_initiative_ties_go_to_the_higher_modifier_then_the_player():
    player, a, b = object(), spawn_monster("goblin", 0, 0), spawn_monster("gnawer", 0, 0)
    enc = Encounter(player)
    enc.add(b, 12, 0)                   # 12, same modifier as you: you go first
    enc.add(player, 10, 2)
    enc.add(a, 8, 4)                    # 12 with a higher modifier: goes first
    assert enc.entities == [a, player, b]
    assert enc.before(player) == [a] and enc.after(player) == [b]


def test_late_joiner_rolls_on_joining():
    w = _world()
    g = _fight(w, gap=3, stunned=9)
    rolls = _record(w, "initiative")
    late = _goblin(w, w.player.x, w.player.y + 1)
    w.join_combat(late)
    assert late in w.combat and [r["who"] for r in rolls] == [late.name]


# --- The turn budget -------------------------------------------------------------

def test_move_action_and_bonus_in_one_round():
    w = _world()
    g = _fight(w, gap=3, stunned=9)
    w.player.hp = 10
    w.inventory.append("tonic")
    turn = w.turn
    assert w.use_item(len(w.inventory) - 1)                # bonus action: drink
    w.player.hp = 10
    w.inventory.append("tonic")
    assert not w.use_item(len(w.inventory) - 1)            # only one bonus action
    assert w.move_player(1, 0) and w.turn == turn          # move
    assert not w.move_player(1, 0) and w.turn == turn      # second move refused
    assert "move" in w.messages.lines[-1][0]
    g.x = w.player.x + 1                                   # it comes to you
    assert w.move_player(1, 0)                             # attack: move + action spent ...
    assert w.turn == turn + 1                              # ... so the round ends by itself
    assert all(w.combat.budget.values())                   # and the next turn is fresh
    assert w.move_player(1, 0) and not w.move_player(1, 0)  # one attack per turn


def test_wait_ends_your_turn_early():
    w = _world()
    _fight(w, gap=3, stunned=9)
    turn = w.turn
    assert w.move_player(1, 0) and w.turn == turn
    assert w.wait() and w.turn == turn + 1 and all(w.combat.budget.values())


def test_skills_pickups_and_descend_use_the_action():
    w = _world()
    _fight(w, gap=3, stunned=9)
    w.floor_items[(w.player.x, w.player.y)] = ["sock", "sock"]
    turn = w.turn
    assert w.pickup() and not w.combat.has("action") and w.turn == turn
    assert w.choose_class("human", "analyst")
    assert not w.use_skill() and not w.scout_turns         # action already spent
    w.player.x, w.player.y = w.floor.stairs[0]
    w.has_key = True
    assert not w.descend() and w.depth == 1
    w.wait()
    assert w.use_skill() and w.scout_turns and not w.combat.has("action")


def test_monster_in_combat_steps_and_attacks_in_one_round():
    w = _world()
    hits = _record(w, "damage_taken")
    misses = _record(w, "dodged")
    g = _fight(w, gap=3, attack=100)
    g.x = w.player.x + 2                                   # two tiles off: step, then swing
    turn = w.turn
    w.wait()
    assert cheb(w.player, g) == 1 and w.turn == turn + 1
    assert len(hits) + len(misses) >= 1 and hits


def test_one_round_ticks_the_clock_once():
    w = _world()
    _fight(w, gap=3, stunned=99)
    turns = []
    w.events.subscribe("turn", lambda n, d: turns.append(d["turn"]))
    for _ in range(3):
        w.wait()
    assert len(turns) == 3


# --- Ending ----------------------------------------------------------------------

def test_killing_the_last_combatant_ends_combat():
    w = _world()
    ends = _record(w, "combat_end")
    g = _fight(w, gap=1, stunned=9, hp=1)
    w.player.attack = 100
    turn = w.turn
    assert w.move_player(1, 0) and g not in w.monsters
    assert w.combat is None and ends[0]["cause"] == "cleared"
    assert w.turn == turn + 1                              # the rest of the round plays out


def test_losing_track_ends_combat():
    w = _world()
    ends = _record(w, "combat_end")
    g = _fight(w, gap=3)
    far = next((x, y) for y in range(w.floor.height) for x in range(w.floor.width)
               if _open(w, x, y) and (x, y) not in w.visible
               and max(abs(x - w.player.x), abs(y - w.player.y)) > 30)
    g.x, g.y = far
    g.unseen_turns = C.MONSTER_LOSE_TRACK
    w.wait()
    assert w.combat is None and not g.alerted and ends[0]["cause"] == "lost_track"


def test_entering_a_safe_room_ends_combat():
    w = _world()
    f = w.floor
    dx, dy = f.safe_door
    outside = next((dx + ox, dy + oy) for ox, oy in NEIGHBOURS_8 if _open(w, dx + ox, dy + oy))
    w.player.x, w.player.y = outside
    w.update_fov()
    g = _goblin(w, *next((outside[0] + ox, outside[1] + oy) for ox, oy in NEIGHBOURS_8
                         if _open(w, outside[0] + ox, outside[1] + oy)), stunned=9)
    w.join_combat(g)
    assert w.combat
    assert w.move_player(dx - outside[0], dy - outside[1])
    assert w.in_safe_room and w.combat is None


def test_descending_ends_combat_and_uses_the_action():
    w = _world()
    _fight(w, gap=3, stunned=9)
    w.player.x, w.player.y = w.floor.stairs[0]
    w.has_key = True
    w.combat.spend("action")
    assert not w.descend() and w.depth == 1                # action already spent
    w.combat.reset_budget()
    assert w.descend() and w.depth == 2 and w.combat is None


def test_dying_ends_combat():
    w = _world()
    ends = _record(w, "combat_end")
    g = _fight(w, gap=1, attack=100)
    g.dmg_bonus = 5000
    w.riposte = 0
    w.wait()
    assert w.state == "dead" and w.combat is None and ends[-1]["cause"] == "death"


def test_never_saves_mid_combat(tmp_path):
    w = _world()
    _fight(w, gap=3, stunned=9)
    with pytest.raises(ValueError):
        save.save(w, tmp_path / "slot.json")
    assert not (tmp_path / "slot.json").exists()


def test_safe_room_time_passes_only_out_of_combat():
    w = _world()
    _fight(w, gap=3, stunned=9)
    turn = w.turn
    assert w._spend_turns(1) is False and w.turn == turn  # refuses, even under python -O
    w.player.hp = 5
    assert not w.rest() and not w.craft(0) and w.turn == turn


def test_a_bomb_that_kills_the_last_fighter_and_catches_a_bystander_keeps_the_fight():
    w = _world()
    starts, ends = _record(w, "combat_start"), _record(w, "combat_end")
    g = _fight(w, gap=3, stunned=9, hp=1)
    enc, turn = w.combat, w.turn
    by = _goblin(w, g.x + 1, g.y, alerted=False)
    w.inventory.append("popper")
    assert w.use_item(len(w.inventory) - 1) and g not in w.monsters
    assert w.combat is enc and by in enc and not starts[1:] and not ends
    assert enc.has("move") and not enc.has("action") and w.turn == turn   # budget kept
    assert w.move_player(1, 0) and w.turn == turn + 1      # move + action: the round ends once
    assert w.combat is enc and all(enc.budget.values())     # a fresh turn, one tick later


def test_moving_then_bombing_the_last_fighter_does_not_hand_back_your_move():
    w = _world()
    starts = _record(w, "combat_start")
    g = _fight(w, gap=3, stunned=9, hp=1)
    turn = w.turn
    assert w.move_player(1, 0)
    _goblin(w, g.x + 1, g.y, alerted=False)
    w.inventory.append("popper")
    assert w.use_item(len(w.inventory) - 1)
    assert len(starts) == 1 and w.turn == turn + 1         # no restart at round 1 mid-turn


def test_a_monster_that_loses_track_does_not_act_again_that_round(monkeypatch):
    monkeypatch.setattr(C, "MONSTER_WANDER_CHANCE", 1.0)    # an outsider would always wander
    w = _world()
    g = _fight(w, gap=3)
    far = next((x, y) for y in range(w.floor.height) for x in range(w.floor.width)
               if _open(w, x, y) and (x, y) not in w.visible
               and max(abs(x - w.player.x), abs(y - w.player.y)) > 30
               and all(_open(w, x + dx, y + dy) for dx, dy in NEIGHBOURS_8))
    g.x, g.y = far
    g.unseen_turns = C.MONSTER_LOSE_TRACK
    w.wait()
    assert w.combat is None and not g.alerted and (g.x, g.y) == far


def test_a_pet_ahead_in_initiative_acts_once_when_the_fight_ends_mid_turn():
    w = _world(pet=("dog", "Rex"))
    g = _fight(w, gap=1, stunned=99)
    enc, pet = w.combat, w.pet
    enc.remove(pet)
    enc.add(pet, 99, 0)                                    # the pet goes first
    pet.cooldown = 10
    w.wait()                                               # next round: the pet acts first
    assert pet.cooldown == 9
    g.hp, w.player.attack = 1, 100
    turn = w.turn
    assert w.move_player(g.x - w.player.x, g.y - w.player.y) and w.combat is None
    assert w.turn == turn + 1 and pet.cooldown == 9        # it already had its go this round


def test_haymaker_starts_combat_as_your_action():
    w = _world()
    x, y = _row(w)
    w.player.x, w.player.y = x, y
    w.update_fov()
    assert w.choose_class("human", "brawler")
    g = _goblin(w, x + 1, y, alerted=False)
    assert w.use_skill()
    assert w.combat and g in w.combat and not w.combat.has("action") and w.combat.has("move")


def test_arc_bolt_starts_combat_as_your_action():
    w = _world()
    x, y = _row(w)
    w.player.x, w.player.y = x, y
    w.update_fov()
    assert w.choose_class("human", "arcanist")
    g = _goblin(w, x + 3, y, alerted=False)
    assert w.use_skill()
    assert w.combat and g in w.combat and not w.combat.has("action") and w.combat.has("move")


def test_monsters_ahead_in_initiative_act_before_your_first_turn(monkeypatch):
    from crawler.entities import MONSTERS
    monkeypatch.setitem(MONSTERS["goblin"], "init", 50)     # it always goes first
    w = _world()
    hits = _record(w, "damage_taken")
    x, y = _row(w)
    w.player.x, w.player.y = x, y
    w.update_fov()
    g = _goblin(w, x + 2, y, attack=100)
    w.wait()                                               # it notices you: combat starts...
    assert w.combat and w.combat.entities[0] is g
    assert cheb(w.player, g) == 1 and hits                 # ...and it closes in and hits first
    assert all(w.combat.budget.values())                   # then your turn, untouched


def test_save_and_load_in_a_safe_room_gives_the_same_future():
    import json
    import bot

    def step(w, cfg):
        if w.pending_choice:
            w.choose_class(cfg["race"], cfg["cls"])
        if w.pending_offer:
            w.decline_contract()
        bot.spend_points(w, cfg["cls"])
        bot.manage_items(w)
        act, arg = bot.choose(w)
        ok = {"move": lambda: w.move_player(*arg), "descend": w.descend, "rest": w.rest,
              "pickup": w.pickup, "use": lambda: w.use_item(arg), "skill": w.use_skill,
              "revive": w.revive_pet}.get(act, w.wait)()
        w.remote_shop = False
        if not ok:
            w.wait()

    def sig(w):
        return (w.turn, w.state, w.depth, w.player.hp, (w.player.x, w.player.y), w.rng.random(),
                sorted((m.key, m.x, m.y, m.hp) for m in w.monsters))

    for seed in range(1, 10):                            # the first run that reaches floor 2
        cfg = bot.run_config(seed)
        w = World(seed, pet=(cfg["pet"], ""))
        for i in range(20000):
            step(w, cfg)
            if w.state != "playing" or (w.in_safe_room and w.combat is None and w.depth >= 2):
                break
        if w.state == "playing":
            break
    assert w.state == "playing" and w.in_safe_room
    b = save.from_dict(json.loads(json.dumps(save.to_dict(w))))
    fights = [_record(x, "combat_start") for x in (w, b)]
    for _ in range(600):
        for x in (w, b):
            if x.state == "playing":
                step(x, cfg)
    assert fights[0] and len(fights[0]) == len(fights[1])  # later fights happen, identically
    assert sig(w) == sig(b)


# --- Bot -------------------------------------------------------------------------

@pytest.mark.parametrize("seed", [0, 1, 2])
def test_bot_finishes_runs_in_combat_mode(seed):
    from bot import play
    w, _ = play(seed, max_steps=60_000)
    assert w.state in ("dead", "victory")


# --- Attacks of opportunity ------------------------------------------------------

def _room(w):
    """A non-safe tile with open ground two tiles west, three east and one above and below."""
    f = w.floor
    for y in range(f.height):
        for x in range(f.width):
            if all(_open(w, x + dx, y + dy) for dx in range(-2, 4) for dy in (-1, 0, 1)):
                return x, y
    raise AssertionError("no open room")


def _melee_fight(w, **kw):
    """You with a goblin right next to you (east), in combat, your turn fresh."""
    x, y = _room(w)
    w.player.x, w.player.y = x, y
    w.update_fov()
    g = _goblin(w, x + 1, y, **kw)
    assert w.join_combat(g)
    return x, y, g


def test_stepping_away_provokes_one_attack_a_round():
    w = _world()
    aoo = _record(w, "opportunity_attack")
    x, y, g = _melee_fight(w, attack=100)
    assert w.provokers(-1, 0) == [g] and w.provokers(0, 1) == []
    hp = w.player.hp
    assert w.move_player(-1, 0)
    assert aoo == [dict(attacker="goblin", target="player", hit=True)] and w.player.hp < hp
    assert any("Attack of opportunity" in t for t, _ in w.messages.lines)
    assert not w.move_player(-1, 0) and len(aoo) == 1      # move spent: no second step
    w.wait()                                               # its turn: it closes in again
    assert cheb(w.player, g) == 1
    px = w.player.x
    assert w.move_player(-1, 0) and w.player.x == px - 1   # next round it provokes again
    assert len(aoo) == 2


def test_moving_along_its_side_does_not_provoke():
    w = _world()
    aoo = _record(w, "opportunity_attack")
    _melee_fight(w)
    assert w.move_player(0, 1) and not aoo


def test_each_adjacent_monster_gets_its_own_attack():
    w = _world()
    aoo = _record(w, "opportunity_attack")
    x, y, g = _melee_fight(w)
    g2 = _goblin(w, x + 1, y + 1)
    w.join_combat(g2)
    assert w.move_player(-1, 0)
    assert len(aoo) == 2 and all(a["attacker"] == "goblin" for a in aoo)


def test_riposte_parries_an_attack_of_opportunity():
    w = _world()
    aoo = _record(w, "opportunity_attack")
    _melee_fight(w, attack=100)
    w.riposte, hp = 2, w.player.hp
    assert w.move_player(-1, 0)
    assert w.riposte == 1 and aoo[0]["hit"] is False and w.player.hp == hp


def test_a_stunned_monster_cannot_react_and_a_reaction_lasts_until_its_turn():
    w = _world()
    aoo = _record(w, "opportunity_attack")
    x, y, g = _melee_fight(w, stunned=1)
    assert w.provokers(-1, 0) == [] and w.move_player(-1, 0) and not aoo
    w2 = _world()
    aoo2 = _record(w2, "opportunity_attack")
    x, y, g = _melee_fight(w2)
    w2.combat.react(g)                                     # already used this round
    assert w2.move_player(-1, 0) and not aoo2


def test_a_monster_leaving_your_reach_gives_you_and_your_pet_a_free_attack():
    w = _world(pet=("dog", "Rex"))
    aoo = _record(w, "opportunity_attack")
    x, y, g = _melee_fight(w)
    w.pet.x, w.pet.y = x + 1, y + 1                        # the dog is next to it too
    assert w.pet in w.combat
    assert w.opportunity_attacks(g, x + 3, y)
    assert {(a["attacker"], a["target"]) for a in aoo} == {("player", "goblin"), ("pet", "goblin")}
    assert w.opportunity_attacks(g, x + 3, y) and len(aoo) == 2   # reactions used up


def test_your_pet_leaving_a_monster_provokes_it():
    w = _world(pet=("dog", "Rex"))
    aoo = _record(w, "opportunity_attack")
    x, y, g = _melee_fight(w)
    w.pet.x, w.pet.y = x + 2, y
    w.opportunity_attacks(w.pet, x + 3, y + 1)
    assert [(a["attacker"], a["target"]) for a in aoo] == [("goblin", "pet")]


def test_swapping_with_your_pet_does_not_provoke():
    w = _world(pet=("dog", "Rex"))
    aoo = _record(w, "opportunity_attack")
    x, y, g = _melee_fight(w)
    w.pet.x, w.pet.y = x - 1, y
    assert w.move_player(-1, 0) and (w.pet.x, w.pet.y) == (x, y) and not aoo


def test_nothing_provokes_out_of_combat():
    w = _world()
    aoo = _record(w, "opportunity_attack")
    x, y = _room(w)
    w.player.x, w.player.y = x, y
    g = _goblin(w, x + 1, y, alerted=False)
    assert w.provokers(-1, 0) == [] and w.threats() == []
    assert w.move_player(-1, 0) and not aoo


def test_a_monster_cut_down_as_it_retreats_does_not_move():
    from crawler.ai import take_combat_turn
    w = _world()
    x, y, g = _melee_fight(w, hp=1)
    w.player.attack = 100
    assert not w.opportunity_attacks(g, x + 3, y) and g not in w.monsters


# --- Slice 5 review fixes ------------------------------------------------------------

def test_the_combat_banner_shows_for_two_of_your_rounds():
    w = _world()
    _fight(w, gap=3, stunned=99)
    stamp = next(t[0] for t in w.toasts if t[2] == "combat")

    def live():
        return w.turn - stamp < 2
    assert live()
    w.wait()
    assert live()
    w.wait()
    assert not live()


def test_expired_toasts_are_pruned():
    w = _world()
    for i in range(50):
        w.add_toast(f"t{i}", "silver")
        w._tick_clock()
    assert len(w.toasts) <= C.TOAST_TURNS + 1


def test_a_fight_with_only_a_lost_outsider_left_ends():
    w = _world()
    ends = _record(w, "combat_end")
    g = _fight(w, gap=1, stunned=9, hp=1)
    p = w.player
    spot = next((x, y) for y in range(w.floor.height) for x in range(w.floor.width)
                if _open(w, x, y) and (x, y) not in w.visible
                and 6 < max(abs(x - p.x), abs(y - p.y)) <= 20)
    o = _goblin(w, *spot, alerted=True, unseen_turns=C.MONSTER_LOSE_TRACK)
    w.player.attack = 100
    assert w.move_player(1, 0) and g not in w.monsters
    assert w.combat is not None                            # it's still after you...
    w.wait()
    assert not o.alerted and w.combat is None and ends[-1]["cause"] == "lost_track"


def _safe_edge(w):
    """A safe tile s with a non-safe walkable neighbour o (s + d) and a safe tile behind (s - d)."""
    f = w.floor
    for y in range(f.height):
        for x in range(f.width):
            if not f.is_safe(x, y) or not f.walkable(x, y):
                continue
            for dx, dy in NEIGHBOURS_8:
                if _open(w, x + dx, y + dy) and f.walkable(x - dx, y - dy) \
                        and f.is_safe(x - dx, y - dy):
                    return (x, y), (dx, dy)
    raise AssertionError("no safe-room edge")


def test_no_attacks_of_opportunity_into_or_out_of_a_safe_room():
    w = _world(pet=("dog", "Rex"))
    aoo = _record(w, "opportunity_attack")
    x, y, g = _melee_fight(w, attack=100)
    (sx, sy), (dx, dy) = _safe_edge(w)
    w.pet.x, w.pet.y = sx, sy                              # the pet on the safe side...
    g.x, g.y = sx + dx, sy + dy                            # ...the goblin just outside
    hp = w.pet.hp
    assert w.opportunity_attacks(w.pet, sx - dx, sy - dy)  # pet steps deeper in: no swing
    assert w.opportunity_attacks(g, g.x + dx, g.y + dy)    # goblin backs off: the pet can't swing out
    assert not aoo and w.pet.hp == hp


def test_no_warning_once_your_move_is_spent():
    w = _world()
    x, y, g = _melee_fight(w)
    assert w.threats() == [g]
    w.combat.spend("move")
    assert w.threats() == [] and w.provokers(-1, 0) == []


def test_system_lines_only_when_you_are_caught(monkeypatch):
    from crawler import showrunner
    monkeypatch.setattr(C, "SASS_LEVEL", 10)
    monkeypatch.setitem(showrunner.SPEAK_CHANCE, "opportunity_attack", 5.0)
    w = _world()
    w.messages.lines.clear()
    w.events.emit("opportunity_attack", attacker="goblin", target="pet", hit=True)
    w.events.emit("opportunity_attack", attacker="pet", target="goblin", hit=True)
    w.events.emit("opportunity_attack", attacker="goblin", target="player", hit=False)   # a miss
    assert not any(t.startswith("SYSTEM:") for t, _ in w.messages.lines)
    w.events.emit("opportunity_attack", attacker="goblin", target="player", hit=True)
    assert any(t.startswith("SYSTEM:") for t, _ in w.messages.lines)


def test_bot_flees_through_a_provoke_only_when_hurt():
    import bot
    w = _world()
    aoo = _record(w, "opportunity_attack")
    x, y, g = _melee_fight(w)
    act, arg = bot.choose(w)
    assert act == "move" and (x + arg[0], y + arg[1]) == (g.x, g.y)   # healthy: attack
    w.player.hp = int(w.player.max_hp * 0.2)
    w.inventory.clear()
    act, arg = bot.choose(w)
    assert act == "move" and (x + arg[0], y + arg[1]) != (g.x, g.y)   # hurt, no potion: run
