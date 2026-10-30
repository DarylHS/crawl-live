class_name UserSettings
extends RefCounted
## Player preferences that outlive a run, such as the camera view (crawler/settings.py).
##
## Kept apart from the run save so the save format doesn't change. A missing or broken file, or a
## value we don't recognise, quietly falls back to the default. A path of "" turns persistence off
## (Python's path=None, used by tests): load returns the defaults and save writes nothing.

## Where the game keeps the file unless told otherwise (port plan 10.4; a --save-dir option can pass
## settings_path(dir) instead).
const DEFAULT_PATH: String = "user://settings.json"
const FILE_NAME: String = "settings.json"
## first-person, top-down map
const VIEWS: Array[String] = ["fp", "top"]
## Graphics render scale (owner addition in P5; the Python version ignores the key): the 3D
## resolution, Retro 320 x 200 with hard pixels, Sharp 640 x 400, Full at the size of the map area.
const RENDER_SCALES: Array[String] = ["retro", "sharp", "full"]
## Effects level (owner addition in P8; the Python version ignores the key): juice such as hit flashes,
## floating numbers, particles and screen shake. "reduced" drops the shake and most particles.
const EFFECTS_MODES: Array[String] = ["on", "reduced", "off"]
## Master volume in percent and mute (P8; also ignored by Python).
const VOLUME_MAX: int = 100
const DEFAULTS: Dictionary = {"view": "fp", "render_scale": "retro", "effects": "on", "volume": 70,
		"muted": false}


## The settings file inside `dir`.
static func settings_path(dir: String) -> String:
	return dir.path_join(FILE_NAME)


## The saved settings over the defaults. path "" means defaults only.
static func load(path: String = DEFAULT_PATH) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	if path == "":
		return out
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return out
	var text := fa.get_as_text()
	fa.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return out
	var data: Variant = parser.data
	if data is Dictionary and data.get("view") is String and VIEWS.has(data["view"]):
		out["view"] = data["view"]
	if data is Dictionary and data.get("render_scale") is String and RENDER_SCALES.has(data["render_scale"]):
		out["render_scale"] = data["render_scale"]
	if data is Dictionary and data.get("effects") is String and EFFECTS_MODES.has(data["effects"]):
		out["effects"] = data["effects"]
	if data is Dictionary and data.get("volume") is float and data["volume"] >= 0.0 and data["volume"] <= VOLUME_MAX:
		out["volume"] = int(data["volume"])
	if data is Dictionary and data.get("muted") is bool:
		out["muted"] = data["muted"]
	return out


## Write settings atomically (path.tmp, then rename). path "" turns saving off. Returns false when
## the file could not be written.
static func save(settings: Dictionary, path: String = DEFAULT_PATH) -> bool:
	if path == "":
		return true
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path.get_basename() + ".tmp"
	var fa := FileAccess.open(tmp, FileAccess.WRITE)
	if fa == null:
		push_error("UserSettings.save: cannot write %s (error %d)" % [tmp, FileAccess.get_open_error()])
		return false
	fa.store_string(PyJson.dumps(settings))
	fa.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_error("UserSettings.save: cannot rename %s to %s (error %d)" % [tmp, path, err])
		return false
	return true
