class_name TestHelpers
extends RefCounted
## Helpers shared by test files (port plan 7.2). World factories are added with the World port.

static var _patches: Array = []   # [[target, key, had_key, old_value, is_object], ...]


## Empty scratch directory user://test_tmp/<name>/ (pytest's tmp_path).
static func tmp_dir(dir_name: String) -> String:
	var path := "user://test_tmp/%s/" % dir_name
	if DirAccess.dir_exists_absolute(path):
		for f in DirAccess.get_files_at(path):
			DirAccess.remove_absolute(path + f)
	else:
		DirAccess.make_dir_recursive_absolute(path)
	return path


## monkeypatch.setattr analogue for `static var` config: patch_static(GameConfig, "MAP_W", 40).
static func patch_static(script: Object, prop: String, value: Variant) -> void:
	_patches.append([script, prop, true, script.get(prop), true])
	script.set(prop, value)


## monkeypatch.setitem analogue for content Dictionaries: patch_item(Content.monster("goblin"), "init", 50).
static func patch_item(dict: Dictionary, key: Variant, value: Variant) -> void:
	_patches.append([dict, key, dict.has(key), dict.get(key), false])
	dict[key] = value


## Undo every patch, newest first. Call it from each test file's after_each().
static func restore_patches() -> void:
	_patches.reverse()
	for p in _patches:
		if p[4]:
			p[0].set(p[1], p[3])
		elif p[2]:
			p[0][p[1]] = p[3]
		else:
			p[0].erase(p[1])
	_patches = []


## Value of an environment variable, or "" (tests use it for generated reference files).
static func env(var_name: String) -> String:
	return OS.get_environment(var_name)
