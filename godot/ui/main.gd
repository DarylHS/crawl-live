extends Control
## Main scene (P4): a run in the first-person 3D view, with a PLACEHOLDER status panel and log.
##
##   godot --path godot                              # a random seed, the first companion (cat)
##   godot --path godot -- --seed 1234 --pet dog     # a fixed seed; --pet cat|dog|budgie|mouse|none
##
## Title, character creation, the real HUD and menus arrive in P5-P7; until then the Status and
## Log labels are plain text, and Enter after death or victory starts a new run with a new seed.
## Headless (`godot --headless --path godot`) it still loads every content table, prints a summary
## and quits, as the P0 placeholder did.

@onready var fp_view: FpView = $FpView
@onready var status: Label = $Status
@onready var log_label: Label = $Log

var _seed: Variant = null
var _pet: Variant = null
var _status_wait: float = 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_print_content_summary()
		return
	var args := _parse_args(OS.get_cmdline_user_args())
	if args.has("seed"):
		_seed = int(args["seed"])            # else keep a seed set before _ready (screenshots)
	var species: String = args.get("pet", Content.table("pets").keys()[0])
	_pet = null if species == "none" else [species, ""]
	fp_view.new_run_requested.connect(_new_run)
	_new_run()


## Start a run: the fixed seed the first time (if given), then random seeds, as Python's App.
func _new_run() -> void:
	var w := World.new(_seed, _pet, default_hero())
	_seed = null
	fp_view.start(w)
	print("Crawl Live! seed %d" % w.seed)


func _process(delta: float) -> void:
	var w := fp_view.world
	if w == null:
		return
	_status_wait -= delta
	if _status_wait > 0.0:
		return
	_status_wait = 0.1
	status.text = status_text(w, fp_view.logic)
	var lines: Array[String] = []
	for line in w.messages.recent(7):
		lines.append(line[0])
	log_label.text = "\n".join(lines)


## Python App's hero when you press Enter through character creation: "Crawler", the first
## gender and the first backstory (so a fixed seed makes the same run as `python main.py`).
static func default_hero() -> Dictionary:
	return {"name": "Crawler", "gender": Content.table("genders").keys()[0],
			"backstory": Content.table("backstories").keys()[0]}


## The placeholder status panel's text (P6 replaces it with the real side panel).
static func status_text(w: World, view: FpLogic) -> String:
	var p := w.player
	var out: Array[String] = [
		"Floor %d   Turn %d" % [w.depth, w.turn],
		"HP %d / %d" % [p.hp, p.max_hp],
		"Gold %d" % w.gold,
		"Collapse in %s" % w.timer_text(),
	]
	if w.exit_sealed:
		out.append("Exit sealed")
	elif w.stairs_locked:
		out.append("Stairs locked: %s" % w.timer_text(w.stairs_wait))
	else:
		out.append("Stairs open")
	out.append("Facing %s (%d)" % [view.compass(), int(view.angle)])
	if w.combat != null:
		var parts: Array[String] = []
		for part in ["move", "action", "bonus"]:
			parts.append(part.capitalize() if w.combat.has(part) else "-")
		out.append("COMBAT round %d: %s" % [w.combat.round, " ".join(parts)])
	if w.on_stairs:
		out.append("Stairs here: > or Enter")
	if w.state == "dead":
		out.append("\nYou died. Enter: new run")
	elif w.state == "victory":
		out.append("\nYou escaped! Enter: new run")
	out.append("\nW/S walk, A/D strafe, Q/E turn")
	out.append("Space wait, > descend")
	out.append("%d FPS" % Engine.get_frames_per_second())
	return "\n".join(out)


## --key value pairs (and bare --flag) from the user arguments after `--`.
static func _parse_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < args.size():
		var a := args[i]
		if a.begins_with("--"):
			var k := a.substr(2)
			if "=" in k:
				out[k.get_slice("=", 0)] = k.get_slice("=", 1)
			elif i + 1 < args.size() and not args[i + 1].begins_with("--"):
				out[k] = args[i + 1]
				i += 1
			else:
				out[k] = ""
		i += 1
	return out


func _print_content_summary() -> void:
	var names := Content.names()
	var bad := 0
	for n in names:
		if Content.table(n) == null:
			bad += 1
	print("Crawl Live! content: %d tables (%d failed), %d monsters, %d achievements, %d lines events, manifest commit %s" % [
		names.size(), bad, Content.table("monsters").size(), Content.table("achievements").size(),
		Content.table("lines").size(), String(Content.manifest()["source_commit"]).left(8)])
	get_tree().quit(1 if bad > 0 else 0)
