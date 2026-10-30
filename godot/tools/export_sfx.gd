extends SceneTree
## Writes every synthesised sound effect as a .wav file, to listen to or to start from when making real ones:
##
##   godot --headless --path godot -s res://tools/export_sfx.gd -- --out=/some/dir
##
## Drop a finished <name>.wav or <name>.ogg into godot/assets/sfx/ and SfxPlayer uses it instead of the
## synthesised one (names are the keys of SfxSynth.SOUNDS: hit, miss, crit, kill, step, descend, box_open,
## achievement, select, ...). Also prints each sound's length and peak.


func _initialize() -> void:
	var args := Main._parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", "")
	if out_dir == "":
		push_error("export_sfx.gd: pass -- --out=<dir>")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var bad := 0
	for n in SfxSynth.names():
		var path := out_dir.path_join(n + ".wav")
		var err := SfxSynth.stream(n).save_to_wav(path)
		var peak := 0.0
		for x in SfxSynth.samples(n):
			peak = maxf(peak, absf(x))
		print("%-12s %.2f s  peak %.2f  %s" % [n, SfxSynth.length(n), peak, error_string(err)])
		bad += int(err != OK)
	quit(1 if bad > 0 else 0)
