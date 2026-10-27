extends TestCase
## tests/test_phase4.py, the parts that need no World: item values, box stats against simulation and
## the shop policy tests. The rest (kills, trade-up, reroll, shop in World, contracts in World, fun
## facts, run report, save) is listed in docs/port-plan.md B.1.


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
