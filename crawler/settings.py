"""Player preferences that outlive a run, such as the camera view (headless).

Kept apart from the run save so the save format doesn't change. A missing or
broken file, or a value we don't recognise, quietly falls back to the default.
"""
import json
from pathlib import Path

from .save import SAVE_DIR

SETTINGS_FILE = SAVE_DIR / "settings.json"
VIEWS = ("fp", "top")               # first-person, top-down map
DEFAULTS = {"view": "fp"}


def load(path=SETTINGS_FILE):
    """The saved settings over the defaults. path=None means defaults only."""
    out = dict(DEFAULTS)
    if path is None:
        return out
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return out
    if isinstance(data, dict) and data.get("view") in VIEWS:
        out["view"] = data["view"]
    return out


def save(settings, path=SETTINGS_FILE):
    """Write settings atomically. path=None turns saving off (tests)."""
    if path is None:
        return
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(settings))
    tmp.replace(path)
