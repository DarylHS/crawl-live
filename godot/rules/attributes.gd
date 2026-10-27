class_name Attributes
extends RefCounted
## The five crawler attributes and the numbers derived from them (crawler/attributes.py).
##
## Scores sit around 10; the modifier is (score - 10) // 2, as in tabletop RPGs, so a 14 gives +2
## and an 8 gives -1. Crawlers get POINTS_PER_LEVEL points to spend at each level-up (and
## START_POINTS at the start). Race, class and backstory nudge scores through an `attrs`
## dictionary in their data. The ATTRS table is attributes.json (`Attributes.table()`), the
## numeric constants are the config.json "attributes" section.

static func _c(name: String) -> int:
	return Content.config("attributes")[name]


static var BASE_SCORE: int = _c("BASE_SCORE")
static var START_POINTS: int = _c("START_POINTS")
static var POINTS_PER_LEVEL: int = _c("POINTS_PER_LEVEL")
static var MAX_SCORE: int = _c("MAX_SCORE")


## ATTRS: {"str": {"name": "Strength", "short": "STR", "does": "..."}, ...} in Python order.
static func table() -> Dictionary:
	return Content.table("attributes")


## list(ATTRS): attribute keys in Python order.
static func keys() -> Array:
	return table().keys()


## Modifier for a score: (score - 10) // 2. mod(9) == -1.
static func mod(score: int) -> int:
	return PyMath.floordiv(score - 10, 2)


## Training bonus to hit, to weapon damage and to save DCs: +2 at level 1, +1 every 4 levels.
static func proficiency(level: int) -> int:
	return 2 + PyMath.floordiv(level - 1, 4)


static func fmt_mod(m: int) -> String:
	return PyFmt.signed_int(m)
