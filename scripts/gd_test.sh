#!/usr/bin/env bash
# Run every Godot headless test (port plan 8.3):
#   scripts/gd_test.sh                       # all
#   scripts/gd_test.sh --file=test_content   # one file (any runner argument is passed through)
#
# 1. imports the project (class_name needs .godot/global_script_class_cache.cfg; a headless
#    parse error can still exit 0, so step 4 also greps the log),
# 2. regenerates the Python references into a temp dir (not committed: the RNG one is 12.7 MB),
# 3. runs tests/run_tests.gd,
# 4. passes only if the exit status is 0, the log has the TESTS PASSED line and no SCRIPT ERROR /
#    parse error / failed-to-load line appears.
# Environment: GODOT (binary, default godot), GD_TEST_LOG (default /tmp/gd_test.log).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
LOG="${GD_TEST_LOG:-/tmp/gd_test.log}"
REFDIR="$(mktemp -d)"
trap 'rm -rf "$REFDIR"' EXIT

"$GODOT" --headless --path "$ROOT/godot" --import >/dev/null 2>&1

python3 "$ROOT/scripts/py_random_reference.py" "$REFDIR/py_random_ref.json" || { echo "FAIL: py_random_reference.py"; exit 1; }
python3 "$ROOT/scripts/content_reference.py" "$REFDIR/content_ref.json" || { echo "FAIL: content_reference.py"; exit 1; }
export PY_RANDOM_REF="$REFDIR/py_random_ref.json" CONTENT_REF="$REFDIR/content_ref.json"

"$GODOT" --headless --path "$ROOT/godot" -s res://tests/run_tests.gd -- "$@" 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}

fail=0
[ "$status" -eq 0 ] || { echo "gd_test: godot exited with $status"; fail=1; }
grep -q '^TESTS PASSED$' "$LOG" || { echo "gd_test: no 'TESTS PASSED' line in the log"; fail=1; }
if grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script|Failed to compile' "$LOG"; then
	echo "gd_test: script or parse errors in the log:"
	grep -En 'SCRIPT ERROR|Parse Error|Failed to load script|Failed to compile' "$LOG" | head -20
	fail=1
fi
[ "$fail" -eq 0 ] && echo "gd_test: OK" || echo "gd_test: FAILED"
exit "$fail"
