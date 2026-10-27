class_name Bosses
extends RefCounted
## Bosses in three tiers (crawler/bosses.py): Opening Acts (elite versions of the floor's
## monsters), Featured Acts (tougher elites) and one Headliner per floor. Rows come from
## bosses.json (keys "1" to "6"), acts.json ("acts", "names") and the config "bosses" section.

## An Opening Act's map reveals this far around where it fell.
static var MAP_RADIUS: int = Content.config("bosses")["MAP_RADIUS"]
## Final boss phase 2 (at half HP): {damage_bonus, ranged, adds}.
static var PHASE_TWO: Dictionary = Content.config("bosses")["PHASE_TWO"]


## BOSSES: Headliner rows, keyed by the depth as a String ("1" to "6").
static func bosses() -> Dictionary:
	return Content.table("bosses")


## ACTS: how an Act improves on its base monster, keyed "opening" and "featured".
static func acts() -> Dictionary:
	return Content.table("acts")["acts"]


## ACT_NAMES: base monster key to [Opening Act name, Featured Act name].
static func act_names() -> Dictionary:
	return Content.table("acts")["names"]


## The floor's Headliner.
static func spawn_boss(depth: int, x: int, y: int) -> Monster:
	var b: Dictionary = Content.boss(depth)
	var mon := Monster.new(x, y, b["name"], b["glyph"], (b["colour"] as Array).duplicate(), b["hp"], b["hp"])
	Entities.apply_stat_block(mon, Entities.stat_block(b))
	mon.key = "boss_%d" % depth
	mon.xp_value = b["xp"]
	mon.ranged = b.get("ranged", 0)
	mon.boss = true
	mon.save = b["save"]
	mon.tier = "headliner"
	mon.base = "boss_%d" % depth
	return mon


## [Opening Acts, Featured Acts] on a floor, as a Vector2i (x opening, y featured).
static func acts_per_floor(depth: int) -> Vector2i:
	return Vector2i(2 + PyMath.floordiv(depth, 2), PyMath.floordiv(depth, 2))


## An Act: tier "opening" or "featured", base a key of monsters.json. As in Python, the base
## monster's dr is not carried over (the Act keeps the default 0).
static func spawn_act(tier: String, base: String, x: int, y: int) -> Monster:
	var m: Dictionary = Entities.monsters()[base]
	var a: Dictionary = acts()[tier]
	var nm: String = act_names()[base][0 if tier == "opening" else 1]
	var dmg: Array = m["dmg"]
	var hp := PyMath.round_half_even(m["hp"] * a["hp"])
	var mon := Monster.new(x, y, nm, String(m["glyph"]).to_upper(), (m["colour"] as Array).duplicate(), hp, hp)
	mon.attack = m["attack"] + a["attack"]
	mon.ac = m["ac"] + a["ac"]
	mon.dmg_n = dmg[0]
	mon.dmg_die = dmg[1]
	mon.dmg_bonus = dmg[2] + a["dmg"]
	mon.key = "%s_%s" % [tier, base]
	mon.xp_value = m["xp"] * a["xp"]
	mon.ranged = m.get("ranged", 0)
	mon.boss = true
	mon.save = m["save"] + a["save"]
	mon.tier = tier
	mon.base = base
	return mon


## Floor number of a Headliner (its key is boss_<depth>).
static func boss_depth(monster: Monster) -> int:
	return int(monster.key.split("_")[1])
