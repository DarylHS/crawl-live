extends TestCase
## Per-seed parity for slice S4 against Python: scripts/make_fixtures_s4.py runs, for seeds 0-199 (0-49 in the suite), a
## scripted sequence over the loot stream (seed ^ 0x100F) and the shop stream (seed ^ 0x5A0F): box
## rolls for every tier, floor loot tables and draws, odds / box_stats / reroll_fee, item texts,
## crafting, boss and Act stat blocks, Encounter initiative with ties, contract effects and previews
## (on a World stand-in), and a persistent Shop run over many floors (Poisson demand, restocking,
## forecasts, prices, buys, mutations, save/load). Each step replays the recorded arguments and
## compares every result, the words_used of both streams and their state digests (first 16 hex).

var _mismatches := 0
var _steps := 0
var _shop: Shop = null


## [rows, bought, missed, log length]; rows for every item or only `only`.
func _shop_view(s: Shop, only: String = "") -> Array:
	var rows: Array = []
	for k in s.stock:
		if only != "" and k != only:
			continue
		var st: ShopStock = s.stock[k]
		rows.append([k, st.on_hand, st.forecast, st.on_order, st.history.size(),
			st.history[-1] if not st.history.is_empty() else null, s.price(k), s.reorder_point(k),
			s.safety_stock(k), s.order_up_to(k), Shop.sell_price(k)])
	return [rows, s.bought.duplicate(), s.missed.duplicate(), s.log.size()]


func _run_enc(step: Array) -> Array:
	var ents: Array = []
	for spec in step[1]:
		ents.append(S2Support.build(spec))
	var e := Encounter.new(ents[0])
	var out: Array = []
	for op in step[2]:
		var res: Variant = null
		match op[0]:
			"add":
				e.add(ents[op[1]], op[2], op[3])
			"remove":
				e.remove(ents[op[1]])
			"react":
				e.react(ents[op[1]])
			"ready":
				e.ready(ents[op[1]])
			"spend":
				e.spend(op[1])
			"reset":
				e.reset_budget()
			"look":
				var x: Entity = ents[op[1]]
				var inside := e.has_entity(x)
				res = [inside, e.can_react(x), e.total(x) if inside else null,
					_idxs(e.before(x), ents) if inside else null,
					_idxs(e.after(x), ents) if inside else null]
		var reacted: Array = _idxs(e.reacted.keys(), ents)
		reacted.sort()
		var keys: Array = []
		var totals: Array = []
		for row in e.order:
			keys.append(row[0])
		for y in e.entities:
			totals.append(e.total(y))
		out.append([res, _idxs(e.entities, ents), _idxs(e.monsters, ents), totals,
			[e.has("move"), e.has("action"), e.has("bonus")], e.turn_over, reacted, keys])
	return out


func _idxs(list: Array, ents: Array) -> Array:
	var out: Array = []
	for y in list:
		for i in ents.size():
			if is_same(ents[i], y):
				out.append(i)
				break
	return out


func _run_step(step: Array, loot: PyRandom, shop_rng: PyRandom) -> Array:
	match step[0]:
		"box":
			return [Loot.roll_box(step[1], loot)]
		"floor_table":
			return Items.floor_loot_table(step[1])
		"floor_draw":
			var t := Items.floor_loot_table(step[1])
			var picks: Array = []
			for i in range(step[2]):
				picks.append(loot.choices(t[0], t[1])[0])
			return [picks, loot.choices(["tonic", "brew", "elixir"], [6, 3, 1])[0]]
		"odds":
			var tier: String = step[1]
			var nt := Loot.next_tier(tier)
			return [Loot.odds(tier), Loot.box_stats(tier), null if nt == "" else nt,
				Loot.reroll_fee(tier), Content.box(tier)["name"]]
		"item":
			return [Items.value(step[1]), Items.glyph(step[1]), Items.describe(step[1])]
		"craft":
			var oks: Array = []
			for r in Crafting.recipes():
				oks.append(Crafting.can_craft(r, step[1]))
			return [oks]
		"boss":
			var b := Bosses.spawn_boss(step[1], step[2], step[3])
			var apf := Bosses.acts_per_floor(step[1])
			return [b.to_dict(), Entities.init_mod(b), Bosses.boss_depth(b), [apf.x, apf.y]]
		"act":
			var a := Bosses.spawn_act(step[1], step[2], step[3], step[4])
			return [a.to_dict(), Entities.init_mod(a)]
		"enc":
			return _run_enc(step)
		"effect":
			var ew := World.new(1)
			ew.contract = step[1]
			return [Contracts.effect(ew, step[2], step[3])]
		"preview":
			var player := S2Support.build(step[2])
			var monsters: Array = []
			for spec in step[3]:
				monsters.append(S2Support.build(spec))
			var w := World.new(1)
			w.player = player as Player
			w.timer = step[5]
			w.floor_stats = (step[4] as Array).duplicate(true)
			w.monsters = monsters
			var lines := Contracts.preview(w, step[1])
			var bonuses: Array = []
			for m in monsters:
				bonuses.append(m.dmg_bonus)
			return [Array(lines), bonuses]
		"shop_new":
			_shop = Shop.new(shop_rng)
			return _shop_view(_shop)
		"shop_day":
			var before := _shop.log.size()
			_shop.end_of_floor(step[1])
			return [_shop.log.slice(before)] + _shop_view(_shop)
		"shop_buy":
			var got := _shop.buy(step[1])
			return [null if got == "" else got] + _shop_view(_shop, step[1])
		"shop_back":
			_shop.take_back(step[1])
			return _shop_view(_shop, step[1])
		"shop_set":
			match step[2]:
				"bought":
					_shop.bought[step[1]] = step[3]
				"missed":
					_shop.missed[step[1]] = step[3]
				_:
					_shop.stock[step[1]].set(step[2], step[3])
			return _shop_view(_shop, step[1])
		"poisson":
			return [_shop._poisson(step[1])]
		"shop_save":
			var d0 := _shop.to_dict()
			var s2 := Shop.new(PyRandom.new(0))
			s2.load(d0.duplicate(true))
			var same := TestCase.strict_diff(s2.to_dict(), d0) == ""
			var last: Variant = d0["log"][-1] if not d0["log"].is_empty() else null
			return [d0["stock"], d0["bought"], d0["missed"], d0["log"].size(), last, same]
		"shop_view":
			return _shop_view(_shop)
	push_error("unknown step kind %s" % str(step[0]))
	return []


func _check_seed(seed_value: int) -> String:
	var node: Dictionary = S4Support.doc()["seeds"][seed_value]
	assert_eq(int(node["seed"]), seed_value)
	var loot := PyRandom.new(seed_value ^ 0x100F)
	var shop_rng := PyRandom.new(seed_value ^ 0x5A0F)
	_shop = null
	var words := [-1, -1]
	var digests := ["", ""]
	var i := 0
	for enc_step in node["steps"]:
		var rec: Array = PyFixtures.decode(enc_step)
		var step: Array = rec[0]
		var res := _run_step(step, loot, shop_rng)
		# The digest is recomputed only when the stream moved; an unmoved stream cannot change state.
		if loot.words_used != words[0]:
			words[0] = loot.words_used
			digests[0] = loot.state_digest().substr(0, 16)
		if shop_rng.words_used != words[1]:
			words[1] = shop_rng.words_used
			digests[1] = shop_rng.state_digest().substr(0, 16)
		var got: Array = [step, res, [loot.words_used, digests[0], shop_rng.words_used, digests[1]]]
		_steps += 1
		var diff := TestCase.strict_diff(got, rec)
		if diff != "":
			_mismatches += 1
			return "seed %d step %d (%s): %s" % [seed_value, i, step[0], diff]
		i += 1
	return ""


func test_fixture_seeds() -> void:
	if not S4Support.require(self):
		return
	var seeds: Array = S4Support.doc()["seeds"]
	assert_gte(seeds.size(), 50)                  # gd_test.sh makes 50, parity_all.sh 200
	var first_failures: Array = []
	for s in range(seeds.size()):
		var msg := _check_seed(s)
		if msg != "" and first_failures.size() < 5:
			first_failures.append(msg)
	assert_eq(first_failures, [], "mismatching seeds (%d steps checked, %d mismatches)" % [_steps, _mismatches])
	assert_eq(_mismatches, 0)
	assert_gt(_steps, seeds.size() * 90)
	gut.p("S4 parity: %d steps over %d seeds, %d mismatches" % [_steps, seeds.size(), _mismatches])


func test_boss_stat_blocks_per_depth() -> void:
	if not S4Support.require(self):
		return
	for row in S4Support.rows("boss_blocks"):
		var b := Bosses.spawn_boss(row[0], 3, 4)
		assert_eq(b.to_dict(), row[1], "boss %d" % row[0])
		assert_eq(Entities.init_mod(b), row[2])
		assert_eq(Content.boss(row[0]).get("final", false), row[3])
		var apf := Bosses.acts_per_floor(row[0])
		assert_eq([apf.x, apf.y], row[4])


func test_acts_match_python() -> void:
	if not S4Support.require(self):
		return
	for row in S4Support.rows("acts"):
		var a := Bosses.spawn_act(row[0][0], row[0][1], 5, 6)
		assert_eq(a.to_dict(), row[1], str(row[0]))
		assert_eq(Entities.init_mod(a), row[2])


func test_acts_per_floor_table() -> void:
	if not S4Support.require(self):
		return
	for row in S4Support.rows("acts_per_floor"):
		var apf := Bosses.acts_per_floor(row[0])
		assert_eq([apf.x, apf.y], row[1])


func test_item_texts_match_python() -> void:
	if not S4Support.require(self):
		return
	var rows := S4Support.rows("items")
	assert_eq(rows.size(), Items.items().size())
	for row in rows:
		assert_eq([Items.value(row[0]), Items.glyph(row[0]), Items.describe(row[0])], [row[1], row[2], row[3]])


func test_loot_tables_match_python() -> void:
	if not S4Support.require(self):
		return
	for row in S4Support.rows("loot"):
		var nt := Loot.next_tier(row[0])
		assert_eq([Loot.odds(row[0]), Loot.box_stats(row[0]), null if nt == "" else nt, Loot.reroll_fee(row[0])],
				[row[1], row[2], row[3], row[4]], row[0])


func test_shop_opens_as_python() -> void:
	if not S4Support.require(self):
		return
	var shop := Shop.new(PyRandom.new(1))
	for row in S4Support.rows("shop_open"):
		assert_eq([shop.stock[row[0]].on_hand, shop.price(row[0])], [row[1], row[2]], row[0])
