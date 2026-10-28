class_name Ai
extends RefCounted
## Monster and pet behaviour (crawler/ai.py).
##
## A monster becomes alerted when it is in the player's field of view and gives up after
## MONSTER_LOSE_TRACK turns out of sight. Alerted monsters step down a shared distance map towards
## the player; idle ones occasionally wander. Ranged monsters shoot when they have the player in
## sight at range. Monsters never enter safe-room tiles and never attack into them.
##
## Outside combat every monster acts once per turn. In combat (World.combat) the monsters and the
## pet in the fight act in initiative order instead, each able to step and then attack
## (take_combat_turn, take_pet_turn(combat = true)); a step out of a hostile's reach first gives it
## an attack of opportunity (World.opportunity_attacks). A pounce is a leap, not a step, and
## doesn't provoke.
##
## `occupied` sets are Dictionaries of Vector2i to true (membership only, as in Python). A step is
## null or a Vector2i (Python None or a tuple). The chase cache lives on the world as
## `_chase_cache` = [floor, x, y, dist].

static var CHASE_RADIUS: int = Content.config("ai")["CHASE_RADIUS"]
## A following pet stays this close and defends you within it.
static var PET_LEASH: int = Content.config("ai")["PET_LEASH"]
static var POUNCE_RANGE: int = Content.config("ai")["POUNCE_RANGE"]
static var SQUAWK_RANGE: int = Content.config("ai")["SQUAWK_RANGE"]
## The mouse runs back to you below this much HP.
static var MOUSE_FLEE_FRAC: float = Content.config("ai")["MOUSE_FLEE_FRAC"]


## Chebyshev distance between two entities.
static func cheb(a: Entity, b: Entity) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func _free(world: World, x: int, y: int, occupied: Dictionary, allow_safe: bool = false) -> bool:
	var fl := world.floor
	return (fl.walkable(x, y) and (allow_safe or not fl.is_safe(x, y))
			and not occupied.has(Vector2i(x, y)) and not (x == world.player.x and y == world.player.y))


## The free neighbouring tile with the lowest distance, or null.
static func _step_down(world: World, ent: Entity, dist: PackedInt32Array, occupied: Dictionary,
		allow_safe: bool = false) -> Variant:
	var w := world.floor.width
	var best: int = dist[ent.y * w + ent.x]
	var step: Variant = null
	if best == -1:
		return null
	for n in DungeonFloor.NEIGHBOURS_8:
		var nx := ent.x + n.x
		var ny := ent.y + n.y
		if not _free(world, nx, ny, occupied, allow_safe):
			continue
		var d: int = dist[ny * w + nx]
		if d != -1 and d < best:
			best = d
			step = Vector2i(nx, ny)
	return step


## Distance map towards the player, cached until the player moves or the floor changes.
static func chase_map(world: World) -> PackedInt32Array:
	var player := world.player
	var cache: Array = world._chase_cache
	if cache.is_empty() or not is_same(cache[0], world.floor) or cache[1] != player.x or cache[2] != player.y:
		cache = [world.floor, player.x, player.y,
				world.floor.distance_map(player.x, player.y, CHASE_RADIUS, true)]
		world._chase_cache = cache
	return cache[3]


## Update a monster's alert from what it can see; returns true if it sees you.
static func _notice(world: World, m: Monster) -> bool:
	var seen: bool = world.visible.has(Vector2i(m.x, m.y)) and cheb(m, world.player) <= world.notice_range()
	if seen:
		m.alerted = true
		m.unseen_turns = 0
	elif m.alerted:
		m.unseen_turns += 1
		if m.unseen_turns > GameConfig.MONSTER_LOSE_TRACK:
			m.alerted = false
	return seen


## Attack the player, else the pet, if adjacent and outside the safe room.
static func _melee(world: World, m: Monster) -> bool:
	var fl := world.floor
	var player := world.player
	if cheb(m, player) == 1 and not fl.is_safe(player.x, player.y):
		world.monster_attack(m)
		return true
	var pet := world.active_pet
	if pet != null and cheb(m, pet) == 1 and not fl.is_safe(pet.x, pet.y):
		world.monster_attack_pet(m)
		return true
	return false


static func _shoot(world: World, m: Monster, seen: bool) -> bool:
	var player := world.player
	# Short-circuit: the draw happens only when every earlier condition holds.
	if (m.ranged != 0 and seen and 2 <= cheb(m, player) and cheb(m, player) <= m.ranged
			and not world.floor.is_safe(player.x, player.y)
			and world.rng.random() < GameConfig.RANGED_ATTACK_CHANCE):
		world.monster_attack(m, true)
		return true
	return false


static func _occupied(world: World) -> Dictionary:
	var occupied := {}
	for m in world.monsters:
		occupied[Vector2i(m.x, m.y)] = true
	var pet := world.active_pet
	if pet != null:
		occupied[Vector2i(pet.x, pet.y)] = true
	return occupied


## Every monster outside combat acts once. A monster that becomes alerted joins (or starts) combat
## instead, and from then on acts in initiative order.
static func take_monster_turns(world: World) -> void:
	var rng := world.rng
	var dist := chase_map(world)
	var occupied := _occupied(world)

	for m: Monster in world.monsters.duplicate():          # bosses can summon help mid-loop
		if world.state != "playing":
			return
		if (world.combat != null and world.combat.has_entity(m)) or world._acted.has(m):
			continue                        # combatants act in initiative order, once a round
		if not world.monsters.has(m):
			continue                        # killed by a riposte earlier in the loop
		if m.stunned != 0:
			m.stunned -= 1
			continue
		var seen := _notice(world, m)
		if m.alerted and world.join_combat(m):
			continue                        # rolling initiative takes its turn

		var step: Variant = null
		if m.alerted:
			if _melee(world, m) or _shoot(world, m, seen):
				continue
			step = _step_down(world, m, dist, occupied)
		elif not m.boss and rng.random() < GameConfig.MONSTER_WANDER_CHANCE:
			var n: Vector2i = rng.choice(DungeonFloor.NEIGHBOURS_8)
			if _free(world, m.x + n.x, m.y + n.y, occupied):
				step = Vector2i(m.x + n.x, m.y + n.y)

		if step != null:
			occupied.erase(Vector2i(m.x, m.y))
			m.x = step.x
			m.y = step.y
			occupied[step] = true


## A monster's turn in combat: attack if adjacent, else shoot or step towards you and then attack
## if the step ends adjacent (a move plus an action).
static func take_combat_turn(world: World, m: Monster) -> void:
	if m.stunned != 0:
		m.stunned -= 1
		return
	var seen := _notice(world, m)
	if not m.alerted:
		world.leave_combat(m)               # lost track of you
		return
	if _melee(world, m) or _shoot(world, m, seen):
		return
	var step: Variant = _step_down(world, m, chase_map(world), _occupied(world))
	if step != null and world.opportunity_attacks(m, step.x, step.y):        # leaving reach provokes
		m.x = step.x
		m.y = step.y
		_melee(world, m)


## The companion's turn: ability if ready, then fight, then move by mode. In combat a plain step may
## be followed by an attack if it ends next to a monster.
static func take_pet_turn(world: World, combat: bool = false) -> void:
	var pet := world.active_pet
	if pet == null or world.state != "playing":
		return
	var fl := world.floor
	var player := world.player
	var spec: Dictionary = Entities.pets()[pet.species]
	if pet.cooldown != 0:
		pet.cooldown -= 1
	var pet_safe := fl.is_safe(pet.x, pet.y)
	var occupied := {}
	for m in world.monsters:
		occupied[Vector2i(m.x, m.y)] = true

	if spec["ability"] == "dirty_trick" and pet.hp < pet.max_hp * MOUSE_FLEE_FRAC:
		# Cowardice: run back to the player and don't pick fights.
		if cheb(pet, player) > 1:
			var dist := fl.distance_map(player.x, player.y, 40)
			var step: Variant = _step_down(world, pet, dist, occupied, true)
			if step != null and (not combat or world.opportunity_attacks(pet, step.x, step.y)):
				pet.x = step.x
				pet.y = step.y
				world.pet_flees()
		return

	if pet.cooldown == 0:
		if spec["ability"] == "squawk" and not pet_safe:
			var near: Array = []
			for m: Monster in world.monsters:
				if world.visible.has(Vector2i(m.x, m.y)) and cheb(m, player) <= SQUAWK_RANGE and m.stunned == 0:
					near.append(m)
			var adjacent_near := false
			for m: Monster in near:
				if cheb(m, player) == 1:
					adjacent_near = true
					break
			if near.size() >= 2 or adjacent_near:
				world.pet_squawk(near)
				return
		if spec["ability"] == "dirty_trick" and not pet_safe:
			var wounded: Array = []
			for m: Monster in world.monsters:
				if cheb(pet, m) == 1 and m.hp <= m.max_hp * 0.6:
					wounded.append(m)
			if not wounded.is_empty():
				world.pet_dirty_trick(PyMath.min_by(wounded, func(m: Monster) -> int: return m.hp))
				return
		if (spec["ability"] == "lick" and player.hp < player.max_hp * 0.5
				and cheb(pet, player) <= 1):
			world.pet_lick()
			return
		if spec["ability"] == "pounce" and pet.mode != "stay" and not pet_safe:
			var targets: Array = []
			for m: Monster in world.monsters:
				if world.visible.has(Vector2i(m.x, m.y)) and 2 <= cheb(pet, m) and cheb(pet, m) <= POUNCE_RANGE:
					targets.append(m)
			for t: Monster in PyMath.stable_sort_by(targets, func(m: Monster) -> int: return m.hp):
				var spots: Array = []
				for n in DungeonFloor.NEIGHBOURS_8:
					if _free(world, t.x + n.x, t.y + n.y, occupied):
						spots.append(Vector2i(t.x + n.x, t.y + n.y))
				if not spots.is_empty():
					var best: Vector2i = PyMath.min_by(spots, func(s: Vector2i) -> int:
							return maxi(absi(s.x - pet.x), absi(s.y - pet.y)))
					pet.x = best.x
					pet.y = best.y
					world.pet_pounce(t)
					return

	if not pet_safe:
		var adjacent: Array = []
		for m: Monster in world.monsters:
			if cheb(pet, m) == 1:
				adjacent.append(m)
		if not adjacent.is_empty():
			world.pet_attack(PyMath.min_by(adjacent, func(m: Monster) -> int: return m.hp))
			return

	var target: Entity = null
	if pet.mode == "attack":
		var seen_mons: Array = []
		for m: Monster in world.monsters:
			if world.visible.has(Vector2i(m.x, m.y)):
				seen_mons.append(m)
		if not seen_mons.is_empty():
			target = PyMath.min_by(seen_mons, func(m: Monster) -> int: return cheb(pet, m))
	elif pet.mode == "follow":
		# Help with whatever is fighting the player.
		var threats: Array = []
		for m: Monster in world.monsters:
			if (world.visible.has(Vector2i(m.x, m.y)) and cheb(m, player) <= PET_LEASH
					and not fl.is_safe(m.x, m.y)):
				threats.append(m)
		if not threats.is_empty():
			target = PyMath.min_by(threats, func(m: Monster) -> int: return cheb(pet, m))
	if target == null and pet.mode != "stay" and cheb(pet, player) > PET_LEASH:
		target = player
	if target == null:
		return
	var dist2 := fl.distance_map(target.x, target.y, 40)
	var step2: Variant = _step_down(world, pet, dist2, occupied, true)
	if step2 != null and (not combat or world.opportunity_attacks(pet, step2.x, step2.y)):
		pet.x = step2.x
		pet.y = step2.y
		if combat and not fl.is_safe(pet.x, pet.y):
			var adjacent2: Array = []
			for m: Monster in world.monsters:
				if cheb(pet, m) == 1:
					adjacent2.append(m)
			if not adjacent2.is_empty():
				world.pet_attack(PyMath.min_by(adjacent2, func(m: Monster) -> int: return m.hp))
