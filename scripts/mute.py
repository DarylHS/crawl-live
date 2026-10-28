"""Shared --mute parsing for py_trace.py, chaos_trace.py and chaos_diff.py.

A muted subsystem is a real Python system that is silenced to isolate it while debugging. Since T3 every
system is real on both sides and nothing is muted by default. Achievements (T1) and the Showrunner (T2) are real on both sides, so
Achievements cannot be muted at all: only the names in SUBSYSTEMS are accepted, anything else is an error.
"""
SUBSYSTEMS = ("showrunner", "funfacts")
DEFAULT = ""                  # nothing is muted by default


def parse_mute(text):
    """'funfacts' -> {'funfacts'}; '' and 'none' -> empty; 'all' -> every name in SUBSYSTEMS."""
    if text in ("", "none"):
        return set()
    names = set(SUBSYSTEMS) if text == "all" else set(text.split(","))
    bad = names - set(SUBSYSTEMS)
    if bad:
        raise SystemExit(f"unknown subsystem(s) to mute: {sorted(bad)} (choose from {', '.join(SUBSYSTEMS)}, all, none)")
    return names
