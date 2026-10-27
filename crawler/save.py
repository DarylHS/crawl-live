"""Save and load a run as JSON (one slot, safe rooms only).

A loaded World is built normally (so event subscriptions exist) and then has
its state overwritten, including all RNG states, so play continues exactly
where it left off.
"""
import json
from dataclasses import asdict
from pathlib import Path

from .dungeon import Floor, Room
from .entities import Monster, Pet, Player
from .world import World

SAVE_DIR = Path(__file__).resolve().parents[1] / "saves"
SAVE_FILE = SAVE_DIR / "slot1.json"
VERSION = 7


def _rng_state(rng):
    return list(rng.getstate()[1]), rng.getstate()[2]


def _set_rng(rng, state):
    internal, gauss = state
    rng.setstate((3, tuple(internal), gauss))


def _entity(cls, d):
    d = dict(d)
    d["colour"] = tuple(d["colour"])
    return cls(**d)


def to_dict(w):
    if w.combat is not None:
        raise ValueError("Can't save mid-combat")      # saves are safe-room only, which ends it
    f = w.floor
    sr = w.showrunner
    return dict(
        version=VERSION, seed=w.seed, turn=w.turn, state=w.state, death_cause=w.death_cause,
        depth=w.depth, timer=w.timer, timer_max=w.timer_max, warnings_left=w._warnings_left,
        was_safe=w._was_safe, inventory=w.inventory, equipment=w.equipment, boxes=w.boxes,
        box_reasons=w.box_reasons, last_reason=w.last_reason,
        floor_items=[[x, y, keys] for (x, y), keys in w.floor_items.items()],
        last_reveal=w.last_reveal, toasts=w.toasts, messages=list(w.messages.lines),
        race=w.race, cls=w.cls, pending_choice=w.pending_choice,
        skill_cooldown=w.skill_cooldown, scout_turns=w.scout_turns, exit_sealed=w.exit_sealed,
        has_key=w.has_key, stairs_open_turn=w.stairs_open_turn,
        stairs_announced=w._stairs_announced, next_spawn=w._next_spawn, spawn_cap=w._spawn_cap,
        gold=w.gold, contract=w.contract, pending_offer=w.pending_offer,
        hero_name=w.hero_name, gender=w.gender, backstory=w.backstory, hype_turns=w.hype_turns,
        practice=w.training.to_dict(),
        riposte=w.riposte, remote_shop=w.remote_shop, plant_fed_floor=w._plant_fed_floor,
        floor_stats=w.floor_stats, box_log=w.box_log, shop=w.shop.to_dict(),
        shop_rng=_rng_state(w.shop.rng), deal_rng=_rng_state(w.deal_rng),
        funfacts=dict(last_turn=w.funfacts.last_turn, said=sorted(w.funfacts.said),
                      miss_streak=w.funfacts.miss_streak,
                      streak_chance=w.funfacts.streak_chance, drought=w.funfacts.drought),
        player=asdict(w.player), pet=asdict(w.pet) if w.pet else None,
        monsters=[asdict(m) for m in w.monsters],
        floor=dict(width=f.width, height=f.height, depth=f.depth, tiles=f.tiles, safe=f.safe,
                   explored=f.explored, rooms=[asdict(r) for r in f.rooms],
                   start_room=f.rooms.index(f.start_room), safe_room=f.rooms.index(f.safe_room),
                   stairs=f.stairs, safe_door=f.safe_door,
                   furniture=[[x, y, kind] for (x, y), kind in f.furniture.items()]),
        rng=_rng_state(w.rng), loot_rng=_rng_state(w.loot_rng),
        achievements=dict(unlocked=w.achievements.unlocked,
                          kills=w.achievements.tracker.kills,
                          pickups=w.achievements.tracker.pickups,
                          equipped=sorted(w.achievements.tracker.equipped)),
        showrunner=dict(viewers=sr.viewers, peak=sr.peak, history=sr.history,
                        kill_turns=sr._kill_turns, last_fun=sr._last_fun, gift_idx=sr._gift_idx,
                        last_flee_quip=sr._last_flee_quip, samples=sr.samples,
                        rng=_rng_state(sr.rng)),
    )


def from_dict(d):
    if d.get("version") != VERSION:
        raise ValueError(f"Unsupported save version {d.get('version')}")
    w = World(d["seed"])
    # Rebuild from scratch: drop anything the constructor's first floor produced.
    w.messages.lines.clear()
    for key in ("turn", "state", "death_cause", "depth", "timer", "timer_max", "inventory",
                "boxes", "race", "cls", "pending_choice", "skill_cooldown", "scout_turns",
                "exit_sealed", "gold", "contract", "pending_offer", "floor_stats", "box_log",
                "hero_name", "gender", "backstory", "hype_turns", "riposte", "remote_shop",
                "has_key", "stairs_open_turn", "box_reasons", "last_reason"):
        setattr(w, key, d[key])
    w._stairs_announced, w._next_spawn = d["stairs_announced"], d["next_spawn"]
    w._spawn_cap = d["spawn_cap"]
    w._warnings_left, w._was_safe = d["warnings_left"], d["was_safe"]
    w._plant_fed_floor = d["plant_fed_floor"]
    w.training.load(d["practice"])
    w.equipment = d["equipment"]
    w.floor_items = {(x, y): keys for x, y, keys in d["floor_items"]}
    w.last_reveal = tuple(d["last_reveal"]) if d["last_reveal"] else None
    w.toasts = [tuple(t) for t in d["toasts"]]
    for text, colour in d["messages"]:
        w.messages.add(text, tuple(colour))
    w.player = _entity(Player, d["player"])
    w.pet = _entity(Pet, d["pet"]) if d["pet"] else None
    w.monsters = [_entity(Monster, m) for m in d["monsters"]]

    fd = d["floor"]
    f = Floor(fd["width"], fd["height"], fd["depth"])
    f.tiles, f.safe, f.explored = fd["tiles"], fd["safe"], fd["explored"]
    f.rooms = [Room(**r) for r in fd["rooms"]]
    f.start_room, f.safe_room = f.rooms[fd["start_room"]], f.rooms[fd["safe_room"]]
    f.stairs = [tuple(s) for s in fd["stairs"]]
    f.safe_door = tuple(fd["safe_door"])
    f.furniture = {(x, y): kind for x, y, kind in fd["furniture"]}
    w.floor = f

    _set_rng(w.rng, d["rng"])
    _set_rng(w.loot_rng, d["loot_rng"])
    _set_rng(w.deal_rng, d["deal_rng"])
    w.shop.load(d["shop"])
    _set_rng(w.shop.rng, d["shop_rng"])
    ff, f2 = w.funfacts, d["funfacts"]
    ff.last_turn, ff.said, ff.miss_streak = f2["last_turn"], set(f2["said"]), f2["miss_streak"]
    ff.streak_chance, ff.drought = f2["streak_chance"], f2["drought"]
    a = d["achievements"]
    w.achievements.unlocked = a["unlocked"]
    t = w.achievements.tracker
    t.kills, t.pickups, t.equipped = a["kills"], a["pickups"], set(a["equipped"])
    s, sr = d["showrunner"], w.showrunner
    sr.viewers, sr.peak, sr.history = s["viewers"], s["peak"], [tuple(h) for h in s["history"]]
    sr._kill_turns, sr._last_fun, sr._gift_idx = s["kill_turns"], s["last_fun"], s["gift_idx"]
    sr._last_flee_quip, sr.samples = s["last_flee_quip"], [tuple(x) for x in s["samples"]]
    _set_rng(sr.rng, s["rng"])
    w.update_fov()
    return w


def save(world, path=SAVE_FILE):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(to_dict(world)))
    tmp.replace(path)                   # atomic: a crash mid-write never corrupts the slot


def load(path=SAVE_FILE):
    return from_dict(json.loads(Path(path).read_text()))


def has_save(path=SAVE_FILE):
    return Path(path).exists()
