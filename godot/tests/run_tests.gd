extends SceneTree
## Stopgap test runner (port plan 7.2). Use scripts/gd_test.sh, which imports the project first
## (class_name needs the global class cache), regenerates the Python reference files and checks the log.
##
##   godot --headless --path godot -s res://tests/run_tests.gd -- [--dir=res://tests] [--file=substr]
##                                                               [--test=substr] [--verbose]
##
## Finds test_*.gd under --dir (skipping support/ and fixtures/), sorted by path. Each file must
## extend TestCase. Test methods are those named test_*, in declaration order; before_all /
## before_each / after_each / after_all run when defined. A parametrised test has one argument
## with a default (`p = use_parameters([...])`) and runs once per entry as test_x[i].
## A test that makes no assertion is "risky" and fails the run. Prints `RESULT: ...` and a
## sentinel `TESTS PASSED` / `TESTS FAILED`; exits 0 / 1.

var _passed := 0
var _failed := 0
var _risky := 0
var _pending := 0
var _verbose := false
var _failure_lines: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	var dir := "res://tests"
	var file_filter := ""
	var test_filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.trim_prefix("--dir=")
		elif a.begins_with("--file="):
			file_filter = a.trim_prefix("--file=")
		elif a.begins_with("--test="):
			test_filter = a.trim_prefix("--test=")
		elif a == "--verbose":
			_verbose = true
	var files := _discover(dir)
	var started := Time.get_ticks_msec()
	var ran_files := 0
	for path in files:
		if file_filter != "" and not path.contains(file_filter):
			continue
		ran_files += 1
		_run_file(path, test_filter)
	for line in _failure_lines:
		print(line)
	var secs := (Time.get_ticks_msec() - started) / 1000.0
	print("files: %d, time: %.1fs" % [ran_files, secs])
	if ran_files == 0:
		_failed += 1
		print("FAIL: no test files found in %s matching '%s'" % [dir, file_filter])
	print("RESULT: %d passed, %d failed, %d risky, %d pending" % [_passed, _failed, _risky, _pending])
	var ok := _failed == 0 and _risky == 0
	print("TESTS PASSED" if ok else "TESTS FAILED")
	quit(0 if ok else 1)


func _discover(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for sub in DirAccess.get_directories_at(dir):
		if sub != "support" and sub != "fixtures":
			out.append_array(_discover(dir + "/" + sub))
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir + "/" + f)
	out.sort()
	return out


func _record_failure(path: String, test_name: String, text: String) -> void:
	_failure_lines.append("FAIL %s::%s\n    %s" % [path.trim_prefix("res://"), test_name, text])


func _run_file(path: String, test_filter: String) -> void:
	var script = load(path)
	if script == null or not (script is GDScript) or not script.can_instantiate():
		_failed += 1
		_record_failure(path, "<file>", "script failed to load or parse")
		return
	var t = script.new()
	if not (t is TestCase):
		_failed += 1
		_record_failure(path, "<file>", "does not extend TestCase")
		return
	var methods: Array = []
	for m in script.get_script_method_list():
		if String(m["name"]).begins_with("test_"):
			methods.append(m)
	if t.has_method("before_all"):
		t.before_all()
	for m in methods:
		var name: String = m["name"]
		if test_filter != "" and not name.contains(test_filter):
			continue
		var parametrised: bool = m["args"].size() == 1 and m["default_args"].size() == 1
		if parametrised:
			t._param_index = 0
			t._param_count = 0
			while true:
				_run_test(t, path, name, "%s[%d]" % [name, t._param_index])
				t._param_index += 1
				if t._param_index >= t._param_count:
					break
		else:
			_run_test(t, path, name, name)
	if t.has_method("after_all"):
		t.after_all()


# GDScript can't catch runtime errors, so a test that errors after its first assert still
# counts as passed here. Always run through scripts/gd_test.sh, which fails the run on any
# SCRIPT ERROR in the output.
func _run_test(t: TestCase, path: String, method: String, label: String) -> void:
	t._failures = PackedStringArray()
	t._pending = PackedStringArray()
	t._asserts = 0
	if t.has_method("before_each"):
		t.before_each()
	t.call(method)
	if t.has_method("after_each"):
		t.after_each()
	if not t._failures.is_empty():
		_failed += 1
		_record_failure(path, label, "\n    ".join(t._failures))
		return
	if t._asserts == 0 and t._pending.is_empty():
		_risky += 1
		_record_failure(path, label, "risky: no assertions ran (a runtime error may have returned null)")
		return
	if not t._pending.is_empty():
		_pending += 1
		if _verbose:
			print("PENDING %s::%s %s" % [path.trim_prefix("res://"), label, t._pending[0]])
		return
	_passed += 1
	if _verbose:
		print("ok   %s::%s" % [path.trim_prefix("res://"), label])
