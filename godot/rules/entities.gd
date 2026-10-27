class_name Entities
extends RefCounted
## Factories and tables for Player, Monster and Pet (the module-level functions of
## crawler/entities.py). MONSTERS, PETS and PET_QUIPS are the monsters.json, pets.json and
## pet_quips.json tables (Content.table), in Python's key order.

static func monsters() -> Dictionary:
	return Content.table("monsters")


static func pets() -> Dictionary:
	return Content.table("pets")


static func pet_quips() -> Dictionary:
	return Content.table("pet_quips")


## Combat fields for an Entity from a data row: hp, ac, attack and damage dice.
## Returns {attack, ac, dmg_n, dmg_die, dmg_bonus, dr}.
static func stat_block(d: Dictionary) -> Dictionary:
	var dmg: Array = d["dmg"]
	return {"attack": d["attack"], "ac": d["ac"], "dmg_n": dmg[0], "dmg_die": dmg[1],
		"dmg_bonus": dmg[2], "dr": d.get("dr", 0)}


## Python's `Entity(..., **stat_block(row))`: assign a stat block onto an entity.
static func apply_stat_block(e: Entity, block: Dictionary) -> void:
	e.attack = block["attack"]
	e.ac = block["ac"]
	e.dmg_n = block["dmg_n"]
	e.dmg_die = block["dmg_die"]
	e.dmg_bonus = block["dmg_bonus"]
	e.dr = block["dr"]


## Combat numbers are filled in by World.refresh_stats.
static func new_player(x: int, y: int) -> Player:
	return Player.new(x, y, "Crawler", "@", GameConfig.PLAYER_COLOUR.duplicate(), 0, 0)


## Keys and weights of monsters allowed on this floor: [keys, weights].
static func monster_table(depth: int) -> Array:
	var keys: Array = []
	var weights: Array = []
	var table := monsters()
	for k in table:
		var floors: Array = table[k]["floors"]
		if floors[0] <= depth and depth <= floors[1]:
			keys.append(k)
	for k in keys:
		weights.append(table[k]["weight"])
	return [keys, weights]


static func spawn_monster(key: String, x: int, y: int) -> Monster:
	var m: Dictionary = monsters()[key]
	var mon := Monster.new(x, y, m["name"], m["glyph"], (m["colour"] as Array).duplicate(), m["hp"], m["hp"])
	apply_stat_block(mon, stat_block(m))
	mon.key = key
	mon.xp_value = m["xp"]
	mon.ranged = m.get("ranged", 0)
	mon.save = m["save"]
	return mon


## Initiative modifier for a monster or pet: its data row's optional init key, default 0.
## Acts use their base monster's row; Headliners their boss row.
static func init_mod(entity: Entity) -> int:
	if entity is Pet:
		return pets()[(entity as Pet).species].get("init", 0)
	var mon := entity as Monster
	if mon.tier == "headliner":
		# SEAM: Python calls bosses.boss_depth(monster), int(monster.key.split("_")[1]); Bosses
		# arrives in slice S4, so the same expression is inlined here.
		var depth := int(mon.key.split("_")[1])
		return Content.boss(depth).get("init", 0)
	var row_key: String = mon.base if mon.base != "" else mon.key
	return monsters().get(row_key, {}).get("init", 0)


static func new_pet(species: String, pet_name: String, x: int, y: int) -> Pet:
	var s: Dictionary = pets()[species]
	var p := Pet.new(x, y, pet_name if pet_name != "" else s["default_name"], s["glyph"],
		(s["colour"] as Array).duplicate(), s["hp"], s["hp"])
	apply_stat_block(p, stat_block(s))
	p.species = species
	return p
