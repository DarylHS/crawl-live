class_name AchievementRules
extends RefCounted
## The achievement tests as data (port plan 4.4): Python's per-achievement lambdas become `rule`
## objects in achievements.json and this one interpreter. scripts/export_content.py proves every
## rule agrees with its lambda (rule_test there is the Python twin of `test`).


## True when `rule` unlocks given the tracker `t` and the event payload `d`.
static func test(rule: Dictionary, t: AchievementTracker, d: Dictionary) -> bool:
	var kind: String = rule["kind"]
	match kind:
		"always":
			return true
		"counter_gte":
			return t.get(rule["counter"]) >= rule["n"]
		"field_gte":
			return d[rule["field"]] >= rule["n"]
		"field_eq":
			return d[rule["field"]] == rule["value"]
		"field_true":
			return PyMath.truthy(d.get(rule["field"], false))
		"field_lte_floordiv":
			return d[rule["field"]] <= PyMath.floordiv(d[rule["of"]], rule["div"])
		"field_lt_frac":
			return float(d[rule["field"]]) < float(rule["frac"]) * float(d[rule["of"]])
		"world_gte":
			# n_config is read at test time so patching GameConfig works (Python reads C.INVENTORY_SIZE).
			var cfg: Variant = GameConfig   # the class object: its static vars read by name
			var n: int = cfg.get(rule["n_config"]) if rule.has("n_config") else rule["n"]
			var w: Object = t.world
			var stat: int = w.viewers if rule["stat"] == "viewers" else w.inventory.size()
			return stat >= n
		"equipped_all":
			for slot in rule["slots"]:
				if not t.equipped.has(slot):
					return false
			return true
		"all":
			for r in rule["rules"]:
				if not test(r, t, d):
					return false
			return true
	push_error("AchievementRules: unknown rule kind " + kind)
	return false
