class_name TracePolicies
extends RefCounted
## Scripted action policies for the parity traces (port plan 6.4). Written line for line like
## scripts/trace_policies.py, whose docstring is normative: no set or dictionary iteration, lists in
## World order, ties broken by first in list order, and every random choice drawn from the policy's
## own PyRandom stream in the documented order.
##
## A policy is an object with `step(w: World, do: Callable)`; `do(action: String, arg: Variant) -> bool`
## performs one action and writes its `act` record. If the main action of a step returns false the
## policy then calls do("wait", null), exactly like the bot does.
##
## Status: `walk` (slice S7) and `hunter` (slice S8) are complete and proven against Python at core
## scope (seeds 0-49, with and without pets and heroes); `bot` (slice T6) drives BotPolicy in bot.play's loop.

const POLICY_NAMES := ["walk", "hunter", "bot"]
## World methods each policy can call (trace.gd refuses a policy whose methods are missing).
const POLICY_METHODS := {"walk": ["move_player", "wait"],
		"hunter": ["move_player", "wait", "descend", "pickup", "use_item"],
		"bot": ["move_player", "wait", "descend", "rest", "pickup", "use_item", "use_skill", "revive_pet"]}
const POTIONS := ["tonic", "brew", "elixir"]


## Seed of the policy's own RNG stream (the bot's coin stream is seed ^ 0xB07).
static func policy_seed(policy_name: String, seed_value: int) -> int:
	return seed_value ^ (0xB07 if policy_name == "bot" else 0x7ACE)


## Chebyshev distance between two [x, y] pairs.
static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Run one named action on the World; returns its ok flag.
static func perform(w: World, action: String, arg: Variant) -> bool:
	match action:
		"move":
			return w.move_player(arg[0], arg[1])
		"wait":
			return w.wait()
		"choose_class":
			return w.choose_class(arg[0], arg[1])
		"accept":
			return w.accept_contract()
		"decline":
			return w.decline_contract()
		"descend", "rest", "pickup", "use", "skill", "revive":
			var method: String = {"descend": "descend", "rest": "rest", "pickup": "pickup", "use": "use_item",
					"skill": "use_skill", "revive": "revive_pet"}[action]
			return w.call(method, arg) if action == "use" else w.call(method)
	push_error("TracePolicies.perform: unknown action '%s'" % action)
	return false


## One step downhill on a distance map from the target, or null (else a [dx, dy] Array).
static func step_towards(w: World, tx: int, ty: int) -> Variant:
	var f := w.floor
	var p := w.player
	var dist := f.distance_map(tx, ty)
	var best: int = dist[p.y * f.width + p.x]
	var move: Variant = null
	for n in DungeonFloor.NEIGHBOURS_8:
		var nx := p.x + n.x
		var ny := p.y + n.y
		if f.walkable(nx, ny):
			var d: int = dist[ny * f.width + nx]
			if d != -1 and d < best:
				best = d
				move = [n.x, n.y]
	return move


## Draw i = rng.randrange(9). i < 8: move NEIGHBOURS_8[i]; i == 8: wait.
class WalkPolicy extends RefCounted:
	var policy_name := "walk"
	var rng: PyRandom

	func _init(_seed_value: int, rng_value: PyRandom) -> void:
		rng = rng_value

	func step(_w: World, do: Callable) -> void:
		var i := rng.randrange(9)
		var ok: bool
		if i < 8:
			ok = do.call("move", [DungeonFloor.NEIGHBOURS_8[i].x, DungeonFloor.NEIGHBOURS_8[i].y])
		else:
			ok = do.call("wait", null)
		if not ok:
			do.call("wait", null)


## First rule that yields an action wins (see the docstring of trace_policies.py).
class HunterPolicy extends RefCounted:
	var policy_name := "hunter"
	var rng: PyRandom

	func _init(_seed_value: int, rng_value: PyRandom) -> void:
		rng = rng_value             # unused (the hunter is fully deterministic), kept for symmetry

	## Returns [action, arg].
	func decide(w: World) -> Array:
		var p := w.player
		var f := w.floor
		var pos := Vector2i(p.x, p.y)
		if p.hp * 100 < p.max_hp * 45 and not w.in_safe_room:                # 1
			for i in range(w.inventory.size()):
				if w.inventory[i] in TracePolicies.POTIONS:
					return ["use", i]
		for m in w.monsters:                                                 # 2
			if TracePolicies.cheb(Vector2i(m.x, m.y), pos) == 1:
				return ["move", [m.x - p.x, m.y - p.y]]
		if w.floor_items.has(pos) and w.inventory.size() < 16:               # 3
			return ["pickup", null]
		var best_d := -1
		var best_m: Monster = null
		for m in w.monsters:                                                 # 4
			if w.visible.has(Vector2i(m.x, m.y)) and (not m.boss or w.exit_sealed):
				var d := TracePolicies.cheb(Vector2i(m.x, m.y), pos)
				if best_m == null or d < best_d:
					best_d = d
					best_m = m
		if best_m != null:
			var mv: Variant = TracePolicies.step_towards(w, best_m.x, best_m.y)
			if mv != null:
				return ["move", mv]
		best_d = -1
		var best_c: Variant = null
		for r in f.rooms:                                                    # 5
			var c := r.centre()
			if f.explored[c.y][c.x] == 0:
				var d := TracePolicies.cheb(c, pos)
				if best_c == null or d < best_d:
					best_d = d
					best_c = c
		if best_c != null:
			var mv: Variant = TracePolicies.step_towards(w, best_c.x, best_c.y)
			if mv != null:
				return ["move", mv]
		if w.on_stairs and not w.stairs_locked and not w.exit_sealed:        # 6
			return ["descend", null]
		if not w.on_stairs:                                                  # 7
			best_c = null
			for s in f.stairs:
				var d := TracePolicies.cheb(s, pos)
				if best_c == null or d < best_d:
					best_d = d
					best_c = s
			if best_c != null:
				var mv: Variant = TracePolicies.step_towards(w, best_c.x, best_c.y)
				if mv != null:
					return ["move", mv]
		return ["wait", null]                                                # 8

	func step(w: World, do: Callable) -> void:
		var decision := decide(w)
		if not do.call(decision[0], decision[1]):
			do.call("wait", null)


## `bot`: BotPolicy's choose, spend_points and manage_items inside bot.play's loop (class pick when
## pending, contract coin flip, free item management, one act, wait when refused). spend_points,
## manage_items and the remote shop_buy after a Supply Drop call the World directly and write no `act`
## records. The coin stream is `rng` (PyRandom(seed ^ 0xB07)); race, class, pet and hero come from
## BotPolicy.run_config(seed) (its 4 draws on the seed * 7919 + 13 stream are not traced).
class BotTracePolicy extends RefCounted:
	var policy_name := "bot"
	var cfg: Dictionary
	var rng: PyRandom
	var state := BotPolicy.BotState.new()

	func _init(seed_value: int, rng_value: PyRandom) -> void:
		cfg = BotPolicy.run_config(seed_value)
		rng = rng_value             # the coin stream

	func step(w: World, do: Callable) -> void:
		if w.pending_choice:
			do.call("choose_class", [cfg["race"], cfg["cls"]])
		if PyMath.truthy(w.pending_offer):
			do.call("accept" if rng.random() < 0.5 else "decline", null)
		BotPolicy.spend_points(w, cfg["cls"])
		BotPolicy.manage_items(w)
		var r := BotPolicy.choose(w, state)
		var act: String = r[0]
		var arg: Variant = r[1]
		var ok: bool
		if act == "move":
			ok = do.call("move", [arg.x, arg.y])
		elif act == "skill":
			ok = do.call("skill", null)
			if ok and w.remote_shop:
				BotPolicy.remote_shop_buy(w)
		elif act in ["descend", "rest", "pickup", "use", "revive", "wait"]:
			ok = do.call(act, arg)
		else:
			ok = do.call("wait", null)
		if not ok:
			do.call("wait", null)


## [pet species ("" for none), hero Dictionary or null] a policy uses unless the command line overrides
## it (Python default_setup).
static func default_setup(policy_name: String, seed_value: int) -> Array:
	if policy_name == "bot":
		var cfg := BotPolicy.run_config(seed_value)
		var pet: String = cfg["pet"]
		return [pet if pet != "none" else "", {"name": "Bot", "gender": cfg["gender"], "backstory": cfg["backstory"]}]
	return ["", null]


## A policy object for `policy_name` driven by `rng`, or null (with push_error) when it is not
## available yet.
static func make_policy(policy_name: String, seed_value: int, rng_value: PyRandom) -> Object:
	if policy_name == "walk":
		return WalkPolicy.new(seed_value, rng_value)
	if policy_name == "hunter":
		return HunterPolicy.new(seed_value, rng_value)
	if policy_name == "bot":
		return BotTracePolicy.new(seed_value, rng_value)
	push_error("TracePolicies.make_policy: policy '%s' is not ported yet" % policy_name)
	return null
