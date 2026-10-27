class_name Shop
extends RefCounted
## The safe-room shop: a small inventory simulation (crawler/shop.py).
##
## One shop franchise serves every safe room, so its stock carries between floors. Other crawlers
## buy from it too (Poisson demand per floor). At the end of each floor the shop:
##   1. sells to the other crawlers (unmet demand is a lost sale, a stockout),
##   2. updates its demand forecast by exponential smoothing,
##   3. receives last floor's order (lead time: one floor),
##   4. reorders up to its target if stock is at or below the reorder point.
## Prices rise as stock runs low. end_of_floor iterates `stock` in BASE_DEMAND order and draws one
## Poisson number per item, so that order is the RNG order.

## Demand rises 10% per floor as crawlers get desperate.
static var DEMAND_GROWTH: float = Content.config("shop")["DEMAND_GROWTH"]
## Forecast smoothing weight on the newest floor.
static var ALPHA: float = Content.config("shop")["ALPHA"]
## Floors between ordering and delivery.
static var LEAD_TIME: int = Content.config("shop")["LEAD_TIME"]
## Safety stock in standard deviations of lead-time demand.
static var SAFETY_Z: float = Content.config("shop")["SAFETY_Z"]
## Up to +60% on price as stock runs out.
static var SCARCITY_MARKUP: float = Content.config("shop")["SCARCITY_MARKUP"]
## The shop buys items from you at 40% of value.
static var SELL_RATE: float = Content.config("shop")["SELL_RATE"]

var rng: PyRandom
## Item key to ShopStock, in BASE_DEMAND order.
var stock: Dictionary = {}
## One row (Dictionary) per item per floor.
var log: Array = []
## Player purchases this floor.
var bought: Dictionary = {}
## Player tried to buy, sold out.
var missed: Dictionary = {}


## Other crawlers' average demand per floor, before the depth multiplier (shop.json).
static func base_demand() -> Dictionary:
	return Content.table("shop")["base_demand"]


func _init(p_rng: PyRandom) -> void:
	rng = p_rng
	var demand := base_demand()
	for k in demand:
		stock[k] = ShopStock.new(0, demand[k])
	for k in stock:
		stock[k].on_hand = ceili(order_up_to(k))     # open fully stocked
	for k in demand:
		bought[k] = 0
		missed[k] = 0


# --- Policy numbers ------------------------------------------------

func safety_stock(key: String) -> float:
	# Poisson demand: variance equals the mean.
	return SAFETY_Z * sqrt(stock[key].forecast * LEAD_TIME)


func reorder_point(key: String) -> float:
	return stock[key].forecast * LEAD_TIME + safety_stock(key)


func order_up_to(key: String) -> float:
	var f: float = stock[key].forecast
	return f * (LEAD_TIME + 1) + SAFETY_Z * sqrt(f * (LEAD_TIME + 1))


func price(key: String) -> int:
	var s: ShopStock = stock[key]
	var scarcity := maxf(0.0, 1 - s.on_hand / maxf(1.0, order_up_to(key)))
	return maxi(1, PyMath.round_half_even(Items.value(key) * (1 + SCARCITY_MARKUP * scarcity)))


static func sell_price(key: String) -> int:
	return maxi(1, PyMath.round_half_even(Items.value(key) * SELL_RATE))


# --- Player trades ----------------------------------------------------

## Take one unit for the player; "" (Python None) if sold out.
func buy(key: String) -> String:
	var s: ShopStock = stock[key]
	if s.on_hand <= 0:
		missed[key] += 1
		return ""
	s.on_hand -= 1
	bought[key] += 1
	return key


func take_back(key: String) -> void:
	if stock.has(key):
		stock[key].on_hand += 1


# --- Floor turnover ---------------------------------------------------

## Knuth's method; fine for the small means used here. One rng.random() per loop pass.
func _poisson(mean: float) -> int:
	var limit := exp(-mean)
	var k := 0
	var p := 1.0
	while true:
		p *= rng.random()
		if p <= limit:
			return k
		k += 1
	return k


func end_of_floor(depth: int) -> void:
	var demand_table := base_demand()
	for key in stock:
		var s: ShopStock = stock[key]
		var wanted := _poisson(demand_table[key] * (1 + DEMAND_GROWTH * depth))
		var sold := mini(s.on_hand, wanted)
		s.on_hand -= sold
		var demand: int = wanted + bought[key] + missed[key]
		var lost: int = (wanted - sold) + missed[key]
		s.history.append(demand)
		var forecast_before := s.forecast
		s.forecast = ALPHA * demand + (1 - ALPHA) * s.forecast
		var delivered := s.on_order
		s.on_hand = s.on_hand + s.on_order
		s.on_order = 0
		var rop := reorder_point(key)
		var target := order_up_to(key)
		if s.on_hand <= rop:
			s.on_order = maxi(0, ceili(target - s.on_hand))
		log.append({"depth": depth, "item": key, "demand": demand, "sales": sold + bought[key],
				"lost": lost, "delivered": delivered, "on_hand": s.on_hand,
				"forecast_before": PyMath.round_n(forecast_before, 3),
				"forecast": PyMath.round_n(s.forecast, 3), "reorder_point": PyMath.round_n(rop, 3),
				"ordered": s.on_order})
		bought[key] = 0
		missed[key] = 0


# --- Save / load ------------------------------------------------------

func to_dict() -> Dictionary:
	var st := {}
	for k in stock:
		st[k] = stock[k].to_dict()
	return {"stock": st, "log": log, "bought": bought, "missed": missed}


## Replace the shop's state from a to_dict() dictionary (the caller owns schema coercion).
func load(d: Dictionary) -> void:
	stock = {}
	for k in d["stock"]:
		stock[k] = ShopStock.from_dict(d["stock"][k])
	log = d["log"]
	bought = d["bought"]
	missed = d["missed"]
