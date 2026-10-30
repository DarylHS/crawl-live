extends Control
## Main scene (P6): a run in the first-person 3D view or the top-down map (Tab), with the real HUD (Hud).
##
##   godot --path godot                              # a random seed, the first companion (cat)
##   godot --path godot -- --seed 1234 --pet dog     # a fixed seed; --pet cat|dog|budgie|mouse|none
##
## Title, character creation and menus arrive in P7; until then Enter after death or victory starts
## a new run with a new seed.
## Headless (`godot --headless --path godot`) it still loads every content table, prints a summary
## and quits, as the P0 placeholder did.

@onready var game_view: GameView = $GameView
@onready var hud: Hud = $Hud

var _seed: Variant = null
var _pet: Variant = null


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		_print_content_summary()
		return
	var args := _parse_args(OS.get_cmdline_user_args())
	if args.has("seed"):
		_seed = int(args["seed"])            # else keep a seed set before _ready (screenshots)
	var species: String = args.get("pet", Content.table("pets").keys()[0])
	_pet = null if species == "none" else [species, ""]
	game_view.new_run_requested.connect(_new_run)
	_new_run()


## Start a run: the fixed seed the first time (if given), then random seeds, as Python's App.
func _new_run() -> void:
	var w := World.new(_seed, _pet, default_hero())
	_seed = null
	game_view.start(w)
	hud.bind(game_view)
	print("Crawl Live! seed %d" % w.seed)


## Python App's hero when you press Enter through character creation: "Crawler", the first
## gender and the first backstory (so a fixed seed makes the same run as `python main.py`).
static func default_hero() -> Dictionary:
	return {"name": "Crawler", "gender": Content.table("genders").keys()[0],
			"backstory": Content.table("backstories").keys()[0]}


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
