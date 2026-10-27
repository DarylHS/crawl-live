class_name Items
extends RefCounted
## Item data (crawler/items.py). Everything the player can carry is a Dictionary in
## items.json "items"; kind: weapon | armour | potion | bomb | junk. value is the base price in gold.

static var FISTS: Dictionary = Content.fists()


## ITEMS: key to item row, in Python order.
static func items() -> Dictionary:
	return Content.table("items")["items"]


## Floor loot and monster drops that can appear at this depth: [keys, weights].
static func floor_loot_table(depth: int) -> Array:
	var keys: Array = []
	var weights: Array = []
	for row in Content.table("floor_loot"):
		if row["min_floor"] <= depth:
			keys.append(row["item"])
			weights.append(row["weight"])
	return [keys, weights]


static func glyph(key: String) -> String:
	return Content.config("items")["GLYPHS"][items()[key]["kind"]]


## One-line stat summary for menus.
static func describe(key: String) -> String:
	var it: Dictionary = items()[key]
	var bits: PackedStringArray = PackedStringArray()
	if it["kind"] == "weapon":
		var d: Array = it["dice"]
		bits.append(Dice.fmt(d[0], d[1], it.get("dmg", 0)) + (" finesse" if it["style"] == "blade" else ""))
		if PyMath.truthy(it.get("hit", 0)):
			bits.append("%s to hit" % PyFmt.signed_int(it["hit"]))
	if PyMath.truthy(it.get("ac", 0)):
		var cap: Variant = it.get("max_dex")
		var tail := ""
		if cap == null:
			tail = ""
		elif cap == 0:
			tail = ", no DEX bonus"
		else:
			tail = ", DEX bonus max +%d" % cap
		bits.append("+%d AC" % it["ac"] + tail)
	if it.has("heal"):
		bits.append("heals %d" % it["heal"])
	if it["kind"] == "bomb":
		var d2: Array = it["dice"]
		bits.append("%s (avg %s) r%d" % [Dice.fmt(d2[0], d2[1]), PyFmt.fixed(Dice.average(d2[0], d2[1]), 0), it["radius"]])
	var text := ", ".join(bits)
	return text if text != "" else it["desc"]


static func value(key: String) -> int:
	return items()[key]["value"]
