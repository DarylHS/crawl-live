extends SceneTree
## Headless bot CLI (port plan 8.4; analysis/bot.py main). Plays runs with BotPolicy and appends each
## run's telemetry tables to <runs-dir>/bot_<table>.csv through Telemetry and PyCsv.
##
##   godot --headless --path godot -s res://tools/bot.gd -- --runs 100 --start 0 --runs-dir /abs/dir
##       [--deals random|accept|decline] [--pet cat|dog|budgie|mouse|none] [--no-events] [--summary-only]
##       [--summary-out FILE]
##
## --runs-dir defaults to user://runs (owner decision 5); a relative path is taken against the shell's
## working directory. Old bot_*.csv files are deleted only when --start is 0 (a fresh generation),
## otherwise runs append. --no-events skips bot_events.csv (the committed runs/bot_*.csv were made so).
## --summary-only writes no CSVs. --summary-out writes one JSON summary per run (JSON lines) so
## scripts/gd_bot.py can print the combined statistics of its shards.
##
## The bot's run plays inside BotPolicy.play, which holds the Telemetry for the whole run; the tables
## of one run are encoded and appended as soon as the run ends (never the whole batch in memory).

const _VALUE_OPTS := ["--runs", "--start", "--pet", "--deals", "--runs-dir", "--summary-out"]
const _FLAG_OPTS := ["--no-events", "--summary-only"]
const TABLES := ["runs", "floors", "boxes", "shop", "practice", "events"]


func _fail(msg: String) -> void:
	printerr("bot.gd: ", msg)
	quit(2)


## Relative paths are taken against the shell's working directory, not the project.
func _resolve(path: String) -> String:
	if path.begins_with("user://") or path.is_absolute_path():
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
	for k in ["--runs", "--start"]:
		if opts.has(k) and not String(opts[k]).is_valid_int():
			_fail("%s needs an integer, got '%s'" % [k, opts[k]])
			return
	var runs := int(opts.get("--runs", "200"))
	var start := int(opts.get("--start", "0"))
	var pet: String = opts.get("--pet", "")
	var pets: Array = Content.table("pets").keys()
	if pet != "" and pet != "none" and not pets.has(pet):
		_fail("--pet needs one of %s or none, got '%s'" % [", ".join(PackedStringArray(pets)), pet])
		return
	var deals: String = opts.get("--deals", "random")
	if not (deals in ["random", "accept", "decline"]):
		_fail("--deals needs random, accept or decline, got '%s'" % deals)
		return
	var runs_dir := _resolve(opts.get("--runs-dir", "user://runs"))
	var log_csv := not opts.has("--summary-only")
	var skip: Array = ["events"] if opts.has("--no-events") else []
	if log_csv:
		DirAccess.make_dir_recursive_absolute(runs_dir)
		if start == 0:
			for table_name in TABLES:        # a fresh generation replaces the old data
				var path := runs_dir.path_join("bot_%s.csv" % table_name)
				if FileAccess.file_exists(path):
					DirAccess.remove_absolute(path)
	var summary_fh: FileAccess = null
	if opts.has("--summary-out"):
		summary_fh = FileAccess.open(_resolve(opts["--summary-out"]), FileAccess.WRITE)
		if summary_fh == null:
			_fail("cannot write " + String(opts["--summary-out"]))
			return
	var t0 := Time.get_ticks_msec()
	var summaries: Array = []
	for seed_value in range(start, start + runs):
		var r := BotPolicy.play(seed_value, pet, deals, log_csv)
		var summary := _summary(r[0])
		summaries.append(summary)
		if summary_fh != null:
			summary_fh.store_line(PyJson.dumps(summary))
		if log_csv:
			if not PyCsv.write_tables(r[1], runs_dir, "bot_", skip):
				_fail("cannot write the CSV files in " + runs_dir)
				return
	if summary_fh != null:
		summary_fh.close()
	_print_summary(summaries, (Time.get_ticks_msec() - t0) / 1000.0)
	quit(0)


## The per-run summary of analysis/bot.py `_worker`.
func _summary(w: World) -> Dictionary:
	var outcome: String
	if w.state == "victory":
		outcome = "victory"
	elif w.state == "playing":
		outcome = "floor %d stuck" % w.depth
	else:
		outcome = "floor %d " % w.depth + ("collapse" if String(w.death_cause).contains("collapsed") else "killed")
	var gold := 0
	for f in w.floor_stats:
		gold += f["gold"]
	var s := {}
	s["outcome"] = outcome
	s["pet"] = w.pet.species if w.pet != null else "none"
	s["cls"] = w.cls
	s["race"] = w.race
	s["backstory"] = w.backstory
	s["won"] = w.state == "victory"
	s["viewers"] = w.viewers
	s["gold"] = gold
	s["boxes"] = w.box_log.size()
	s["achievements"] = w.achievements.unlocked.keys()
	s["skills"] = w.training.levels.duplicate()
	return s


## Python main()'s summary lines.
func _print_summary(summaries: Array, secs: float) -> void:
	var n := summaries.size()
	print("%d runs in %ss with 1 workers" % [n, PyFmt.fixed(secs, 0)])
	if n == 0:
		return
	var outcomes := {}
	for s in summaries:
		outcomes[s["outcome"]] = int(outcomes.get(s["outcome"], 0)) + 1
	var names: Array = outcomes.keys()
	names.sort()
	for k in names:
		print("  %s %5d (%s)" % [PyFmt.ljust(k, 22), outcomes[k], PyFmt.percent(float(outcomes[k]) / n, 0)])
	for key in ["pet", "backstory", "race", "cls"]:
		var groups := {}
		var wins := {}
		for s in summaries:
			if PyMath.truthy(s[key]):
				groups[s[key]] = int(groups.get(s[key], 0)) + 1
				if s["won"]:
					wins[s[key]] = int(wins.get(s[key], 0)) + 1
		var gk: Array = groups.keys()
		gk.sort()
		var parts := PackedStringArray()
		for g in gk:
			parts.append("%s %s of %d" % [g, PyFmt.percent(float(wins.get(g, 0)) / groups[g], 0), groups[g]])
		print("  win rate by %s: %s" % [key, ", ".join(parts)])
	print("  median viewers %s, gold %d, boxes %d" % [PyFmt.thousands(_median(summaries, "viewers")),
			_median(summaries, "gold"), _median(summaries, "boxes")])
	var means: Array = []
	for k in summaries[0]["skills"]:
		var total := 0
		for s in summaries:
			total += s["skills"][k]
		means.append([k, float(total) / n])
	var ordered := PyMath.stable_sort_by(means, func(kv: Array) -> float: return -kv[1])
	var texts := PackedStringArray()
	for kv in ordered:
		texts.append("%s %s" % [kv[0], PyFmt.fixed(kv[1], 1)])
	print("  mean practice level: " + ", ".join(texts))


func _median(summaries: Array, key: String) -> int:
	var xs: Array = []
	for s in summaries:
		xs.append(s[key])
	xs.sort()
	return xs[xs.size() / 2]
