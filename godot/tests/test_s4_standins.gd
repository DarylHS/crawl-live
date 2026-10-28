extends TestCase
## Ownership of the subsystems that hold their World weakly (the Achievements and FunFacts stand-ins, the real Showrunner): a world that owns one must be
## freed with it (they hold the world through a WeakRef), as Practice does. Also the Loot error path.
## (The preview guard for zero expected damage cannot be reached with real entities: damage is at
## least 1 and a natural 20 always hits.)


class Owner extends RefCounted:
	var seed: int = 7
	var events := EventBus.new()
	var sub: Object


func _build(kind: String) -> Array:
	var w := Owner.new()
	match kind:
		"achievements":
			w.sub = Achievements.new(w)
		"showrunner":
			w.sub = Showrunner.new(w)
		_:
			w.sub = FunFacts.new(w)
	assert_true(w.sub.world == w)
	return [weakref(w), weakref(w.sub)]   # both dropped when this function returns


func test_stand_ins_are_freed_with_their_world(kind = use_parameters(["achievements", "showrunner", "fun_facts"])) -> void:
	var refs := _build(kind)
	assert_null(refs[0].get_ref(), kind)
	assert_null(refs[1].get_ref(), kind)


func test_showrunner_defaults_before_any_event() -> void:
	var w := Owner.new()
	var s := Showrunner.new(w)
	assert_eq([s.viewers, s.peak, s.samples], [50, 50, [[0, 50]]])
	assert_eq(s.rng.words_used, 0)


func test_next_tier_unknown_tier_is_an_error() -> void:
	assert_eq(Loot.next_tier("bogus"), "")
	assert_push_error("unknown tier")
	assert_eq(Loot.next_tier("legendary"), "")
	assert_eq(Loot.next_tier("bronze"), "silver")

