#!/usr/bin/env python3
"""Crawl Live! art trial plumbing: generate pictures with the OpenAI Images API, then clean ANY pictures
(generated or hand-made) into an art set the game can switch to.

Two stages, one script (needs Pillow and numpy: `pip install pillow numpy`).

  1. generate  (needs the network; NOT run by the tests or by the build)
       OPENAI_API_KEY=sk-... python3 scripts/artgen.py generate --moodboard art/moodboard --out /tmp/ai_raw
       python3 scripts/artgen.py generate --dry-run ...        # prints the requests, calls nothing, needs no key

     * The key is read ONLY from the environment variable OPENAI_API_KEY. It is never written to a file, never
       printed and never put on the command line (errors from the API are scrubbed of it). The script exits with
       a plain message if the variable is missing.
     * The environment must be allowed to reach https://api.openai.com : the user has to add `api.openai.com`
       to the allowed hosts in the environment's network settings. The script checks the host first and exits
       with a clear message if it is blocked or unreachable.
     * `--moodboard DIR` holds the style reference pictures (PNG or JPG, up to 8 are sent along with each prompt as
       reference images through the /v1/images/edits endpoint; with no pictures it uses /v1/images/generations).
     * `--keys item:tonic,item:pan` picks keys (default: every item in the catalogue, `--set-name all` for the
       furniture, stairs and loot boxes too; `artgen.py list` prints the catalogue and the prompts). Each result is
       saved as <out>/<key with ':' as '__'>.png (a 1024 px picture; the model is asked for a transparent
       background, but the importer does not rely on that).
     * Costs real money per picture; `--n` pictures per key, `--delay` seconds between calls.

  2. import  (offline; this is what the tests exercise)
       python3 scripts/artgen.py import --src /tmp/ai_raw --set ai_trial [--palette snap|keep] [--sheet sheet.png]

     Takes any PNG/JPG named after an art key (`item__tonic.png`, or just `tonic.png` when the name is unique
     in the catalogue; `--map map.json` maps file names to keys for anything else) and cleans it to the sprite
     rules of docs/art-bible.md section 3: background removed to binary alpha (a flat or white/magenta background
     is flood-filled away from the edges), stray specks dropped, trimmed, shrunk to fit 32 x 32 (64 x 64 for
     textures and `--size 64`) with whole-pixel box averaging, feet on the bottom row, a one pixel transparent
     border, binary alpha, and either snapped to the shared palette (`--palette snap`, the default) or left in
     its own colours (`--palette keep`). Items, furniture and loot boxes get a one pixel near-black outline
     (`--outline auto|on|off`; creatures do not, the game draws theirs). Textures (keys starting `tex:` or
     `tile:`) are just resized to 64 x 64 / 32 x 32.
     The results go to godot/assets/sets/<set>/ with a manifest.json (key -> file, origin, source file, note), merged
     with what the set already holds, and an optional contact sheet (before and after side by side).

  Switching art sets in the game (no code changes): press F5 (cycles default, every folder under
  godot/assets/sets/, placeholder), or start with `godot --path godot -- --art-set ai_trial`, or set the
  environment variable CRAWL_ART_SET=ai_trial. A set only needs the keys it replaces; the default set fills
  the rest, and the code-drawn placeholders fill anything no set has.

  `artgen.py list` prints the catalogue; `artgen.py sheet --set ai_trial --out sheet.png` makes a contact sheet.
"""
from __future__ import annotations

import argparse
import base64
import io
import json
import mimetypes
import os
import socket
import sys
import time
import urllib.error
import urllib.request
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

API_HOST = "api.openai.com"
API_BASE = "https://api.openai.com/v1"
KEY_VAR = "OPENAI_API_KEY"
DEFAULT_MODEL = "gpt-image-1"
ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets")

STYLE = ("A single game sprite in pixel-art style, matching the style reference pictures: chunky readable shapes, a limited "
         "palette of about a dozen colours, hard pixel edges with no anti-aliasing or blur, a thin dark outline, lit from "
         "above. Front or three-quarter view, centred, the whole object visible and filling most of the picture, on a "
         "plain white background with no ground shadow, no text and no border. ")

# --- The catalogue: art-bible keys and what to ask for. Comedy lives in props (art bible section 1). ---------
ITEMS = {
    "item:pan": "a battered black frying pan with a long handle, held ready like a weapon, a sponsor sticker on the base",
    "item:cleaver": "a heavy kitchen cleaver with a worn wooden handle and a chipped broad blade",
    "item:katana": "a katana with a bright blue-steel blade and a cheap gold price tag tied to the hilt",
    "item:extinguisher": "a red fire extinguisher with a white label and a black hose, dented",
    "item:sledge": "a sledgehammer with a splintered wooden handle and a chunky iron head",
    "item:jersey": "a padded gym jersey, light blue with white stripes and a number on the chest, shown flat like an armour icon",
    "item:vest": "a blue riot vest with straps and buckles, shown flat like an armour icon",
    "item:plate": "a set of shiny silver stagehand plate armour, chest piece with shoulder guards, shown flat like an armour icon",
    "item:tonic": "a small round potion bottle with a cork, pink-red liquid, a white sponsor label",
    "item:brew": "a squat potion bottle with a cork, deep magenta-red murky liquid, a gold label",
    "item:elixir": "a tall potion bottle with a cork, glowing bright pink-red liquid with a few sparkles, a gold star label",
    "item:popper": "a party popper cone, orange with a gold stripe, confetti bursting from the wide end",
    "item:fireworks": "a firework rocket on a wooden stick, orange and white paper body with a red cone tip and a lit fuse",
    "item:sock": "a single white tube sock with red stripes at the top and a blue heel, slightly grubby",
    "item:trophy": "a small gold trophy cup on a brown base with a gold plate, one handle bent",
    "item:remote": "a grey TV remote control with a grid of coloured buttons and a red power button",
    "item:mug": "a white ceramic mug of tea with blue stripe and steam rising",
}
BOXES = {
    "box:bronze": "a loot box: a bronze-coloured gift box with a red ribbon and a bow on the lid",
    "box:silver": "a loot box: a silver-coloured gift box with a red ribbon and a bow on the lid",
    "box:gold": "a loot box: a shiny gold gift box with a red ribbon and a bow on the lid",
    "box:platinum": "a loot box: a pale cyan platinum gift box with a red ribbon and a bow on the lid",
    "box:legendary": "a loot box: a magenta gift box with a red ribbon, a bow on the lid and glowing edges",
}
FURNITURE = {
    "furn:bed": "a small camp bed seen from the side with a blue sponsor blanket with gold logos and a white pillow",
    "furn:bench": "a wooden workbench with a bench vice, a spanner and a little pile of screws",
    "furn:counter": "a shop counter in purple with a gold trim, a green cash till and a hand-written price board",
    "fx:stairs_open": "a golden downward arrow pointing down, glowing, flat game icon",
    "fx:stairs_locked": "a red downward arrow with a grey padlock in the middle, flat game icon",
}
CATALOGUE = {**ITEMS, **BOXES, **FURNITURE}
SETS = {"items": ITEMS, "boxes": BOXES, "furniture": FURNITURE, "all": CATALOGUE}

OUTLINE_KINDS = ("item", "furn", "box", "fx")


def slug(key: str) -> str:
    return key.replace(":", "__")


def unslug(name: str) -> str:
    return name.replace("__", ":")


def prompt_for(key: str) -> str:
    return STYLE + "Subject: " + CATALOGUE[key] + "."


# --- Stage 1: generate -------------------------------------------------------------------------

class GenError(SystemExit):
    pass


def scrub(text: str, key: str | None) -> str:
    """Remove the API key (and anything shaped like one) from text before it is shown."""
    if key:
        text = text.replace(key, "<key>")
    out, i = [], 0
    while i < len(text):
        j = text.find("sk-", i)
        if j < 0:
            out.append(text[i:])
            break
        out.append(text[i:j])
        k = j + 3
        while k < len(text) and (text[k].isalnum() or text[k] in "-_"):
            k += 1
        out.append("<key>")
        i = k
    return "".join(out)


def check_host(timeout: float = 8.0) -> None:
    """Exit with a clear message unless https://api.openai.com answers (any HTTP status counts: 401 is fine)."""
    req = urllib.request.Request(API_BASE + "/models", method="GET")     # no Authorization header: only a reachability probe
    try:
        urllib.request.urlopen(req, timeout=timeout)
        return
    except urllib.error.HTTPError as e:
        if e.code == 401:                                                # no key sent: 401 means the API itself answered
            return
        body = ""
        try:
            body = e.read(300).decode("utf-8", "replace")
        except Exception:
            pass
        raise GenError(blocked_message("HTTP %d from the network path (%s)" % (e.code, body.strip()[:120] or "no body")))
    except (urllib.error.URLError, socket.timeout, OSError) as e:
        raise GenError(blocked_message(str(getattr(e, "reason", e))))


def blocked_message(why: str) -> str:
    return ("artgen: cannot reach %s (%s).\n"
            "The environment's network settings must allow the host `%s` (add it to the allowed domains), then run again.\n"
            "Stage 2 (`artgen.py import`) works offline and does not need it." % (API_HOST, why, API_HOST))


def multipart(fields: dict[str, str], files: list[tuple[str, str, bytes, str]]) -> tuple[bytes, str]:
    boundary = "----artgen" + uuid.uuid4().hex
    buf = io.BytesIO()
    for k, v in fields.items():
        buf.write(("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (boundary, k, v)).encode())
    for name, fname, data, ctype in files:
        buf.write(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n"
                   % (boundary, name, fname, ctype)).encode())
        buf.write(data)
        buf.write(b"\r\n")
    buf.write(("--%s--\r\n" % boundary).encode())
    return buf.getvalue(), "multipart/form-data; boundary=" + boundary


def moodboard_files(folder: str, limit: int = 8) -> list[tuple[str, str, bytes, str]]:
    """Up to `limit` reference pictures from the folder, each shrunk to at most 1024 px on its long side."""
    from PIL import Image
    out = []
    if not folder or not os.path.isdir(folder):
        return out
    for fn in sorted(os.listdir(folder)):
        if not fn.lower().endswith((".png", ".jpg", ".jpeg", ".webp")):
            continue
        im = Image.open(os.path.join(folder, fn)).convert("RGBA")
        im.thumbnail((1024, 1024))
        b = io.BytesIO()
        im.save(b, "PNG")
        out.append(("image[]", os.path.splitext(fn)[0] + ".png", b.getvalue(), "image/png"))
        if len(out) >= limit:
            break
    return out


def request_for(key: str, model: str, size: str, quality: str, refs: list, n: int) -> tuple[str, bytes, str]:
    """(url, body, content type) for one key. With references: /images/edits (multipart); else /images/generations (JSON)."""
    common = {"model": model, "prompt": prompt_for(key), "size": size, "quality": quality, "n": str(n),
              "background": "transparent", "output_format": "png"}
    if refs:
        body, ctype = multipart(common, refs)
        return API_BASE + "/images/edits", body, ctype
    body = json.dumps({**common, "n": n}).encode()
    return API_BASE + "/images/generations", body, "application/json"


def cmd_generate(args: argparse.Namespace) -> int:
    keys = args.keys.split(",") if args.keys else list(SETS[args.set_name])
    bad = [k for k in keys if k not in CATALOGUE]
    if bad:
        print("artgen: unknown keys %s (see `artgen.py list`)" % ", ".join(bad), file=sys.stderr)
        return 2
    refs = moodboard_files(args.moodboard)
    if args.moodboard and not refs:
        print("artgen: no pictures found in the moodboard folder %r; using text prompts only" % args.moodboard, file=sys.stderr)
    if args.dry_run:
        for k in keys:
            url, body, ctype = request_for(k, args.model, args.size, args.quality, refs, args.n)
            print("%s -> POST %s (%d bytes, %s, %d reference pictures)\n    prompt: %s" % (k, url, len(body), ctype.split(";")[0], len(refs), prompt_for(k)))
        print("dry run: %d requests, nothing sent" % len(keys))
        return 0
    key = os.environ.get(KEY_VAR, "")
    if not key:
        print("artgen: the environment variable %s is not set.\n"
              "Export your OpenAI API key as %s (it is read from the environment only, never stored or printed) and run again."
              % (KEY_VAR, KEY_VAR), file=sys.stderr)
        return 2
    try:
        check_host()
    except GenError as e:
        print(e.code, file=sys.stderr)
        return 3
    os.makedirs(args.out, exist_ok=True)
    done = 0
    for k in keys:
        url, body, ctype = request_for(k, args.model, args.size, args.quality, refs, args.n)
        req = urllib.request.Request(url, data=body, method="POST",
                                     headers={"Authorization": "Bearer " + key, "Content-Type": ctype})
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                data = json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            msg = scrub(e.read(600).decode("utf-8", "replace"), key)
            print("artgen: %s failed: HTTP %d %s" % (k, e.code, msg), file=sys.stderr)
            if e.code in (401, 403):
                return 4                                                  # wrong or unauthorised key: stop at once
            continue
        except (urllib.error.URLError, socket.timeout, OSError) as e:
            print("artgen: %s failed: %s" % (k, scrub(str(e), key)), file=sys.stderr)
            continue
        for i, item in enumerate(data.get("data", [])):
            raw = base64.b64decode(item["b64_json"]) if "b64_json" in item else urllib.request.urlopen(item["url"]).read()
            name = slug(k) + (".png" if i == 0 else "_%d.png" % (i + 1))
            with open(os.path.join(args.out, name), "wb") as f:
                f.write(raw)
            print("saved", os.path.join(args.out, name))
            done += 1
        time.sleep(args.delay)
    print("generated %d pictures into %s; now: artgen.py import --src %s --set <name>" % (done, args.out, args.out))
    return 0 if done else 1


# --- Stage 2: import ---------------------------------------------------------------------------

def key_for_file(fn: str, mapping: dict[str, str]) -> str | None:
    if fn in mapping:
        return mapping[fn]
    stem = os.path.splitext(fn)[0]
    if stem in mapping:
        return mapping[stem]
    if stem.endswith(tuple("_%d" % i for i in range(2, 10))):
        stem = stem.rsplit("_", 1)[0]
    k = unslug(stem)
    if ":" in k:
        return k
    hits = [c for c in CATALOGUE if c.split(":", 1)[1] == stem]
    return hits[0] if len(hits) == 1 else None


def box_downscale(arr, w: int, h: int):
    """Area-average an RGBA array to w x h with premultiplied colour, so a soft edge becomes a partial alpha to threshold."""
    import numpy as np
    from PIL import Image
    a = arr.astype(np.float64)
    alpha = a[..., 3:4] / 255.0
    pm = np.concatenate([a[..., :3] * alpha, a[..., 3:4]], axis=2)
    ims = [Image.fromarray(np.clip(pm[..., i], 0, 255).astype(np.uint8), "L").resize((w, h), Image.BOX) for i in range(4)]
    chans = np.stack([np.array(i, dtype=np.float64) for i in ims], axis=2)
    al = chans[..., 3:4] / 255.0
    rgb = np.where(al > 0.01, chans[..., :3] / np.maximum(al, 0.01), 0)
    return np.concatenate([np.clip(rgb, 0, 255), chans[..., 3:4]], axis=2).astype(np.uint8)


def clean_sprite(im, size: int, palette: str, outline: bool, border: int = 1):
    """Any RGBA picture to a size x size game sprite (see the module doc). Returns an RGBA numpy array."""
    import numpy as np
    import art_pipeline as ap
    arr = np.array(im.convert("RGBA"))
    arr = ap.remove_background(arr)                       # a flat white or magenta background becomes transparent
    # soft edges: keep pixels that are mostly opaque, drop the fringe and any halo of near-white
    arr = ap.binary_alpha(arr, 128)
    arr = ap.keep_largest_blob(arr)
    b = ap.bbox(arr)
    if b is None:
        raise ValueError("nothing left after removing the background")
    arr = arr[b[1]:b[3] + 1, b[0]:b[2] + 1]
    room = size - 2 * border - (2 if outline else 0)
    h, w = arr.shape[:2]
    k = min(room / w, room / h)
    nw, nh = max(1, round(w * k)), max(1, round(h * k))
    if (nw, nh) != (w, h):
        arr = ap.binary_alpha(box_downscale(arr, nw, nh), 128)
    arr = ap.fit(arr, size, border + (1 if outline else 0))
    if palette == "snap":
        arr = ap.snap(arr)
    if outline:
        arr = ap.outline_rect(arr)
    return arr


def clean_texture(im, size: int, palette: str):
    import numpy as np
    from PIL import Image
    import art_pipeline as ap
    rgb = im.convert("RGB").resize((size, size), Image.BOX)
    arr = np.dstack([np.array(rgb), np.full((size, size), 255, dtype=np.uint8)])
    if palette == "snap":
        arr = ap.snap(arr, ap.TEXTURE_PALETTE)
    return arr


def want_size(key: str, args: argparse.Namespace) -> int:
    if key.startswith("tex:"):
        return 64
    if key.startswith("tile:"):
        return 32
    if key.startswith("box_big:"):
        return 64
    return args.size


def cmd_import(args: argparse.Namespace) -> int:
    from PIL import Image
    set_dir = os.path.join(args.assets, "sets", args.set)
    os.makedirs(set_dir, exist_ok=True)
    mp = {}
    if args.map:
        with open(args.map, encoding="utf-8") as f:
            mp = json.load(f)
    man_path = os.path.join(set_dir, "manifest.json")
    manifest = {}
    if os.path.exists(man_path):
        with open(man_path, encoding="utf-8") as f:
            manifest = json.load(f)
    wanted = set(args.keys.split(",")) if args.keys else None
    done, skipped = [], []
    for fn in sorted(os.listdir(args.src)):
        if not fn.lower().endswith((".png", ".jpg", ".jpeg", ".webp", ".bmp")):
            continue
        key = key_for_file(fn, mp)
        if key is None or (wanted and key not in wanted):
            skipped.append(fn)
            continue
        try:
            im = Image.open(os.path.join(args.src, fn))
            kind = key.split(":", 1)[0]
            size = want_size(key, args)
            if kind in ("tex", "tile"):
                arr = clean_texture(im, size, args.palette)
            else:
                outline = args.outline == "on" or (args.outline == "auto" and kind in OUTLINE_KINDS)
                arr = clean_sprite(im, size, args.palette, outline)
        except Exception as e:                            # one bad picture must not stop the batch
            print("artgen: %s: %s" % (fn, e), file=sys.stderr)
            skipped.append(fn)
            continue
        sub = {"item": "items", "mon": "monsters", "boss": "headliners", "pet": "pets", "furn": "furniture",
               "fx": "fx", "player": "player", "box": "boxes", "box_big": "boxes", "tex": "textures", "tile": "tiles"}.get(kind, "misc")
        rel = "%s/%s.png" % (sub, key.split(":", 1)[1].replace(":", "_"))
        out = os.path.join(set_dir, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        Image.fromarray(arr, "RGBA").save(out, optimize=True)
        manifest[key] = {"file": rel, "origin": "imported", "source": [fn], "palette": args.palette,
                         "licence": args.licence, "note": args.note}
        done.append((key, fn, out))
    with open(man_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
        f.write("\n")
    print("imported %d pictures into %s (%d skipped%s)" % (len(done), set_dir, len(skipped),
                                                           ": " + ", ".join(skipped) if skipped else ""))
    if args.sheet:
        make_sheet(args.sheet, [(k, os.path.join(args.src, fn), out) for k, fn, out in done])
        print("contact sheet:", args.sheet)
    return 0 if done else 1


def make_sheet(path: str, rows: list[tuple[str, str, str]], cols: int = 4) -> None:
    """Before (the input, shrunk) and after (the sprite at 4x on a checkerboard) for each picture."""
    from PIL import Image, ImageDraw
    cell_w, cell_h = 128 + 128 + 24, 128 + 22
    sheet = Image.new("RGBA", (cols * cell_w, ((len(rows) + cols - 1) // cols) * cell_h), (60, 58, 70, 255))
    d = ImageDraw.Draw(sheet)
    for i, (key, before, after) in enumerate(rows):
        x, y = (i % cols) * cell_w + 6, (i // cols) * cell_h + 4
        b = Image.open(before).convert("RGBA")
        b.thumbnail((128, 128))
        sheet.alpha_composite(b, (x, y))
        a = Image.open(after).convert("RGBA")
        scale = max(1, 128 // a.width)
        a = a.resize((a.width * scale, a.height * scale), Image.NEAREST)
        chk = Image.new("RGBA", a.size, (90, 88, 100, 255))
        cd = ImageDraw.Draw(chk)
        for cy in range(0, a.height, 8):
            for cx in range(0, a.width, 8):
                if (cx // 8 + cy // 8) % 2:
                    cd.rectangle((cx, cy, cx + 7, cy + 7), fill=(110, 108, 120, 255))
        chk.alpha_composite(a)
        sheet.alpha_composite(chk, (x + 140, y))
        d.text((x, y + 128 + 4), key, fill=(255, 255, 255, 255))
    sheet.save(path)


def cmd_sheet(args: argparse.Namespace) -> int:
    set_dir = os.path.join(args.assets, "sets", args.set)
    with open(os.path.join(set_dir, "manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)
    rows = [(k, os.path.join(set_dir, e["file"]), os.path.join(set_dir, e["file"])) for k, e in manifest.items()
            if isinstance(e, dict) and "file" in e]
    make_sheet(args.out, rows)
    print("contact sheet:", args.out)
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    for k, v in CATALOGUE.items():
        print("%-18s %s" % (k, v))
    print("\n%d keys. Every prompt starts with the shared style text:\n%s" % (len(CATALOGUE), STYLE))
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Crawl Live! art trial plumbing (see the top of this file)")
    sub = p.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("generate", help="stage 1: call the OpenAI Images API")
    g.add_argument("--moodboard", default="", help="folder of style reference pictures")
    g.add_argument("--out", default="/tmp/artgen_raw", help="where the raw pictures go (keep outside the repo)")
    g.add_argument("--keys", default="", help="comma separated art keys (default: the catalogue set)")
    g.add_argument("--set-name", default="items", choices=sorted(SETS), help="which catalogue group to generate (default items)")
    g.add_argument("--model", default=DEFAULT_MODEL)
    g.add_argument("--size", default="1024x1024")
    g.add_argument("--quality", default="medium", choices=["low", "medium", "high", "auto"])
    g.add_argument("--n", type=int, default=1, help="pictures per key")
    g.add_argument("--delay", type=float, default=1.0, help="seconds between calls")
    g.add_argument("--dry-run", action="store_true", help="print the requests and exit (no key, no network)")
    g.set_defaults(fn=cmd_generate)
    i = sub.add_parser("import", help="stage 2: clean pictures into an art set")
    i.add_argument("--src", required=True, help="folder of pictures named after art keys")
    i.add_argument("--set", default="ai_trial", help="the art set name (godot/assets/sets/<name>/)")
    i.add_argument("--assets", default=ASSETS, help="the assets folder (default godot/assets)")
    i.add_argument("--size", type=int, default=32, choices=[32, 64], help="sprite size (default 32)")
    i.add_argument("--palette", default="snap", choices=["snap", "keep"], help="snap to the shared palette, or keep colours")
    i.add_argument("--outline", default="auto", choices=["auto", "on", "off"], help="1 px near-black outline (auto: items, furniture, boxes)")
    i.add_argument("--keys", default="", help="only these keys")
    i.add_argument("--map", default="", help="JSON {file name or stem: art key}")
    i.add_argument("--licence", default="unrecorded: record the source and licence before this set ships")
    i.add_argument("--note", default="")
    i.add_argument("--sheet", default="", help="write a before/after contact sheet here")
    i.set_defaults(fn=cmd_import)
    s = sub.add_parser("sheet", help="contact sheet of a set")
    s.add_argument("--set", default="ai_trial")
    s.add_argument("--assets", default=ASSETS)
    s.add_argument("--out", required=True)
    s.set_defaults(fn=cmd_sheet)
    l = sub.add_parser("list", help="print the catalogue and prompts")
    l.set_defaults(fn=cmd_list)
    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
