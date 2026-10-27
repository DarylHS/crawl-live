extends SceneTree
## Godot side of the parity traces (port plan 6.2). Floor-only, pure generate_floor mode for now;
## the run mode follows with World.
##
##   godot --headless --path godot -s res://tools/trace.gd -- --seed 5 --floor-only --floors 6 --out /tmp/gd.jsonl
##   godot --headless --path godot -s res://tools/trace.gd -- --seeds 0-199 --floor-only --out-dir /tmp/gd_floors
##       (writes floors_<seed>.jsonl per seed, like scripts/py_trace.py)
## Compare with: python scripts/parity_diff.py --dirs /tmp/py_floors /tmp/gd_floors
## Default --floors is 6; default output without --out is ./trace_<seed>.jsonl.


func _initialize() -> void:
	var opts := {}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a == "--floor-only" or a == "--spawns" or a == "--no-msg":
			opts[a] = true
		elif a.begins_with("--") and i + 1 < args.size():
			opts[a] = args[i + 1]
			i += 1
		i += 1
	if not opts.has("--floor-only") or opts.has("--spawns"):
		printerr("trace.gd: only --floor-only (without --spawns) is implemented so far")
		quit(2)
		return
	var seeds: Array = []
	if opts.has("--seeds"):
		if not opts.has("--out-dir"):
			printerr("--seeds needs --out-dir")
			quit(2)
			return
		var t: String = opts["--seeds"]
		if t.contains("-"):
			var p := t.split("-")
			for s in range(int(p[0]), int(p[1]) + 1):
				seeds.append(s)
		else:
			seeds.append(int(t))
	else:
		seeds.append(int(opts.get("--seed", "0")))
	var floors := int(opts.get("--floors", "6"))
	if opts.has("--out-dir"):
		DirAccess.make_dir_recursive_absolute(opts["--out-dir"])
	for seed_value in seeds:
		var path: String
		if opts.has("--out-dir"):
			path = "%s/floors_%d.jsonl" % [opts["--out-dir"], seed_value]
		else:
			path = opts.get("--out", "trace_%d.jsonl" % seed_value)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			printerr("cannot write ", path)
			quit(2)
			return
		f.store_string(TraceFloors.to_lines(TraceFloors.run_floors(seed_value, floors)))
		f.close()
		print("wrote ", path)
	quit(0)
