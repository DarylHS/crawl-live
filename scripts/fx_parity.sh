#!/usr/bin/env bash
# P8 proof that the effects never touch the rules: the Godot trace and chaos drivers run with an FxDirector
# attached to every World (CRAWL_FX=1: tools/trace_run.gd and tools/chaos.gd call FxDirector.attach_headless),
# so every event is planned and applied (sounds, flashes, numbers, shake, bursts) while the run goes on, and the
# traces are compared with Python's, line for line, exactly as scripts/parity_all.sh does without effects.
#
#   scripts/fx_parity.sh                          # chaos 0-23 (1500 steps), hunter 0-7 and bot 0-7 (3000 steps)
#   FX_CHAOS=0-59 FX_HUNTER=0-19 FX_BOT=0-19 scripts/fx_parity.sh    # more seeds
#   PARITY_JOBS=8 scripts/fx_parity.sh
#
# Exit 0 only when every set is identical.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
N="${PARITY_JOBS:-$(nproc)}"
CHAOS="${FX_CHAOS:-0-23}"
HUNTER="${FX_HUNTER:-0-7}"
BOT="${FX_BOT:-0-7}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/fx_parity.XXXXXX")"
[ "${PARITY_KEEP:-}" = "1" ] && echo "work directory: $WORK" || trap 'rm -rf "$WORK"' EXIT
cd "$ROOT" || exit 1
"$GODOT" --headless --path "$ROOT/godot" --import >/dev/null 2>&1

# chunks A-B SIZE: "a-b" ranges of at most SIZE seeds
chunks() { local a=${1%-*} b=${1#*-} s=$2; while [ "$a" -le "$b" ]; do local e=$((a + s - 1)); [ "$e" -gt "$b" ] && e=$b; echo "$a-$e"; a=$((e + 1)); done; }

JOBS="$WORK/jobs.txt"
: > "$JOBS"
mkdir -p "$WORK/py_chaos" "$WORK/gd_chaos" "$WORK/py_hunter" "$WORK/gd_hunter" "$WORK/py_bot" "$WORK/gd_bot"
for c in $(chunks "$CHAOS" 6); do
	echo "python3 $ROOT/scripts/chaos_trace.py --seeds $c --steps 1500 --out-dir $WORK/py_chaos" >> "$JOBS"
	echo "CRAWL_FX=1 $GODOT --headless --path $ROOT/godot -s res://tools/chaos.gd -- --seeds $c --steps 1500 --out-dir $WORK/gd_chaos >/dev/null 2>&1" >> "$JOBS"
done
for c in $(chunks "$HUNTER" 4); do
	echo "python3 $ROOT/scripts/py_trace.py --seeds $c --policy hunter --steps 3000 --out-dir $WORK/py_hunter >/dev/null" >> "$JOBS"
	echo "CRAWL_FX=1 $GODOT --headless --path $ROOT/godot -s res://tools/trace.gd -- --seeds $c --policy hunter --steps 3000 --out-dir $WORK/gd_hunter >/dev/null 2>&1" >> "$JOBS"
done
for c in $(chunks "$BOT" 2); do
	echo "python3 $ROOT/scripts/py_trace.py --seeds $c --policy bot --steps 3000 --out-dir $WORK/py_bot >/dev/null" >> "$JOBS"
	echo "CRAWL_FX=1 $GODOT --headless --path $ROOT/godot -s res://tools/trace.gd -- --seeds $c --policy bot --steps 3000 --out-dir $WORK/gd_bot >/dev/null 2>&1" >> "$JOBS"
done
echo "fx_parity: generating traces ($(wc -l < "$JOBS") jobs on $N workers, effects attached on the Godot side)..."
xargs -d '\n' -P "$N" -I CMD bash -c CMD < "$JOBS"

fail=0
out="$(python3 "$ROOT/scripts/chaos_diff.py" --dirs "$WORK/py_chaos" "$WORK/gd_chaos" --seeds "$CHAOS" 2>&1)"
rc=$?
echo "chaos $CHAOS: $(echo "$out" | tail -1)"
[ "$rc" -eq 0 ] || { echo "$out" | grep -v ": SAME" | head -20; fail=1; }
for set in hunter bot; do
	seeds="$HUNTER"
	[ "$set" = "bot" ] && seeds="$BOT"
	out="$(python3 "$ROOT/scripts/parity_diff.py" --dirs "$WORK/py_$set" "$WORK/gd_$set" --seeds "$seeds" --scope full 2>&1)"
	rc=$?
	echo "$set $seeds: $(echo "$out" | tail -1)"
	[ "$rc" -eq 0 ] || { echo "$out" | grep -v "PARITY OK" | head -20; fail=1; }
done
echo "fx_parity: $([ "$fail" -eq 0 ] && echo 'ALL IDENTICAL with effects attached' || echo 'MISMATCH')"
exit "$fail"
