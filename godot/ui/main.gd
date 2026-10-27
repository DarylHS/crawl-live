extends Node
## Placeholder main scene (P0): loads every content table and prints a summary. Headless runs
## (`godot --headless --path godot`) quit straight after printing; real presentation arrives in P4.

func _ready() -> void:
	var names := Content.names()
	var bad := 0
	for n in names:
		if Content.table(n) == null:
			bad += 1
	print("Crawl Live! content: %d tables (%d failed), %d monsters, %d achievements, %d lines events, manifest commit %s" % [
		names.size(), bad, Content.table("monsters").size(), Content.table("achievements").size(),
		Content.table("lines").size(), String(Content.manifest()["source_commit"]).left(8)])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if bad > 0 else 0)
