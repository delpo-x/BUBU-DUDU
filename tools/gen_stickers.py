"""Cuts animated sticker WebPs into transparent sprite sheets for Godot.

    python -I tools/gen_stickers.py path/to/folder_with_webp [fps]

For every <name>.webp in the folder it writes art/stickers/<name>.png (frames in a grid, row by row)
and art/stickers/<name>.tres (SpriteFrames, animation "default", looping), cropped to the
union of all frames so the character never jumps inside its box.

Per frame:
  1. Text and decorations that float on the white background (separate blobs, e.g. Chinese
     captions) are painted white. Only the biggest blob, the character, is kept.
  2. Everything light and grey that can be reached from the border without crossing the dark
     outline becomes black with alpha from its darkness: the white background vanishes, the
     anti-aliased edge stays smooth and the soft floor shadow turns into a real shadow.
     White inside the outline (the panda's fur) is never reached, so it stays opaque.
     Files whose name starts with "dudu" have no white in the character, so for them every
     near-white pixel goes (e.g. the white seen through a skipping rope).

Needs Pillow and numpy.
"""
import math
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "stickers")
BG_MIN = 236          # every channel above this, with little colour, is background
LIGHT_LUM = 120       # light enough to become see-through when reached from the border
GREY_SAT = 48         # max channel spread for "grey"
SIZE = 256            # longest side of a frame in the sheet


def flood(mask, seeds):
    """Pixels of `mask` 4-connected to any seed pixel."""
    h, w = mask.shape
    out = np.zeros_like(mask)
    q = deque()
    for y, x in seeds:
        if mask[y, x] and not out[y, x]:
            out[y, x] = True
            q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not out[ny, nx]:
                out[ny, nx] = True
                q.append((ny, nx))
    return out


def border(h, w):
    return [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] + \
           [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]


def cropped_body(dark):
    """Border pixels where the character is cut by the frame: on each edge, a run between
    two outline crossings (not reaching a corner) is inside the body, not background."""
    h, w = dark.shape
    out = np.zeros_like(dark)
    for line, setter in ((dark[0], lambda a, b: out.__setitem__((0, slice(a, b)), True)),
                         (dark[h - 1], lambda a, b: out.__setitem__((h - 1, slice(a, b)), True)),
                         (dark[:, 0], lambda a, b: out.__setitem__((slice(a, b), 0), True)),
                         (dark[:, w - 1], lambda a, b: out.__setitem__((slice(a, b), w - 1), True))):
        idx = np.nonzero(line)[0]
        if idx.size < 2:
            continue
        # Outline crossings: groups of dark pixels; pair them up from the outside in.
        groups = np.split(idx, np.nonzero(np.diff(idx) > 1)[0] + 1)
        if len(groups) >= 2:
            setter(groups[0][0], groups[-1][-1] + 1)
    return out


def biggest_blob(mask):
    """Largest 4-connected component of `mask`."""
    seen = np.zeros_like(mask)
    best, best_n = None, 0
    ys, xs = np.nonzero(mask)
    for y, x in zip(ys, xs):
        if seen[y, x]:
            continue
        comp = flood(mask & ~seen, [(y, x)])
        seen |= comp
        n = int(comp.sum())
        if n > best_n:
            best, best_n = comp, n
    return best if best is not None else mask


def cut(frame, white_is_bg=False):
    rgb = np.asarray(frame.convert("RGB")).astype(np.int16)
    h, w, _ = rgb.shape
    lum = rgb.mean(axis=2)
    spread = rgb.max(axis=2) - rgb.min(axis=2)
    seeds = border(h, w)
    wall = cropped_body(lum < 110)
    bg = flood(~wall & (rgb.min(axis=2) > BG_MIN) & (spread < 24), seeds)
    # 1. Keep the character only: drop floating captions and specks.
    keep = biggest_blob(~bg)
    rgb[~bg & ~keep] = 255
    lum = rgb.mean(axis=2)
    spread = rgb.max(axis=2) - rgb.min(axis=2)
    # 2. Light grey reachable from outside -> black with alpha (background, edge, shadow).
    see_through = flood(~wall & (lum > LIGHT_LUM) & (spread < GREY_SAT), seeds)
    if white_is_bg:
        see_through |= (lum > 175) & (spread < 40)
    alpha = np.full((h, w), 255, np.uint8)
    a = np.clip((BG_MIN - lum) / (BG_MIN - LIGHT_LUM), 0.0, 1.0)
    alpha[see_through] = (a[see_through] * 255).astype(np.uint8)
    out = np.dstack([rgb.clip(0, 255).astype(np.uint8), alpha])
    shade = np.array([60, 40, 36], np.uint8)  # warm shadow tint, matches the outline
    out[see_through, :3] = shade
    return Image.fromarray(out, "RGBA")


def frames_of(path):
    im = Image.open(path)
    for i in range(getattr(im, "n_frames", 1)):
        im.seek(i)
        yield im.convert("RGBA")


def build(path, fps):
    name = os.path.splitext(os.path.basename(path))[0]
    cuts = [cut(f, name.startswith("dudu")) for f in frames_of(path)]
    box = None
    for c in cuts:
        b = c.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    box = box or (0, 0) + cuts[0].size
    cw, ch = box[2] - box[0], box[3] - box[1]
    k = SIZE / max(cw, ch)
    fw, fh = max(1, round(cw * k)), max(1, round(ch * k))
    # A grid keeps the sheet under 4096 px, which every web GPU accepts.
    cols = math.ceil(math.sqrt(len(cuts)))
    rows = math.ceil(len(cuts) / cols)
    sheet = Image.new("RGBA", (fw * cols, fh * rows), (0, 0, 0, 0))
    for i, c in enumerate(cuts):
        sheet.paste(c.crop(box).resize((fw, fh), Image.LANCZOS), ((i % cols) * fw, (i // cols) * fh))
    os.makedirs(OUT, exist_ok=True)
    sheet.save(os.path.join(OUT, name + ".png"), optimize=True)
    res = "res://art/stickers/%s.png" % name
    lines = ['[gd_resource type="SpriteFrames" load_steps=%d format=3]' % (len(cuts) + 2), "",
             '[ext_resource type="Texture2D" path="%s" id="1"]' % res, ""]
    for i in range(len(cuts)):
        lines += ['[sub_resource type="AtlasTexture" id="f%d"]' % i, 'atlas = ExtResource("1")',
                  "region = Rect2(%d, %d, %d, %d)" % ((i % cols) * fw, (i // cols) * fh, fw, fh), ""]
    frames = ", ".join('{\n"duration": 1.0,\n"texture": SubResource("f%d")\n}' % i for i in range(len(cuts)))
    lines += ["[resource]", 'animations = [{\n"frames": [%s],\n"loop": true,\n"name": &"default",\n"speed": %.1f\n}]' % (frames, fps), ""]
    with open(os.path.join(OUT, name + ".tres"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("%-24s %2d frames  %dx%d" % (name, len(cuts), fw, fh))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    folder = sys.argv[1]
    fps = float(sys.argv[2]) if len(sys.argv) > 2 else 12.0
    for f in sorted(os.listdir(folder)):
        if f.lower().endswith(".webp"):
            build(os.path.join(folder, f), fps)


if __name__ == "__main__":
    main()
