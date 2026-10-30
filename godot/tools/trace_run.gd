class_name TraceRun
extends RefCounted
## Run-mode parity trace (port plan 6.1/6.2; normative: scripts/py_trace.py docstring, Tracer and
## run_trace). Builds a World with the tap seams attached before floor 1, drives it with a
## TracePolicies policy and records header / ev / turn / floor / act / msg / end as Dictionaries
## (key order as Python). Shared by tools/trace.gd and tests/test_s7_parity.gd.
##
## Every number that goes into a hash input is a decimal int; colours are ints; bools stay bools;
## floats are written by PyJson (PyFmt.repr_float).


## Receives the world's events and messages through the tap seams. Holds the world weakly (the
## world's event bus holds this object's tap).
class Tracer extends RefCounted:
	var records: Array = []
	var msgs: bool = true
	var i: int = 0
	var _world_ref: WeakRef

	func _init(with_msgs: bool = true) -> void:
		msgs = with_msgs

	func attach_world(w: Object) -> void:
		_world_ref = weakref(w)

	func on_event(event_name: String, data: Dictionary) -> void:
		var w: World = null
		if _world_ref != null:
			w = _world_ref.get_ref()
		i += 1
		records.append({"k": "ev", "i": i, "t": w.turn if w != null else 0, "d": w.depth if w != null else 0,
				"e": event_name, "p": data.duplicate(), "r": TraceFloors.stream_words(w) if w != null else [0, 0, 0, 0, 0]})
		if w == null:
			return
		if event_name == "turn":
			var p := w.player
			var pt := w.pet
			var pet_rec: Variant = null
			if pt != null:
				pet_rec = [pt.x, pt.y, pt.hp, pt.downed]
			records.append({"k": "turn", "t": w.turn, "pos": [p.x, p.y], "hp": p.hp, "max_hp": p.max_hp,
					"timer": w.timer, "state": w.state, "gold": w.gold, "viewers": w.viewers,
					"combat": w.combat.round if w.combat != null else null,
					"pet": pet_rec,
					"mon": TraceFloors.h16(TraceFloors.mon_string(w.monsters)),
					"inv": w.inventory.duplicate()})
		elif event_name == "floor_start":
			records.append({"k": "floor", "depth": w.depth,
					"fp": TraceFloors.floor_fp(w.floor, w.floor_items, w.monsters),
					"rs": TraceFloors.stream_digests(w)})

	func on_message(text: String, colour: Array) -> void:
		if msgs:
			records.append({"k": "msg", "text": text, "c": colour.duplicate()})


static func header(seed_value: int, policy_name: String, steps: int, pet: Variant, hero: Variant) -> Dictionary:
	return {"k": "header", "impl": "godot", "trace_version": TraceFloors.TRACE_VERSION, "seed": seed_value,
			"policy": policy_name, "steps": steps, "pet": pet, "hero": hero,
			"content_sha": TraceFloors.content_sha(), "mode": "run"}


## Play `steps` policy steps (fewer if the run ends) and return the trace records. `pet` is a species
## key, "" or "none" for no pet; `hero` is a Dictionary or null. Returns [] (with push_error) when
## the policy is not available.
static func run_trace(seed_value: int, policy_name: String, steps: int, pet: String = "",
		hero: Variant = null, with_msgs: bool = true) -> Array:
	if pet == "none":
		pet = ""
	var tracer := Tracer.new(with_msgs)
	var pet_arg: Variant = [pet, ""] if pet != "" else null
	var prng := PyRandom.new(TracePolicies.policy_seed(policy_name, seed_value))
	var pol: Object = TracePolicies.make_policy(policy_name, seed_value, prng)
	if pol == null:
		return []
	var w := World.new(seed_value, pet_arg, hero, Callable(tracer, "on_event"), Callable(tracer, "on_message"),
			tracer)
	var fx: FxDirector = null
	if OS.get_environment("CRAWL_FX") == "1":
		fx = FxDirector.attach_headless(w)       # P8 parity proof: the effects listen to every event and change nothing
	var out: Array = [header(seed_value, policy_name, steps, pet if pet != "" else null, hero)]
	out.append_array(tracer.records)
	tracer.records = []
	var n: Array = [0]          # boxed: lambdas capture locals by value
	var do := func(action: String, arg: Variant) -> bool:
		var ok := TracePolicies.perform(w, action, arg)
		tracer.records.append({"k": "act", "n": n[0], "a": action, "arg": arg, "ok": ok, "pr": prng.words_used})
		return ok
	for step_n in range(steps):
		n[0] = step_n
		if w.state != "playing":
			break
		pol.step(w, do)
		out.append_array(tracer.records)
		tracer.records = []
	out.append({"k": "end", "state": w.state, "turn": w.turn, "depth": w.depth, "cause": w.death_cause,
			"rs": TraceFloors.stream_digests(w)})
	w.events.tap = Callable()      # the taps hold the tracer; drop them so nothing outlives the call
	w.messages.tap = Callable()
	if fx != null:
		fx.free()
	return out
