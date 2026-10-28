extends TestCase
## tests/test_phase4.py: item values, box stats against simulation, the shop policy tests (S4) and the
## shop turnover and contract tests on a World (S6), kills paying gold (S7) and trade-up, reroll and
## buying and selling in World (S8), the fun facts and the run report data (T3). The save test is
## listed in docs/port-plan.md B.1.


func _safe(w: World) -> void:
	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y
	w.update_fov()


func test_every_item_has_a_value() -> void:
	for k in Items.items():
		assert_gt(Items.value(k), 0)


func test_box_stats_match_simulation() -> void:
	var rng := PyRandom.new(3)
	for tier in Loot.TIERS:
		var st := Loot.box_stats(tier)
		var vals: Array = []
		for i in range(20000):
			vals.append(Items.value(Loot.roll_box(tier, rng)))
		var mean := PyMath.fsum_py(vals) / vals.size()
		var sq: Array = []
		for v in vals:
			sq.append(pow(v - mean, 2.0))
		var variance := PyMath.fsum_py(sq) / vals.size()
		assert_almost_eq(mean, st[0], absf(st[0]) * 0.03)
		assert_almost_eq(sqrt(variance), st[1], absf(st[1]) * 0.05)


func test_shop_opens_fully_stocked_with_sane_policy() -> void:
	var shop := Shop.new(PyRandom.new(1))
	for key in Shop.base_demand():
		var s: ShopStock = shop.stock[key]
		assert_gte(float(s.on_hand), shop.reorder_point(key))
		assert_gt(shop.order_up_to(key), shop.reorder_point(key))
		assert_gt(shop.reorder_point(key), 0.0)
		assert_eq(shop.price(key), Items.value(key))      # no markup when well stocked


func test_shop_restocks_after_reorder_point_with_one_floor_lead_time() -> void:
	var shop := Shop.new(PyRandom.new(2))
	var s: ShopStock = shop.stock["tonic"]
	s.on_hand = 0
	shop.end_of_floor(1)
	assert_gt(s.on_order, 0)
	assert_eq(s.on_hand, 0)                              # ordered, not yet delivered
	var ordered := s.on_order
	shop.end_of_floor(2)
	var n := Shop.base_demand().size()
	assert_eq(shop.log[shop.log.size() - n]["delivered"], ordered)


func test_stockout_counts_lost_sales_and_raises_price() -> void:
	var shop := Shop.new(PyRandom.new(3))
	var s: ShopStock = shop.stock["elixir"]
	var full_price := shop.price("elixir")
	s.on_hand = 1
	assert_gt(shop.price("elixir"), full_price)          # scarcity markup
	assert_eq(shop.buy("elixir"), "elixir")
	assert_eq(shop.buy("elixir"), "")
	shop.end_of_floor(1)
	var row: Dictionary = {}
	for r in shop.log:
		if r["item"] == "elixir":
			row = r
			break
	assert_gte(row["lost"], 1)
	assert_gte(row["sales"], 1)


func test_forecast_follows_demand() -> void:
	var shop := Shop.new(PyRandom.new(4))
	var s: ShopStock = shop.stock["tonic"]
	var before := s.forecast
	shop.bought["tonic"] = 20                            # a huge spike
	shop.end_of_floor(1)
	assert_gt(s.forecast, before)


func test_shop_turns_over_between_floors() -> void:
	var w := World.new(6)
	w.new_floor(2)
	assert_eq(w.shop.log.size(), Shop.base_demand().size())


# --- Contracts ----------------------------------------------------------------

func test_contracts_offered_from_floor_two() -> void:
	var offers := 0
	for seed_value in range(30):
		var w := World.new(seed_value)
		assert_null(w.pending_offer)
		w.new_floor(2)
		if w.pending_offer != null:
			offers += 1
	assert_true(10 < offers and offers < 30)                # OFFER_CHANCE is 70%


func test_accepting_hazard_pay_changes_monsters_and_gold() -> void:
	var w := World.new(7)
	w.new_floor(2)
	w.pending_offer = "hazard_pay"
	var before := {}
	for m in w.monsters:
		before[m.get_instance_id()] = [m.dmg_bonus, m.max_hp]
	assert_false(Contracts.preview(w, "hazard_pay").is_empty())
	w.accept_contract()
	assert_eq(w.contract, "hazard_pay")
	assert_null(w.pending_offer)
	assert_true("gold" in w.boxes)
	for m in w.monsters:
		var was: Array = before[m.get_instance_id()]
		assert_eq(m.dmg_bonus, was[0] + 2)
		assert_eq(m.max_hp, PyMath.round_half_even(was[1] * 1.25))
	w.new_floor(3)
	assert_null(w.contract)                                 # one floor only


func test_snack_sprint_shortens_the_timer() -> void:
	var w := World.new(8)
	w.new_floor(2)
	w.pending_offer = "snack_sprint"
	var t := w.timer
	w.accept_contract()
	assert_eq(w.timer, PyMath.round_half_even(t * 0.8))


func test_every_contract_previews() -> void:
	var w := World.new(9)
	w.new_floor(2)
	for key in Contracts.contracts():
		for line in Contracts.preview(w, key):
			assert_typeof(line, TYPE_STRING)
	# Preview must not leave monsters modified.
	for m in w.monsters:
		if not m.boss:
			assert_eq(m.dmg_bonus, Entities.spawn_monster(m.key, 0, 0).dmg_bonus)


func _adjacent_monster(w: World, key: String = "gnawer", hp: int = -1) -> Array:
	var p := w.player
	for n in DungeonFloor.NEIGHBOURS_8:
		var x := p.x + n.x
		var y := p.y + n.y
		if w.floor.walkable(x, y) and not w.floor.is_safe(x, y):
			var m := Entities.spawn_monster(key, x, y)
			if hp >= 0:
				m.hp = hp
			w.monsters.append(m)
			return [m, n]
	fail_test("no free tile")
	return []


func test_kills_pay_gold() -> void:
	var w := World.new(1)
	w.monsters.clear()
	var found := _adjacent_monster(w, "gnawer", 1)
	var m: Monster = found[0]
	var d: Vector2i = found[1]
	w.player.attack = 100
	for _i in range(5):
		if not w.monsters.has(m):
			break
		w.move_player(d.x, d.y)
	assert_gt(w.gold, 0)
	assert_eq(w.floor_stats[-1]["gold"], w.gold)


func test_trade_up_in_safe_room() -> void:
	var w := World.new(2)
	w.boxes = []
	for _i in range(Loot.TRADE_UP_COST):
		w.boxes.append("bronze")
	assert_false(w.trade_up("bronze"))                  # not in a safe room
	_safe(w)
	assert_true(w.trade_up("bronze"))
	assert_eq(w.boxes, ["silver"])
	w.boxes = ["legendary", "legendary", "legendary"]
	assert_false(w.trade_up("legendary"))               # nothing above legendary


func test_reroll_swaps_the_item_and_charges_the_fee() -> void:
	var w := World.new(4)
	_safe(w)
	w.boxes = ["platinum"]
	w.gold = 100
	assert_true(w.open_box("platinum"))
	var first: String = w.last_reveal[1]
	assert_true(w.reroll())
	assert_eq(w.gold, 100 - Loot.reroll_fee("platinum"))
	assert_eq(w.inventory.size(), 1)
	assert_true(w.box_log[-1]["rerolled"])
	assert_true(not w.inventory.has(first) or w.inventory == [w.last_reveal[1]])
	w.gold = 0
	assert_false(w.reroll())                            # can't afford another


func test_buying_and_selling_in_world() -> void:
	var w := World.new(5)
	w.gold = 50
	assert_false(w.shop_buy("tonic"))                   # not in a safe room
	_safe(w)
	var price := w.shop.price("tonic")
	assert_true(w.shop_buy("tonic"))
	assert_eq(w.gold, 50 - price)
	assert_eq(w.inventory, ["tonic"])
	assert_true(w.shop_sell(0))
	assert_eq(w.inventory, [])
	assert_gt(w.gold, 50 - price)
	w.gold = 0
	assert_false(w.shop_buy("elixir"))                  # can't afford it


# --- Fun facts ----------------------------------------------------------------

func _fun_facts(w: World, n: int) -> Array:
	var out: Array = []
	for line in w.messages.recent(n):
		if line[0].begins_with("FUN FACT"):
			out.append(line[0])
	return out


func test_miss_streak_fun_fact() -> void:
	var w := World.new(10)
	for _i in range(6):
		w.events.emit("player_attack", {"target": "goblin", "chance": 0.8, "hit": false, "crit": false})
	var text := _fun_facts(w, 10)
	assert_false(text.is_empty())
	assert_true("no memory" in text[-1])


func test_box_drought_fun_fact() -> void:
	var w := World.new(11)
	var rarest: String = PyMath.min_by(Loot.odds("bronze"), func(r: Array) -> float: return r[1])[0]
	var common: String = PyMath.max_by(Loot.odds("bronze"), func(r: Array) -> float: return r[1])[0]
	assert_ne(rarest, common)
	for _i in range(3):
		w.events.emit("box_opened", {"tier": "bronze", "item": common, "rerolled": false})
	var found := false
	for line in w.messages.recent(10):
		if "isn't 'due'" in line[0]:
			found = true
	assert_true(found)


func test_fun_facts_are_rate_limited() -> void:
	var w := World.new(12)
	w.events.emit("player_attack", {"target": "g", "chance": 0.5, "hit": true, "crit": true})
	w.events.emit("contract_accepted", {"contract": "gloop_blitz", "depth": 2})
	assert_eq(_fun_facts(w, 20).size(), 1)


# --- Report -------------------------------------------------------------------

func test_run_report_data() -> void:
	var w := World.new(13)
	_safe(w)
	w.boxes = ["silver", "gold"]
	w.open_box("silver")
	w.open_box("gold")
	for _i in range(25):
		w.wait()
	var rep := RunReport.build(w)
	assert_eq(rep["box_expected"].size(), 2)
	assert_almost_eq(float(rep["box_expected"][-1]), Loot.box_stats("silver")[0] + Loot.box_stats("gold")[0], 0.02)
	assert_eq(rep["damage_by_floor"][0][0], 1)
	assert_eq(rep["viewers"][-1][0], w.turn)
