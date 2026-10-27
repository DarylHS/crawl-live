extends SceneTree
## Godot side of the parity traces (port plan 6.2). Floor-only, pure generate_floor mode for now;
## the run mode follows with World.
##
##   godot --headless --path godot -s res://tools/trace.gd -- --seed 5 --floor-only --floors 6 --out /tmp/gd.jsonl
##   godot --headless --path godot -s res://tools/trace.gd -- --seeds 0-199 --floor-only --out-dir /tmp/gd_floors
##       (writes floors_<seed>.jsonl per seed, like scripts/py_trace.py)
##   add --spawns for World mode: World.new(seed), then new_floor(2..floors) (monsters, items, timers)
## Compare with: python scripts/parity_diff.py --dirs /tmp/py_floors /tmp/gd_floors
## Default --floors is 6; default output without --out is ./trace_<seed>.jsonl.


const _VALUE_OPTS := ["--seed", "--seeds", "--floors", "--out", "--out-dir"]
const _FLAG_OPTS := ["--floor-only", "--spawns"]


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
	if not opts.has("--floor-only"):
		_fail("only --floor-only is implemented so far")
		return
	for k in ["--seed", "--floors"]:
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
	var out_dir := ""
	if opts.has("--out-dir"):
		out_dir = _resolve(opts["--out-dir"])
		DirAccess.make_dir_recursive_absolute(out_dir)
	for seed_value in seeds:
		var path: String
		if out_dir != "":
			path = "%s/floors_%d.jsonl" % [out_dir, seed_value]
		else:
			path = _resolve(opts.get("--out", "trace_%d.jsonl" % seed_value))
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			_fail("cannot write " + path)
			return
		var records: Array
		if opts.has("--spawns"):
			records = TraceFloors.run_floors_world(seed_value, floors)
		else:
			records = TraceFloors.run_floors(seed_value, floors)
		f.store_string(TraceFloors.to_lines(records))
		f.close()
		print("wrote ", path)
	quit(0)
