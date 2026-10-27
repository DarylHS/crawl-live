class_name Crafting
extends RefCounted
## Crafting recipes for the safe-room bench (crawler/crafting.py): each turns two items into one.

## Floor time spent at the bench per craft.
static var CRAFT_TURNS: int = Content.config("crafting")["CRAFT_TURNS"]


## RECIPES: [{key, name, needs, makes, desc}, ...] from recipes.json.
static func recipes() -> Array:
	return Content.table("recipes")


## True when the inventory holds every needed item (counting duplicates).
static func can_craft(recipe: Dictionary, inventory: Array) -> bool:
	var have := {}
	for k in inventory:
		have[k] = have.get(k, 0) + 1
	var need := {}
	for k in recipe["needs"]:
		need[k] = need.get(k, 0) + 1
	for k in need:
		if have.get(k, 0) < need[k]:
			return false
	return true
