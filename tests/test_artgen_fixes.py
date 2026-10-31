"""artgen.py verifier fixes: empty results are rejected, duplicate keys warn, prompts only say what applies."""
import json

import pytest

pytest.importorskip("PIL.Image")
from PIL import Image  # noqa: E402

from test_artgen import _run, _sprite, artgen  # noqa: E402,F401


def test_a_fully_transparent_picture_is_rejected(artgen, tmp_path, capsys):
    clear = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    faint = Image.new("RGBA", (64, 64), (200, 40, 40, 10))               # alpha so low the threshold clears it
    rc, out = _run(artgen, tmp_path, {"item__remote.png": clear, "item__mug.png": faint, "item__sock.png": _sprite()})
    assert rc == 0
    assert set(json.loads((out / "manifest.json").read_text())) == {"item:sock"}
    assert "item__remote.png" in capsys.readouterr().err


def test_two_files_for_one_key_warn_and_keep_the_first(artgen, tmp_path, capsys):
    rc, out = _run(artgen, tmp_path, {"item__mug.png": _sprite(), "mug.png": _sprite(20, 30)})
    assert rc == 0
    manifest = json.loads((out / "manifest.json").read_text())
    assert manifest["item:mug"]["source"] == ["item__mug.png"]
    assert "both map to item:mug" in capsys.readouterr().err


def test_prompts_only_mention_references_and_backgrounds_that_apply(artgen):
    plain = artgen.prompt_for("item:tonic")
    assert "reference" not in plain and "transparent background" in plain and "white background" not in plain
    assert "reference pictures" in artgen.prompt_for("item:tonic", refs=True)
    opaque = artgen.prompt_for("item:tonic", transparent=False, style_text="warm browns and teal.")
    assert "plain white background" in opaque and "transparent" not in opaque and "warm browns and teal" in opaque
