extends TestCase
## Chaos-trace parity with Python (S8 close-out): scripts/chaos_trace.py (Python, reference traces in
## CHAOS_TRACES, made by scripts/gd_test.sh for seeds 0-9 at 600 steps) against tools/chaos.gd, which
## drives World through every player action (skills, bombs, crafting, shop, boxes, rerolls, trade-ups, pet
## revival, rest, stairs, contracts). tools/chaos.gd is a SceneTree script, so it runs in a child Godot
## process and scripts/chaos_diff.py (python3) does the comparison. Both sides run with the P1 stand-ins
## muted (the default); T1/T2/T3 must switch muting off in chaos_trace.py, chaos.gd and chaos_diff.py
## (--no-mute-standins) and fix this test's call accordingly.
## A missing CHAOS_TRACES directory fails the test (run through scripts/gd_test.sh).

const SEEDS := "0-9"
const STEPS := 600


func test_chaos_traces_match_python() -> void:
	var py_dir := OS.get_environment("CHAOS_TRACES")
	if py_dir == "" or not DirAccess.dir_exists_absolute(py_dir):
		fail_test("CHAOS_TRACES is not set or missing (run through scripts/gd_test.sh)")
		return
	var root := OS.get_environment("CRAWL_ROOT")
	if root == "":
		fail_test("CRAWL_ROOT is not set (run through scripts/gd_test.sh)")
		return
	var gd_dir := ProjectSettings.globalize_path(TestHelpers.tmp_dir("chaos"))
	var log: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", root + "/godot",
			"-s", "res://tools/chaos.gd", "--", "--seeds", SEEDS, "--steps", str(STEPS), "--out-dir", gd_dir], log, true)
	assert_eq(code, 0, "chaos.gd exit code: %s" % "".join(log).right(400))
	log = []
	code = OS.execute("python3", [root + "/scripts/chaos_diff.py", "--dirs", py_dir, gd_dir, "--seeds", SEEDS], log, true)
	assert_eq(code, 0, "chaos_diff: %s" % "".join(log).left(1500))
	assert_true("10/10 chaos traces identical" in "".join(log))
