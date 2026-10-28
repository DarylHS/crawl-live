class_name Telemetry
extends RefCounted
## Run telemetry: turns one game into tidy tables for analysis (crawler/telemetry.py).
##
## Attach a Telemetry to a World as soon as it is created. At the end of the run, tables() returns
## Dictionaries of Arrays of row Dictionaries:
##
##   runs    one row per run: who played, how it ended, totals
##   floors  one row per floor reached: the player's state on arrival, what happened there and how the
##           floor ended (the unit for death models)
##   boxes   one row per loot box opened
##   shop    one row per shop item per floor turnover
##   practice one row per practice skill
##   events  one row per game event (run_id, turn, floor, event, value, detail), the long format for
##           anything the other tables don't cover
##
## PyCsv.write_tables(tables, dir, prefix) appends them to CSVs in a folder (the game passes a
## directory under user://; the bot passes its own). Row keys are inserted in exactly Python's order,
## because that order is the CSV column order (port plan 8.5).
##
## Ownership: the Telemetry reaches the World through a WeakRef, like the other subsystems (port plan
## section 3). The World does not own the Telemetry (the caller does, as in Python), so the caller must
## keep it for as long as the World emits events: a Telemetry freed while its World lives leaves a dead
## callable on the event bus. Subscription order is Python's: "*" first, then "floor_start".
## Rows hold the run's own run_id; with no run_id a 12 hex character one is drawn from the OS (player
## runs only; the bot always passes its ids, so nothing here is seeded or parity-relevant).

## Events that are not logged (every tick; the viewer samples cover it).
static var SKIP: Array = Content.config("telemetry")["SKIP"]
## Payload keys tried in order for the events table's `value` column.
static var VALUE_KEYS: Array = Content.config("telemetry")["VALUE_KEYS"]
## Payload keys tried in order for the events table's `detail` column.
static var DETAIL_KEYS: Array = Content.config("telemetry")["DETAIL_KEYS"]

var source: String
var run_id: Variant
var meta: Dictionary
var events: Array = []
var arrivals: Array = []
var world: World:
	get:
		return _world_ref.get_ref()

var _world_ref: WeakRef


## `run_id` may be any value (Python tests pass an int); a falsy one draws a fresh id. `meta` keys are
## appended to every runs row (the bot adds `deals`).
func _init(world_value: World, source_value: String = "player", run_id_value: Variant = "",
		meta_value: Dictionary = {}) -> void:
	_world_ref = weakref(world_value)
	source = source_value
	run_id = run_id_value if PyMath.truthy(run_id_value) else _new_id()
	meta = meta_value
	world_value.events.subscribe("*", _on_event)
	world_value.events.subscribe("floor_start", _on_floor_start)
	_arrive()   # floor 1 started before we subscribed


## uuid4().hex[:12]: 12 hex characters.
static func _new_id() -> String:
	return Crypto.new().generate_random_bytes(6).hex_encode()


func _on_floor_start(_name: String, _d: Dictionary) -> void:
	_arrive()


func _arrive() -> void:
	var w: World = world
	var p: Player = w.player
	var kinds: Array = []
	for k in w.inventory:
		kinds.append(Content.item(k)["kind"])
	var pet: Pet = w.pet
	var row := {}
	row["depth"] = w.depth
	row["turn"] = w.turn
	row["hp"] = p.hp
	row["max_hp"] = p.max_hp
	row["hp_frac"] = PyMath.round_n(float(p.hp) / p.max_hp, 3)
	row["level"] = p.level
	for a in Content.table("attributes"):
		row[a] = w.score(a)
	row["attack"] = p.attack
	row["ac"] = p.ac
	row["dmg_avg"] = Dice.average(p.dmg_n, p.dmg_die, p.dmg_bonus)
	row["potions"] = kinds.count("potion")
	row["bombs"] = kinds.count("bomb")
	row["gold"] = w.gold
	row["boxes"] = w.boxes.size()
	row["cls"] = w.cls if PyMath.truthy(w.cls) else "none"
	row["race"] = w.race if PyMath.truthy(w.race) else "none"
	row["backstory"] = w.backstory if PyMath.truthy(w.backstory) else "none"
	row["pet"] = pet.species if pet != null else "none"
	row["pet_level"] = pet.level if pet != null else 0
	row["pet_down"] = pet != null and pet.downed
	row["timer_max"] = w.timer_max
	row["viewers"] = w.viewers
	arrivals.append(row)


func _on_event(event_name: String, d: Dictionary) -> void:
	if SKIP.has(event_name):
		return
	var w: World = world
	var value: Variant = ""
	for k in VALUE_KEYS:
		var v: Variant = d.get(k)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:   # bool is its own type here, as excluded
			value = v
			break
	var detail := ""
	for k in DETAIL_KEYS:
		var v: Variant = d.get(k)
		if v == null or (typeof(v) == TYPE_STRING and v == ""):
			continue
		detail = PyFmt.str(v)
		break
	events.append({"run_id": run_id, "turn": w.turn, "floor": w.depth, "event": event_name,
			"value": value, "detail": detail})


## The run's tables, ready for PyCsv.write_tables. Call at the end of the run (it reads the final
## world state; floors and events are the ones collected so far).
func tables() -> Dictionary:
	var w: World = world
	var p: Player = w.player
	var ended := w.state != "playing"
	var cause: String = w.death_cause if PyMath.truthy(w.death_cause) else ""
	var outcome := "victory" if w.state == "victory" else (
			"collapse" if "collapsed" in cause else ("killed" if w.state == "dead" else "unfinished"))
	var gold_total := 0
	for f in w.floor_stats:
		gold_total += f["gold"]
	var levels_total := 0
	for k in w.training.levels:
		levels_total += w.training.levels[k]
	var run := {}
	run["run_id"] = run_id
	run["source"] = source
	run["seed"] = w.seed
	run["pet"] = w.pet.species if w.pet != null else "none"
	run["race"] = w.race if PyMath.truthy(w.race) else "none"
	run["backstory"] = w.backstory if PyMath.truthy(w.backstory) else "none"
	run["gender"] = w.gender if PyMath.truthy(w.gender) else "none"
	run["cls"] = w.cls if PyMath.truthy(w.cls) else "none"
	run["outcome"] = outcome
	run["depth"] = w.depth
	run["turns"] = w.turn
	run["kills"] = p.kills
	run["level"] = p.level
	run["gold"] = gold_total
	run["viewers"] = w.viewers
	run["peak_viewers"] = w.showrunner.peak
	run["boxes"] = w.box_log.size()
	run["achievements"] = w.achievements.unlocked.size()
	run["practice_levels"] = levels_total
	run["death_cause"] = cause
	for k in meta:
		if run.has(k):
			push_error("Telemetry: meta key '%s' collides with a runs column (Python raises TypeError)" % k)
		run[k] = meta[k]
	var floors: Array = []
	var by_depth := {}
	for f in w.floor_stats:
		by_depth[f["depth"]] = f
	for i in range(arrivals.size()):
		var a: Dictionary = arrivals[i]
		var f: Dictionary = by_depth.get(a["depth"], {})
		var last: bool = a["depth"] == w.depth and i == arrivals.size() - 1
		var result := outcome if (last and ended) else ("unfinished" if last else "cleared")
		var row := {"run_id": run_id, "source": source}
		row.merge(a)
		row["contract"] = f.get("contract") if PyMath.truthy(f.get("contract")) else "none"
		row["damage_taken"] = f.get("damage_taken", 0)
		row["gold_earned"] = f.get("gold", 0)
		row["kills_here"] = f.get("kills", 0)
		row["viewers_gained"] = f.get("viewers_end", 0) - f.get("viewers_start", 0)
		row["result"] = result
		row["died_here"] = int(result == "killed" or result == "collapse")
		floors.append(row)
	var boxes: Array = []
	for b in w.box_log:
		var row := {"run_id": run_id, "source": source}
		row.merge(b)
		boxes.append(row)
	var shop: Array = []
	for r in w.shop.log:
		var row := {"run_id": run_id, "source": source}
		row.merge(r)
		shop.append(row)
	var practice: Array = []
	for k in w.training.levels:
		practice.append({"run_id": run_id, "source": source, "skill": k, "level": w.training.levels[k],
				"used": int(w.training.used.has(k))})
	return {"runs": [run], "floors": floors, "boxes": boxes, "shop": shop, "practice": practice,
			"events": events}
