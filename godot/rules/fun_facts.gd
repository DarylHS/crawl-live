class_name FunFacts
extends RefCounted
## The System AI's stats one-liners, triggered by things that just happened (crawler/funfacts.py).
##
## Facts are rate-limited (one per MIN_GAP turns) so they stay a garnish. Each uses the game's real
## numbers, not generic trivia. FunFacts draws no random numbers.
##
## The owning world is held through a WeakRef (port plan section 3, "Back-references to World"):
## World -> FunFacts -> World would otherwise be a strong reference cycle. The world must own its
## FunFacts for its whole life; a FunFacts kept without its world gets null from `world`.
## Duck-typed world: it needs events, messages, turn and player.

static var MIN_GAP: int = Content.config("funfacts")["MIN_GAP"]
## Misses in a row before the gambler's fallacy fact.
static var MISS_STREAK: int = Content.config("funfacts")["MISS_STREAK"]
## Boxes of a tier opened without its rarest item.
static var BOX_DROUGHT: int = Content.config("funfacts")["BOX_DROUGHT"]

## The owning world, held through a WeakRef.
var world: Object:
	get:
		return _world_ref.get_ref()

var _world_ref: WeakRef
var last_turn: int
## Facts that only appear once per run (a set: key -> true).
var said: Dictionary = {}
var miss_streak: int = 0
var streak_chance: float = 1.0
## tier -> boxes opened without the rarest item.
var drought: Dictionary = {}


func _init(world_value: Object) -> void:
	_world_ref = weakref(world_value)
	last_turn = -MIN_GAP
	var ev: EventBus = world_value.events
	ev.subscribe("player_attack", _attack)
	ev.subscribe("box_opened", _box)
	ev.subscribe("box_trade", _trade)
	ev.subscribe("contract_accepted", _contract)
	ev.subscribe("shop_sold_out", _sold_out)
	ev.subscribe("damage_taken", _close_call)


## Says `text` unless rate-limited. `once` ("" for none, Python None) makes the fact appear once per
## run; `force` ignores the rate limit. Returns whether it was said.
func _say(text: String, once: String = "", force: bool = false) -> bool:
	var w: Object = world
	if (once != "" and said.has(once)) or (not force and w.turn - last_turn < MIN_GAP):
		return false
	if once != "":
		said[once] = true
	last_turn = w.turn
	w.messages.add("FUN FACT: %s" % text, GameConfig.INFO)
	w.events.emit("fun_fact", {"text": text})
	return true


func _attack(_name: String, d: Dictionary) -> void:
	if d["hit"]:
		miss_streak = 0
		if d["crit"]:
			var r: int = world.player.crit_range
			var faces := "a natural 20" if r == 1 else "%d-20 on the d20" % (21 - r)
			_say("You crit on %s: %s of swings, about one in %s. They still cluster and gap at random."
					% [faces, PyFmt.percent(float(r) / 20, 0), PyFmt.fixed(20.0 / r, 0)], "crit")
		return
	var chance: float = d["chance"]
	miss_streak += 1
	streak_chance *= (1 - chance) if miss_streak > 1 else 1.0
	if miss_streak == 1:
		streak_chance = 1 - chance
	if miss_streak >= MISS_STREAK and chance >= 0.6:
		if _say("%d misses in a row at %s each: odds of that were %s. Your next swing is still %s. Dice have no memory."
				% [miss_streak, PyFmt.percent(chance, 0), PyFmt.percent(streak_chance, 2), PyFmt.percent(chance, 0)]):
			miss_streak = 0


func _box(_name: String, d: Dictionary) -> void:
	var tier: String = d["tier"]
	var low: Array = PyMath.min_by(Loot.odds(tier), func(r: Array) -> float: return r[1])
	var rarest: String = low[0]
	var p: float = low[1]
	if d["item"] == rarest:
		drought[tier] = 0
		return
	var n: int = drought.get(tier, 0) + 1
	drought[tier] = n
	if n >= BOX_DROUGHT:
		_say("%d %s boxes without a %s (%s each). Chance of that: %s. It isn't 'due': every box is a fresh roll."
				% [n, Content.box(tier)["name"], Items.items()[rarest]["name"], PyFmt.percent(p, 0),
				PyFmt.percent(pow(1 - p, n), 0)], "", true)


func _trade(_name: String, d: Dictionary) -> void:
	var ev_in: float = Loot.box_stats(d["tier"])[0]
	var out: Array = Loot.box_stats(d["to"])
	var ev_out: float = out[0]
	var sd_out: float = out[1]
	var edge: float = Loot.TRADE_UP_COST * ev_in - ev_out
	var verdict: String
	if edge > 0:
		verdict = "loses about %s gold on average. That's the house edge: it only pays if you want something only the bigger box has" % PyFmt.fixed(edge, 0)
	else:
		verdict = "gains about %s gold on average" % PyFmt.fixed(-edge, 0)
	_say("That trade %s. You swapped %d boxes worth %s in total for one worth %s, give or take %s."
			% [verdict, Loot.TRADE_UP_COST, PyFmt.fixed(Loot.TRADE_UP_COST * ev_in, 0),
			PyFmt.fixed(ev_out, 0), PyFmt.fixed(sd_out, 0)], "", true)


func _contract(_name: String, _d: Dictionary) -> void:
	_say("A deal can have positive expected value and still end your run. Averages describe many runs; you only get this one.", "contract")


func _sold_out(_name: String, d: Dictionary) -> void:
	_say("Sold out of %s. The shop carries safety stock for about one standard deviation of demand, so it runs dry roughly one floor in six. This was one of them."
			% Items.items()[d["item"]]["name"], "sold_out_%s" % d["item"], true)


func _close_call(_name: String, d: Dictionary) -> void:
	var p: Object = world.player
	if 0 < d["hp"] and d["hp"] <= p.max_hp * 0.1:
		_say("Still standing on almost nothing. Close calls feel common because you only remember the ones you survived (survivorship bias).", "close_call")
