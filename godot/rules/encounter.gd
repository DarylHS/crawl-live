class_name Encounter
extends RefCounted
## Combat mode: who is fighting, in what order, and what the player has left this turn
## (crawler/encounter.py). An Encounter exists only while a fight is on (World.combat is null
## otherwise). It is plain data; the World rolls initiative, spends the budget and runs the other
## combatants' turns.

## The player's turn budget parts and their display names (config "encounter").
static var PARTS: Array = Content.config("encounter")["PARTS"]
static var PART_NAMES: Dictionary = Content.config("encounter")["PART_NAMES"]

var player: Entity
## [[sort key, entity, roll, modifier], ...], best first. The key is an Array
## [-(roll + modifier), -modifier, entity is not player, seq].
var order: Array = []
## 0 until the first round begins.
var round: int = 0
## Part name to bool: one move, one action and one bonus action per round.
var budget: Dictionary = _fresh_budget()
## Set of entities that have used their reaction since their last turn (Dictionary, values true).
var reacted: Dictionary = {}
var _seq: int = 0


func _init(p_player: Entity) -> void:
	player = p_player


static func _fresh_budget() -> Dictionary:
	var b := {}
	for part in PARTS:
		b[part] = true
	return b


## Python `entity in encounter` (__contains__).
func has_entity(entity: Entity) -> bool:
	for row in order:
		if is_same(row[1], entity):
			return true
	return false


## Place a combatant by initiative: higher total first, then the higher modifier, then the player;
## later joiners go after earlier ones with the same numbers.
func add(entity: Entity, roll: int, modifier: int) -> void:
	if has_entity(entity):
		return
	_seq += 1
	var key: Array = [-(roll + modifier), -modifier, not is_same(entity, player), _seq]
	order.append([key, entity, roll, modifier])
	PyMath.stable_sort_in_place(order, func(row: Array) -> Array: return row[0])


# --- Reactions (attacks of opportunity) ---------------------------------

func can_react(entity: Entity) -> bool:
	return has_entity(entity) and not reacted.has(entity)


func react(entity: Entity) -> void:
	reacted[entity] = true


## A creature's reaction comes back at the start of its turn.
func ready(entity: Entity) -> void:
	reacted.erase(entity)


func remove(entity: Entity) -> void:
	var kept: Array = []
	for row in order:
		if not is_same(row[1], entity):
			kept.append(row)
	order = kept


## Combatants in initiative order.
var entities: Array:
	get:
		var out: Array = []
		for row in order:
			out.append(row[1])
		return out


## Combatants other than the player and the pet (anything with an 'alerted' flag).
var monsters: Array:
	get:
		var out: Array = []
		for e in entities:
			if e is Monster:
				out.append(e)
		return out


## The entity's initiative total (roll + modifier). Python raises StopIteration when it is not in
## the fight; here that is a push_error and 0.
func total(entity: Entity) -> int:
	for row in order:
		if is_same(row[1], entity):
			return row[2] + row[3]
	push_error("Encounter.total: entity is not in the fight")
	return 0


## Combatants that act before entity in a round. (Python raises when absent; here push_error and [].)
func before(entity: Entity) -> Array:
	var es := entities
	var i := _index_of(es, entity)
	if i < 0:
		push_error("Encounter.before: entity is not in the fight")
		return []
	return es.slice(0, i)


## Combatants that act after entity in a round. (Python raises when absent; here push_error and [].)
func after(entity: Entity) -> Array:
	var es := entities
	var i := _index_of(es, entity)
	if i < 0:
		push_error("Encounter.after: entity is not in the fight")
		return []
	return es.slice(i + 1)


static func _index_of(es: Array, entity: Entity) -> int:
	for i in es.size():
		if is_same(es[i], entity):
			return i
	return -1


# --- The player's turn budget ----------------------------------------

func has(part: String) -> bool:
	return budget[part]


func spend(part: String) -> void:
	budget[part] = false


func reset_budget() -> void:
	budget = _fresh_budget()


## Your turn ends by itself once both the move and the action are spent.
var turn_over: bool:
	get:
		return not budget["move"] and not budget["action"]
