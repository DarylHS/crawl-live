#!/usr/bin/env python3
"""Independent leaf dump of the Python content, for godot/tests/test_content.gd.

Usage: content_reference.py out.json

Reads the Python objects through export_content.tables() (so the table layout is shared) but
walks them with its own flattener, not the exporter's JSON writer: the test then compares every
leaf (type, exact value, key order) with what Content loads from godot/data/*.json.

Encoding of a leaf (JSON numbers are doubles in Godot, so nothing numeric is a JSON number):
  int "i:<dec>"   float "f:<16 hex digits of the IEEE-754 bits>"   str "s:<text>"
  bool "b:1"/"b:0"   None "n:"   empty list "e:[]"   empty dict "e:{}"
Each table is a list of [json pointer, encoded leaf] in document order.
"""
import json
import struct
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_content as E  # noqa: E402


def enc(v):
    if v is None:
        return "n:"
    if isinstance(v, bool):
        return "b:1" if v else "b:0"
    if isinstance(v, int):
        return f"i:{v}"
    if isinstance(v, float):
        return "f:%016x" % struct.unpack(">Q", struct.pack(">d", v))[0]
    return "s:" + v


def flat(node, path, out):
    if isinstance(node, dict):
        if not node:
            out.append([path, "e:{}"])
        for k, v in node.items():
            flat(v, f"{path}/{str(k).replace('~', '~0').replace('/', '~1')}", out)
    elif isinstance(node, (list, tuple)):
        if not node:
            out.append([path, "e:[]"])
        for i, v in enumerate(node):
            flat(v, f"{path}/{i}", out)
    elif isinstance(node, (set, frozenset)):
        flat(sorted(node), path, out)
    else:
        out.append([path, enc(node)])


def main():
    result = {}
    for name, (data, _src) in E.tables().items():
        out = []
        flat(data, "", out)
        result[name.removesuffix(".json")] = out
    counts = {
        "monsters": len(E.entities.MONSTERS), "pets": len(E.entities.PETS), "races": len(E.classes.RACES),
        "classes": len(E.classes.CLASSES), "achievements": len(E.A.ACHIEVEMENTS),
        "headliners": len(E.bosses.BOSSES), "practice_skills": len(E.practice.SKILLS),
        "lines": len(E.lines.LINES), "backstories": len(E.character.BACKSTORIES),
        "items": len(E.items.ITEMS), "floor_loot": len(E.items.FLOOR_LOOT),
    }
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump({"counts": counts, "tables": result}, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main()
