class_name ShopStock
extends RefCounted
## One item's stock record in the shop (the Stock dataclass in crawler/shop.py).

var on_hand: int
var forecast: float
var on_order: int = 0
## Total demand per floor.
var history: Array = []


func _init(p_on_hand: int = 0, p_forecast: float = 0.0, p_on_order: int = 0, p_history: Array = []) -> void:
	on_hand = p_on_hand
	forecast = p_forecast
	on_order = p_on_order
	history = p_history


## vars(stock): the fields in dataclass order (the save layout).
func to_dict() -> Dictionary:
	return {"on_hand": on_hand, "forecast": forecast, "on_order": on_order, "history": history}


## Stock(**d). Numbers are coerced to the declared types (a JSON round trip gives floats); SaveGame
## (slice T5) still owns schema coercion of the whole save.
static func from_dict(d: Dictionary) -> ShopStock:
	return ShopStock.new(int(d["on_hand"]), float(d["forecast"]), int(d.get("on_order", 0)),
			d.get("history", []))
