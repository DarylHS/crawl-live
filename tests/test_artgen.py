"""scripts/artgen.py (P9 part B): the offline import stage cleans messy pictures to the sprite rules, and the
generate stage refuses politely without a key or a reachable host. No test here touches the network."""
import importlib.util
import json
import os
import sys

import numpy as np
import pytest

PIL = pytest.importorskip("PIL.Image")
from PIL import Image, ImageFilter  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")


@pytest.fixture(scope="module")
def artgen():
    sys.path.insert(0, SCRIPTS)
    spec = importlib.util.spec_from_file_location("artgen", os.path.join(SCRIPTS, "artgen.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _sprite(w=30, h=40):
    """A little flag-shaped thing in three colours, as an RGBA image with a transparent background."""
    a = np.zeros((h, w, 4), dtype=np.uint8)
    a[:, :4] = (120, 80, 40, 255)
    a[2:h // 2, 4:] = (200, 40, 40, 255)
    a[h // 2:h // 2 + 6, 4:w // 2] = (240, 220, 60, 255)
    return Image.fromarray(a, "RGBA")


def _rules(arr, size=32):
    """The art bible's sprite rules on a cleaned size x size RGBA array."""
    assert arr.shape == (size, size, 4)
    assert set(np.unique(arr[..., 3])) <= {0, 255}, "binary alpha"
    ys, xs = np.where(arr[..., 3] > 0)
    assert xs.min() >= 1 and ys.min() >= 1 and xs.max() <= size - 2, "one pixel border"
    assert ys.max() == size - 2, "feet on the bottom row inside the border"
    assert abs((xs.min() + xs.max()) / 2 - (size - 1) / 2) <= 2, "centred"


def _run(artgen, tmp_path, files, *extra):
    src = tmp_path / "in"
    src.mkdir(exist_ok=True)
    for name, im in files.items():
        im.save(src / name)
    assets = tmp_path / "assets"
    rc = artgen.main(["import", "--src", str(src), "--set", "t", "--assets", str(assets), *extra])
    return rc, assets / "sets" / "t"


def test_messy_inputs_come_out_to_the_sprite_rules(artgen, tmp_path):
    spr = _sprite()
    big = spr.resize((spr.width * 12, spr.height * 12), Image.BICUBIC)
    white = Image.new("RGBA", (700, 700), (255, 255, 255, 255))
    white.alpha_composite(big, (310, 40))                                   # off-centre, high up, smooth edges, white background
    magenta = Image.new("RGBA", (300, 300), (255, 0, 255, 255))
    magenta.alpha_composite(spr.resize((90, 120), Image.NEAREST), (5, 160))   # colour key background
    soft = big.copy()
    soft.putalpha(soft.getchannel("A").filter(ImageFilter.GaussianBlur(4)))   # transparent but soft edged
    rc, out = _run(artgen, tmp_path, {
        "item__tonic.png": white.convert("RGB"), "item__cleaver.png": magenta.convert("RGB"),
        "item__sock.png": soft, "mug.png": spr}, "--palette", "keep")
    assert rc == 0
    manifest = json.loads((out / "manifest.json").read_text())
    assert set(manifest) == {"item:tonic", "item:cleaver", "item:sock", "item:mug"}
    for key, entry in manifest.items():
        assert entry["origin"] == "imported" and entry["source"]
        arr = np.array(Image.open(out / entry["file"]).convert("RGBA"))
        _rules(arr)
        assert (arr[..., 3] > 0).sum() > 60, key


def test_palette_snap_uses_only_the_shared_palette_and_keep_does_not(artgen, tmp_path):
    import art_pipeline as ap
    spr = _sprite().resize((200, 280), Image.BICUBIC)
    rc, out = _run(artgen, tmp_path, {"item__pan.png": spr}, "--palette", "snap", "--outline", "off")
    assert rc == 0
    arr = np.array(Image.open(out / "items" / "pan.png").convert("RGBA"))
    colours = {tuple(c[:3]) for c in arr.reshape(-1, 4) if c[3]}
    assert colours and colours <= set(ap.PALETTE)
    rc, out2 = _run(artgen, tmp_path, {"item__pan.png": spr}, "--palette", "keep", "--outline", "off")
    arr2 = np.array(Image.open(out2 / "items" / "pan.png").convert("RGBA"))
    assert {tuple(c[:3]) for c in arr2.reshape(-1, 4) if c[3]} - set(ap.PALETTE)      # blended colours survive in keep mode


def test_items_get_an_outline_and_creatures_do_not(artgen, tmp_path):
    spr = _sprite().resize((90, 120), Image.NEAREST)
    rc, out = _run(artgen, tmp_path, {"item__pan.png": spr, "mon__goblin.png": spr})
    assert rc == 0
    item = np.array(Image.open(out / "items" / "pan.png").convert("RGBA"))
    mon = np.array(Image.open(out / "monsters" / "goblin.png").convert("RGBA"))
    assert tuple(item[item[..., 3] > 0][0][:3]) == (14, 12, 18) or (item[..., :3][item[..., 3] > 0] == (14, 12, 18)).all(axis=1).any()
    assert not (mon[..., :3][mon[..., 3] > 0] == (14, 12, 18)).all(axis=1).any()


def test_specks_are_dropped_but_a_detached_part_stays(artgen, tmp_path):
    a = np.zeros((200, 200, 4), dtype=np.uint8)
    a[60:180, 60:140] = (200, 60, 60, 255)               # the body
    a[60:100, 150:170] = (200, 60, 60, 255)              # a detached handle (a fifth of the body)
    a[5:8, 5:8] = (255, 255, 0, 255)                     # a stray speck far away
    rc, out = _run(artgen, tmp_path, {"item__trophy.png": Image.fromarray(a, "RGBA")}, "--outline", "off")
    arr = np.array(Image.open(out / "items" / "trophy.png").convert("RGBA"))
    ys, xs = np.where(arr[..., 3] > 0)
    assert ys.min() >= 1 and ys.max() == 30
    assert xs.max() - xs.min() > 18                      # the handle is still there (body alone would be 2/3 as wide)
    assert (arr[..., 1] == 255).sum() == 0               # no speck colour


def test_a_picture_with_nothing_in_it_is_skipped_not_fatal(artgen, tmp_path, capsys):
    rc, out = _run(artgen, tmp_path, {"item__remote.png": Image.new("RGB", (64, 64), (255, 255, 255)),
                                      "item__mug.png": _sprite().convert("RGBA")})
    assert rc == 0
    assert set(json.loads((out / "manifest.json").read_text())) == {"item:mug"}
    assert "nothing left" in capsys.readouterr().err


def test_reimporting_merges_into_the_manifest_and_textures_are_resized(artgen, tmp_path):
    tex = Image.new("RGB", (512, 512), (110, 105, 100))
    rc, out = _run(artgen, tmp_path, {"item__mug.png": _sprite()})
    assert rc == 0
    src = tmp_path / "in2"
    src.mkdir()
    tex.save(src / "tex__1__floor.png")
    rc = artgen.main(["import", "--src", str(src), "--set", "t", "--assets", str(tmp_path / "assets"), "--keys", "tex:1:floor"])
    assert rc == 0
    manifest = json.loads((out / "manifest.json").read_text())
    assert "item:mug" in manifest and "tex:1:floor" in manifest
    t = Image.open(out / manifest["tex:1:floor"]["file"])
    assert t.size == (64, 64)


def test_file_names_map_to_keys(artgen):
    assert artgen.key_for_file("item__tonic.png", {}) == "item:tonic"
    assert artgen.key_for_file("tonic.png", {}) == "item:tonic"
    assert artgen.key_for_file("item__tonic_2.png", {}) == "item:tonic"
    assert artgen.key_for_file("whatever.png", {"whatever.png": "item:sock"}) == "item:sock"
    assert artgen.key_for_file("nothing_like_it.png", {}) is None


def test_the_catalogue_covers_every_item_and_box(artgen):
    items = json.load(open(os.path.join(ROOT, "godot", "data", "items.json")))["items"]
    boxes = json.load(open(os.path.join(ROOT, "godot", "data", "loot_boxes.json")))
    for k in items:
        assert "item:" + k in artgen.CATALOGUE, k
    for k in boxes:
        assert "box:" + k in artgen.CATALOGUE, k
    assert 20 <= len(artgen.CATALOGUE) <= 30


def test_generate_dry_run_needs_no_key_and_sends_nothing(artgen, monkeypatch, capsys):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.setattr(artgen.urllib.request, "urlopen", lambda *a, **k: pytest.fail("network used"))
    assert artgen.main(["generate", "--dry-run", "--keys", "item:tonic,item:pan"]) == 0
    out = capsys.readouterr().out
    assert "images/generations" in out and "item:tonic" in out and "nothing sent" in out


def test_generate_without_a_key_says_so_and_never_touches_the_network(artgen, monkeypatch, capsys):
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.setattr(artgen.urllib.request, "urlopen", lambda *a, **k: pytest.fail("network used"))
    assert artgen.main(["generate", "--keys", "item:tonic"]) == 2
    assert "OPENAI_API_KEY" in capsys.readouterr().err


def test_generate_with_a_blocked_host_names_the_setting_to_change_and_hides_the_key(artgen, monkeypatch, capsys):
    secret = "sk-test-secret-1234567890"
    monkeypatch.setenv("OPENAI_API_KEY", secret)

    def blocked(*a, **k):
        raise artgen.urllib.error.URLError("Tunnel connection failed: 403 Forbidden")
    monkeypatch.setattr(artgen.urllib.request, "urlopen", blocked)
    assert artgen.main(["generate", "--keys", "item:tonic"]) == 3
    err = capsys.readouterr().err
    assert "api.openai.com" in err and "network settings" in err and secret not in err


def test_the_key_is_scrubbed_from_api_errors(artgen):
    assert "sk-abc123" not in artgen.scrub('Incorrect API key provided: sk-abc123xyz. Check it.', "sk-abc123xyz")
    assert "sk-" not in artgen.scrub("key sk-other-thing-9 was bad", None)


def test_generate_makes_the_requests_it_says_it_does(artgen, monkeypatch, tmp_path):
    """With a fake API: one request per key, the key only in the Authorization header, results saved as <key>.png."""
    secret = "sk-test-secret-1234567890"
    monkeypatch.setenv("OPENAI_API_KEY", secret)
    calls = []

    class Resp:
        def __init__(self, data):
            self._d = data

        def read(self, *a):
            return self._d

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    import base64
    import io
    png = io.BytesIO()
    _sprite().save(png, "PNG")

    def fake(req, timeout=0):
        if isinstance(req, str):
            return Resp(png.getvalue())
        if req.full_url.endswith("/models"):
            raise artgen.urllib.error.HTTPError(req.full_url, 401, "no key", {}, None)
        calls.append((req.full_url, req.get_header("Authorization"), req.data))
        return Resp(json.dumps({"data": [{"b64_json": base64.b64encode(png.getvalue()).decode()}]}).encode())
    monkeypatch.setattr(artgen.urllib.request, "urlopen", fake)
    monkeypatch.setattr(artgen.time, "sleep", lambda s: None)
    rc = artgen.main(["generate", "--keys", "item:tonic,box:gold", "--out", str(tmp_path), "--delay", "0"])
    assert rc == 0
    assert [c[0] for c in calls] == [artgen.API_BASE + "/images/generations"] * 2
    assert all(c[1] == "Bearer " + secret for c in calls)
    assert all(secret.encode() not in c[2] for c in calls)
    assert (tmp_path / "item__tonic.png").exists() and (tmp_path / "box__gold.png").exists()
    body = json.loads(calls[0][2])
    assert body["model"] == "gpt-image-1" and "tonic" in body["prompt"].lower() or "potion" in body["prompt"].lower()
