extends SceneTree
## Save/load parity harness, Godot side (slice T5): the command line of scripts/save_trace.py, same options and
## file names (see its docstring; the work is in tools/save_trace_run.gd).
##
##   godot --headless --path godot -s res://tools/save_trace.gd -- --seeds 0-9 --steps 300 --out-dir DIR
##       [--load-dir OTHER_DIR]     # also continue OTHER_DIR/save_<seed>.json (written by Python) as xload_<seed>.jsonl
##       [--load-only]              # with --load-dir: play nothing, only write the xload files
##
## Relative paths are taken against the shell's working directory, as Python does.


func _resolve(path: String) -> String:
	if path.is_absolute_path():
		return path
	var cwd := OS.get_environment("PWD")
	return path if cwd == "" else cwd.path_join(path)


func _initialize() -> void:
	var seeds: Array = []
	var steps := 300
	var out_dir := ""
	var load_dir := ""
	var load_only := false
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		match a[i]:
			"--seeds":
				var parts := String(a[i + 1]).split("-")
				var hi := int(parts[parts.size() - 1])
				for s in range(int(parts[0]), hi + 1):
					seeds.append(s)
				i += 1
			"--steps":
				steps = int(a[i + 1])
				i += 1
			"--out-dir":
				out_dir = _resolve(a[i + 1])
				i += 1
			"--load-only":
				load_only = true
			"--load-dir":
				load_dir = _resolve(a[i + 1])
				i += 1
			_:
				push_error("save_trace.gd: unknown argument " + a[i])
				quit(2)
				return
		i += 1
	if seeds.is_empty() or out_dir == "":
		push_error("save_trace.gd: give --seeds A-B --out-dir DIR")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	for sd in seeds:
		if load_only:
			var other_save := "%s/save_%d.json" % [load_dir, sd]
			if FileAccess.file_exists(other_save):
				SaveTraceRun.continue_run(SaveGame.load(other_save), sd, steps, "%s/xload_%d.jsonl" % [out_dir, sd])
			continue
		var c := SaveTraceRun.play_to_save_point(sd)
		var w := c.w
		if w.state != "playing" or w.combat != null:
			var f := FileAccess.open("%s/skip_%d" % [out_dir, sd], FileAccess.WRITE)
			f.store_string("no save point\n")
			f.close()
			continue
		var path := "%s/save_%d.json" % [out_dir, sd]
		SaveGame.save(w, path)
		var v := SaveGame.load(path)
		SaveTraceRun.continue_run(v, sd, steps, "%s/loaded_%d.jsonl" % [out_dir, sd])
		SaveTraceRun.drop_unsaved(w)
		SaveTraceRun.continue_run(w, sd, steps, "%s/direct_%d.jsonl" % [out_dir, sd])
		if load_dir != "":
			var other := "%s/save_%d.json" % [load_dir, sd]
			if FileAccess.file_exists(other):
				SaveTraceRun.continue_run(SaveGame.load(other), sd, steps, "%s/xload_%d.jsonl" % [out_dir, sd])
	quit(0)
