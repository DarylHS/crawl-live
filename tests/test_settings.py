"""Settings file: the view choice round-trips, and anything odd falls back to first-person."""
from crawler import settings


def test_view_round_trips(tmp_path):
    path = tmp_path / "settings.json"
    settings.save({"view": "top"}, path)
    assert settings.load(path) == {"view": "top"}
    settings.save({"view": "fp"}, path)
    assert settings.load(path)["view"] == "fp"


def test_missing_or_corrupt_file_falls_back_to_fp(tmp_path):
    assert settings.load(tmp_path / "nope.json")["view"] == "fp"
    bad = tmp_path / "bad.json"
    for text in ("{not json", "", "[1, 2]", "null"):
        bad.write_text(text)
        assert settings.load(bad)["view"] == "fp"


def test_unknown_view_falls_back_to_fp(tmp_path):
    path = tmp_path / "settings.json"
    for value in ("sideways", 3, None):
        settings.save({"view": value}, path)
        assert settings.load(path)["view"] == "fp"


def test_none_path_disables_persistence():
    assert settings.load(None) == settings.DEFAULTS
    settings.save({"view": "top"}, None)                  # no error, nothing written
    assert settings.load(None)["view"] == "fp"


def test_godot_front_end_keys_are_ignored(tmp_path):
    """The Godot port adds render_scale, effects, volume and muted to the same file (P5, P8): Python skips them."""
    path = tmp_path / "settings.json"
    path.write_text(
        '{"view": "top", "render_scale": "sharp", "effects": "reduced", "volume": 40, "muted": true}')
    assert settings.load(path) == {"view": "top"}
