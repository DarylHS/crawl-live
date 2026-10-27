class_name Loot
extends RefCounted
## Loot boxes (crawler/loot.py): five tiers, each a weighted roll table of four items, from
## loot_boxes.json. Odds are exact (weight / total).

static var TIERS: Array = Content.config("loot")["TIERS"]
## Boxes of one tier traded for one of the next tier.
static var TRADE_UP_COST: int = Content.config("loot")["TRADE_UP_COST"]
## Rerolling costs this share of the box's expected value.
static var REROLL_FEE_FRAC: float = Content.config("loot")["REROLL_FEE_FRAC"]


## [[item_key, probability], ...] for a tier.
static func odds(tier: String) -> Array:
	var table: Array = Content.box(tier)["table"]
	var total := 0
	for row in table:
		total += row["weight"]
	var out: Array = []
	for row in table:
		out.append([row["item"], float(row["weight"]) / total])
	return out


## One weighted draw from the tier's table (one PyRandom.choices call).
static func roll_box(tier: String, rng: PyRandom) -> String:
	var keys: Array = []
	var weights: Array = []
	for row in Content.box(tier)["table"]:
		keys.append(row["item"])
		weights.append(row["weight"])
	var picked: Array = rng.choices(keys, weights)
	return picked[0]


## [expected value, standard deviation] of a box's contents, in gold. Python sum() is
## PyMath.fsum_py; `x ** 2` and `var ** 0.5` are libm pow, as in CPython.
static func box_stats(tier: String) -> Array:
	var rows := odds(tier)
	var terms: Array = []
	for r in rows:
		terms.append(r[1] * Items.value(r[0]))
	var ev := PyMath.fsum_py(terms)
	var vterms: Array = []
	for r in rows:
		vterms.append(r[1] * pow(Items.value(r[0]) - ev, 2.0))
	var variance := PyMath.fsum_py(vterms)
	return [ev, pow(variance, 0.5)]


## The next tier up, or "" for none (Python None).
static func next_tier(tier: String) -> String:
	var i := TIERS.find(tier)
	if i < 0:
		push_error("Loot.next_tier: unknown tier %s (Python raises ValueError)" % tier)
		return ""
	return TIERS[i + 1] if i + 1 < TIERS.size() else ""


static func reroll_fee(tier: String) -> int:
	return maxi(2, PyMath.round_half_even(REROLL_FEE_FRAC * box_stats(tier)[0]))
