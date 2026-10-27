class_name Contracts
extends RefCounted
## Sponsor contracts: a deal offered at the start of a floor, for that floor only
## (crawler/contracts.py). Each one trades a reward for a risk; preview() turns the terms into
## numbers from the player's own run so far.
##
## SEAM (World, slice S6): `world` is duck-typed. effect() reads `world.contract` (a contract key
## String, or "" / null for none). preview() reads `world.contract`-free state only: `floor_stats`
## (Array of Dictionary with gold, viewers_start, viewers_end), `monsters` (Array of Monster),
## `player`, `timer` (int) and the method `timer_text(turns := <timer>) -> String` (Python's
## World.timer_text(turns=None); the argument must be optional). tests/support/s4_support.gd has a
## stand-in with those members.

static var OFFER_FROM_FLOOR: int = Content.config("contracts")["OFFER_FROM_FLOOR"]
static var OFFER_CHANCE: float = Content.config("contracts")["OFFER_CHANCE"]


## CONTRACTS: key to contract row, in Python order (contracts.json).
static func contracts() -> Dictionary:
	return Content.table("contracts")


## A modifier from the active contract, or the default.
static func effect(world: Variant, effect_name: String, default: Variant = 1) -> Variant:
	var active: Variant = world.contract
	if active == null or active == "":
		return default
	var c: Dictionary = contracts().get(active, {})
	if c.is_empty():
		return default
	return c.get(effect_name, default)


## Plain-language numbers for this deal, based on the run so far.
static func preview(world: Variant, key: String) -> PackedStringArray:
	var c: Dictionary = contracts()[key]
	var lines := PackedStringArray()
	var stats: Array = world.floor_stats
	var done: Array = stats.slice(0, maxi(stats.size() - 1, 0))
	if c.has("bonus_box"):
		var st := Loot.box_stats(c["bonus_box"])
		lines.append("Signing bonus: a %s box, worth %s gold on average (give or take %s)." % [
				Content.box(c["bonus_box"])["name"], PyFmt.fixed(st[0], 0), PyFmt.fixed(st[1], 0)])
	if c.has("gold_mult"):
		var base: float
		if not done.is_empty():
			var gold_sum := 0
			for f in done:
				gold_sum += f["gold"]
			base = float(gold_sum) / done.size()
		else:
			var xp_sum := 0
			for m in world.monsters:
				xp_sum += m.xp_value
			base = xp_sum * GameConfig.GOLD_PER_XP * 0.6
		lines.append("Gold: you average about %s a floor, so expect %s gold." % [
				PyFmt.fixed(base, 0), PyFmt.signed_fixed(base * (c["gold_mult"] - 1), 0)])
	if c.has("viewer_mult"):
		var gain: float
		if not done.is_empty():
			var v_sum := 0
			for f in done:
				v_sum += f["viewers_end"] - f["viewers_start"]
			gain = float(v_sum) / done.size()
		else:
			gain = 300.0
		lines.append("Viewers: about %s on top of a typical floor." % PyFmt.signed_fixed(
				maxf(0.0, gain) * (c["viewer_mult"] - 1), 0))
	if c.has("monster_damage") or c.has("monster_hp_mult"):
		var p: Entity = world.player
		var mobs: Array = []
		for m in world.monsters:
			if not m.boss:
				mobs.append(m)
		if mobs.is_empty():
			mobs = world.monsters
		if mobs.is_empty():
			push_error("Contracts.preview: no monsters (Python raises ZeroDivisionError)")
			return lines
		var terms: Array = []
		for m in mobs:
			terms.append(Combat.expected_damage(m, p))
		var now := PyMath.fsum_py(terms) / mobs.size()
		if now == 0.0:
			push_error("Contracts.preview: monsters cannot hurt the player (Python raises ZeroDivisionError)")
			return lines
		var extra: int = c.get("monster_damage", 0)
		for m in mobs:
			m.dmg_bonus += extra
		terms = []
		for m in mobs:
			terms.append(Combat.expected_damage(m, p))
		var then := PyMath.fsum_py(terms) / mobs.size()
		for m in mobs:
			m.dmg_bonus -= extra
		lines.append("Danger: an average monster's hit on you goes from %s to %s expected damage (%s)." % [
				PyFmt.fixed(now, 1), PyFmt.fixed(then, 1), PyFmt.signed_percent(then / now - 1, 0)])
		if c.has("monster_hp_mult"):
			lines.append("Monsters take %s longer to kill." % PyFmt.percent(c["monster_hp_mult"] - 1, 0))
	if c.has("timer_mult"):
		lines.append("Time: %s becomes %s." % [world.timer_text(),
				world.timer_text(PyMath.round_half_even(world.timer * c["timer_mult"]))])
	if c.has("rest_mult"):
		lines.append("Resting to full takes half as long.")
	return lines
