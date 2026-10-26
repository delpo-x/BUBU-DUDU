"""Cuts animated sticker WebPs into transparent sprite sheets for Godot.

    python -I tools/gen_stickers.py path/to/folder_with_webp [fps]

For every <name>.webp in the folder it writes art/stickers/<name>.webp (lossy, frames in a grid, row by row)
and art/stickers/<name>.tres (SpriteFrames, animation "default", looping), cropped to the
union of all frames so the character never jumps inside its box.

Per frame:
  1. Text and decorations that float on the white background (separate blobs, e.g. Chinese
     captions) are painted white. Only the big blobs (the characters, a speech bubble) are kept.
  2. Everything light and grey that can be reached from the border without crossing the dark
     outline becomes black with alpha from its darkness: the white background vanishes, the
     anti-aliased edge stays smooth and the soft floor shadow turns into a real shadow.
     White inside the outline (the panda's fur) is never reached, so it stays opaque.
     Stickers in WHITE_IS_BG have no white in them, so every big near-white area goes too
     (the white seen through a skipping rope).

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
WHITE_IS_BG = {"dudu_rope"}   # stickers with no white of their own
## Watermarks printed over the character: sticker -> box (x0, y0, x1, y1) in source pixels.
WATERMARKS = {"dudu_walk": (130, 335, 270, 380)}
QUALITY = 85          # WebP quality of the sheets
GAP = 4               # widest outline gap closed (pixels, at source size)
KEEP_RATIO = 0.08      # blobs this fraction of the biggest are kept...
MIN_FILL = 0.6         # ...if at least this share of them is not dark outline
FRAME_SCAN = 24       # how far in from the border to look for drawn frame lines


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


def dilate(mask, r):
    """Square dilation by `r` pixels."""
    out = mask.copy()
    for _ in range(r):
        grown = out.copy()
        grown[1:] |= out[:-1]
        grown[:-1] |= out[1:]
        grown[:, 1:] |= out[:, :-1]
        grown[:, :-1] |= out[:, 1:]
        out = grown
    return out


def strip_frame(rgb, inked):
    """Paints white the straight lines (any colour but white) some stickers draw along the
    image border. The character's dark outline crossing that line is left alone."""
    h, w = inked.shape
    soft = rgb.mean(axis=2) >= 110
    for d in range(FRAME_SCAN):
        # Each line next to the one a few pixels further in: a frame line is thin, a
        # blanket or a floor running along the edge is not.
        k = d + 4
        for sel, inner in (((d, slice(None)), (k, slice(None))), ((h - 1 - d, slice(None)), (h - 1 - k, slice(None))),
                           ((slice(None), d), (slice(None), k)), ((slice(None), w - 1 - d), (slice(None), w - 1 - k))):
            if inked[sel].mean() > 0.6 and inked[inner].mean() < 0.45:
                line = rgb[sel]
                line[soft[sel]] = 255


def big_parts(mask, min_px):
    """Components of `mask` with at least `min_px` pixels."""
    out = np.zeros_like(mask)
    seen = np.zeros_like(mask)
    ys, xs = np.nonzero(mask)
    for y, x in zip(ys, xs):
        if seen[y, x]:
            continue
        comp = flood(mask & ~seen, [(y, x)])
        seen |= comp
        if comp.sum() >= min_px:
            out |= comp
    return out


def main_blobs(mask, dark):
    """The largest component of `mask`, plus any other at least KEEP_RATIO its size that is
    mostly filled (a second character, a speech bubble). Captions are made of dark strokes
    and specks are small, so they go."""
    comps = []
    seen = np.zeros_like(mask)
    ys, xs = np.nonzero(mask)
    for y, x in zip(ys, xs):
        if seen[y, x]:
            continue
        comp = flood(mask & ~seen, [(y, x)])
        seen |= comp
        comps.append((int(comp.sum()), comp))
    if not comps:
        return mask
    top = max(n for n, _ in comps)
    out = np.zeros_like(mask)
    for n, comp in comps:
        filled = 1.0 - float((dark & comp).sum()) / n
        if n == top or (n >= top * KEEP_RATIO and filled >= MIN_FILL):
            out |= comp
    return out


def cut(frame, white_is_bg=False):
    rgb = np.asarray(frame.convert("RGB")).astype(np.int16)
    h, w, _ = rgb.shape
    lum = rgb.mean(axis=2)
    spread = rgb.max(axis=2) - rgb.min(axis=2)
    seeds = border(h, w)
    strip_frame(rgb, rgb.min(axis=2) < 230)
    lum = rgb.mean(axis=2)
    spread = rgb.max(axis=2) - rgb.min(axis=2)
    wall = cropped_body(lum < 110)
    bg = flood(~wall & (rgb.min(axis=2) > BG_MIN) & (spread < 24), seeds)
    # 1. Keep the character only: drop floating captions and specks.
    keep = main_blobs(~bg, lum < 110)
    rgb[~bg & ~keep] = 255
    lum = rgb.mean(axis=2)
    spread = rgb.max(axis=2) - rgb.min(axis=2)
    # 2. Light grey reachable from outside -> black with alpha (background, edge, shadow).
    light = (lum > LIGHT_LUM) & (spread < GREY_SAT)
    # Sketchy outlines have gaps: flood behind an outline thickened by GAP pixels, then
    # take back the light ring along it so the anti-aliased edge still fades out.
    thick = dilate(lum < 110, GAP)
    see_through = flood(~wall & light & ~thick, seeds)
    see_through |= light & dilate(see_through, GAP + 1) & ~(lum < 110)
    if white_is_bg:
        # Big near-white areas only: small ones are details (a cat's face, a highlight).
        see_through |= big_parts((lum > 175) & (spread < 40) & ~see_through, 1500)
    alpha = np.full((h, w), 255, np.uint8)
    a = np.clip((BG_MIN - lum) / (BG_MIN - LIGHT_LUM), 0.0, 1.0)
    alpha[see_through] = (a[see_through] * 255).astype(np.uint8)
    out = np.dstack([rgb.clip(0, 255).astype(np.uint8), alpha])
    shade = np.array([60, 40, 36], np.uint8)  # warm shadow tint, matches the outline
    out[see_through, :3] = shade
    return Image.fromarray(out, "RGBA")


def frames_of(path, watermark=None):
    im = Image.open(path)
    # Stickers drawn on a band inside a transparent canvas: crop to the band so where it
    # cuts the character counts as the image border (see cropped_body).
    box = None
    for i in range(getattr(im, "n_frames", 1)):
        im.seek(i)
        b = im.convert("RGBA").getchannel("A").point(lambda v: 255 if v > 200 else 0).getbbox()
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    flats = []
    for i in range(getattr(im, "n_frames", 1)):
        im.seek(i)
        # Some stickers pad with transparent pixels: flatten on white like the rest.
        flat = Image.new("RGBA", im.size, (255, 255, 255, 255))
        flat.alpha_composite(im.convert("RGBA"))
        flats.append(flat)
    if watermark:
        flats = unwatermark(flats, watermark)
    return [f.crop(box) if box else f for f in flats]


def unwatermark(frames, box):
    """Paints over a watermark printed on the character: inside `box` (source pixels),
    the pixels that stay the same white or near-black in every frame while the character
    moves under them are the text. They are filled from their neighbours, frame by frame."""
    x0, y0, x1, y1 = box
    stack = np.stack([np.asarray(f.convert("RGB")).astype(np.int16)[y0:y1, x0:x1] for f in frames])
    hi, lo = stack.max(axis=0), stack.min(axis=0)
    still = (hi - lo).max(axis=2) < 90
    ink = (lo.min(axis=2) > 190) | (hi.max(axis=2) < 110)
    mask = dilate(still & ink, 3)
    out = []
    for f in frames:
        a = np.asarray(f.convert("RGB")).astype(np.float32)
        reg = a[y0:y1, x0:x1].copy()
        known = ~mask
        # Diffusion fill: holes take the average of their known neighbours, ring by ring.
        while not known.all():
            acc = np.zeros_like(reg)
            cnt = np.zeros(mask.shape, np.float32)
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                k = np.roll(known, (dy, dx), (0, 1))
                acc += np.roll(reg, (dy, dx), (0, 1)) * k[..., None]
                cnt += k
            grow = ~known & (cnt > 0)
            if not grow.any():
                break
            reg[grow] = acc[grow] / cnt[grow][:, None]
            known = known | grow
        a[y0:y1, x0:x1] = reg
        out.append(Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGB").convert("RGBA"))
    return out


def build(path, fps):
    name = os.path.splitext(os.path.basename(path))[0]
    frames = frames_of(path, WATERMARKS.get(name))
    cuts = [cut(f, name in WHITE_IS_BG) for f in frames]
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
    # Lossy WebP keeps the repo small; the import file keeps it lossy in exports too
    # (Godot's default would re-encode it losslessly).
    sheet.save(os.path.join(OUT, name + ".webp"), quality=QUALITY, method=6)
    imp = os.path.join(OUT, name + ".webp.import")
    if not os.path.exists(imp):
        with open(imp, "w", encoding="utf-8", newline="\n") as f:
            f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
                    '[params]\n\ncompress/mode=1\ncompress/lossy_quality=%.2f\n' % (QUALITY / 100.0))
    res = "res://art/stickers/%s.webp" % name
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
