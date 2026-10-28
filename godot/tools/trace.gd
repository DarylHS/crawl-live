extends SceneTree
## Godot side of the parity traces (port plan 6.2): floor-only modes (pure generate_floor, and World mode
## with --spawns) and run mode (a policy plays the World: --policy walk or hunter; bot needs T6).
##
##   godot --headless --path godot -s res://tools/trace.gd -- --seed 5 --policy walk --steps 500 --out /tmp/gd.jsonl
##       [--pet cat|dog|budgie|mouse|none] [--hero GENDER:BACKSTORY] [--no-msg]
##   godot --headless --path godot -s res://tools/trace.gd -- --seeds 0-49 --policy walk --steps 500 --out-dir /tmp/gd_walk
##       (writes <policy>_<seed>.jsonl per seed, like scripts/py_trace.py; default --policy hunter,
##       default --steps 500)
##
##   godot --headless --path godot -s res://tools/trace.gd -- --seed 5 --floor-only --floors 6 --out /tmp/gd.jsonl
##   godot --headless --path godot -s res://tools/trace.gd -- --seeds 0-199 --floor-only --out-dir /tmp/gd_floors
##       (writes floors_<seed>.jsonl per seed, like scripts/py_trace.py)
##   add --spawns for World mode: World.new(seed, pet, hero), then new_floor(2..floors) (monsters,
##   items, timers); --pet cat|dog|budgie|mouse|none and --hero GENDER:BACKSTORY as in py_trace.py
## Compare with: python scripts/parity_diff.py --dirs /tmp/py_floors /tmp/gd_floors
## Default --floors is 6; default output without --out is ./trace_<seed>.jsonl.


const _VALUE_OPTS := ["--seed", "--seeds", "--floors", "--out", "--out-dir", "--pet", "--hero", "--policy", "--steps"]
const _FLAG_OPTS := ["--floor-only", "--spawns", "--no-msg"]


func _fail(msg: String) -> void:
	printerr("trace.gd: ", msg)
	quit(2)


## Relative paths are taken against the shell's working directory (Python's cwd), not the project.
func _resolve(path: String) -> String:
	if path.is_absolute_path():
		return path
	var cwd := OS.get_environment("PWD")
	return path if cwd == "" else cwd.path_join(path)


func _initialize() -> void:
	var opts := {}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a in _FLAG_OPTS:
			opts[a] = true
		elif a in _VALUE_OPTS:
			if i + 1 >= args.size():
				_fail("option %s needs a value" % a)
				return
			opts[a] = args[i + 1]
			i += 1
		else:
			_fail("unknown option or argument: " + a)
			return
		i += 1
	for k in ["--seed", "--floors", "--steps"]:
		if opts.has(k) and not String(opts[k]).is_valid_int():
			_fail("%s needs an integer, got '%s'" % [k, opts[k]])
			return
	var seeds: Array = []
	if opts.has("--seeds"):
		if not opts.has("--out-dir"):
			_fail("--seeds needs --out-dir")
			return
		var parts := String(opts["--seeds"]).split("-")
		for part in parts:
			if not part.is_valid_int():
				_fail("--seeds needs N or A-B, got '%s'" % opts["--seeds"])
				return
		if parts.size() == 1:
			seeds.append(int(parts[0]))
		elif parts.size() == 2:
			for s in range(int(parts[0]), int(parts[1]) + 1):
				seeds.append(s)
		else:
			_fail("--seeds needs N or A-B, got '%s'" % opts["--seeds"])
			return
	else:
		seeds.append(int(opts.get("--seed", "0")))
	var floors := int(opts.get("--floors", "6"))
	var policy: String = opts.get("--policy", "hunter")
	if not opts.has("--floor-only") and not (policy in TracePolicies.POLICY_NAMES):
		_fail("--policy needs one of %s, got '%s'" % [", ".join(TracePolicies.POLICY_NAMES), policy])
		return
	var steps := int(opts.get("--steps", "500"))
	if opts.has("--pet") and opts["--pet"] != "none" and not Content.table("pets").has(opts["--pet"]):
		_fail("--pet needs one of %s or none, got '%s'" % [", ".join(PackedStringArray(Content.table("pets").keys())), opts["--pet"]])
		return
	if not opts.has("--floor-only"):
		var have := {}
		for m in (World as GDScript).get_script_method_list():
			have[m["name"]] = true
		var needs: Array = TracePolicies.POLICY_METHODS.get(policy, [])
		for method in needs:
			if not have.has(method):
				_fail("policy '%s' needs World.%s, which is not ported yet" % [policy, method])
				return
	var out_dir := ""
	if opts.has("--out-dir"):
		out_dir = _resolve(opts["--out-dir"])
		DirAccess.make_dir_recursive_absolute(out_dir)
	for seed_value in seeds:
		var path: String
		if out_dir != "":
			path = "%s/%s_%d.jsonl" % [out_dir, "floors" if opts.has("--floor-only") else policy, seed_value]
		else:
			path = _resolve(opts.get("--out", "trace_%d.jsonl" % seed_value))
		var records: Array
		var pet: String = opts.get("--pet", "")
		if pet == "none":
			pet = ""
		var hero: Variant = null
		if opts.has("--hero"):
			var parts := String(opts["--hero"]).split(":")
			var story := parts[1] if parts.size() > 1 else ""
			hero = {"name": "Bot", "gender": null if parts[0] == "" else parts[0],
					"backstory": null if story == "" else story}
		if not opts.has("--floor-only"):
			records = TraceRun.run_trace(seed_value, policy, steps, pet, hero, not opts.has("--no-msg"))
			if records.is_empty():
				_fail("policy '%s' is not available yet" % policy)
				return
		elif opts.has("--spawns"):
			records = TraceFloors.run_floors_world(seed_value, floors, pet, hero)
		else:
			records = TraceFloors.run_floors(seed_value, floors)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			_fail("cannot write " + path)
			return
		f.store_string(TraceFloors.to_lines(records))
		f.close()
		print("wrote ", path)
	quit(0)
