"""Encodes the clips recorded by tests/test_gifs.gd into looping animated GIFs.
Pure Python (no Pillow). Run from the project root after recording:

  godot --fixed-fps 60 --path . --script res://tests/run.gd -- gifs
  python -I tools/make_gif.py [clip names]

Reads user://gifs/<clip>.rgb (header: width, height, frame count, delay in 1/100 s, all
little-endian u32; then raw RGB8 frames) and writes media/gifs/<clip>.gif.

Each clip gets one 255-color palette (the most used colors of the flat vector art, then
every other color mapped to its nearest entry). After the first frame only the changed
rectangle is stored and unchanged pixels inside it are transparent, which keeps the files
small: the background never changes in the still-camera clips.
"""
import os
import struct
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "Bubu & Dudu", "gifs")
OUT = os.path.join(ROOT, "media", "gifs")
TRANSPARENT = 255


def read_clip(path):
    with open(path, "rb") as f:
        w, h, n, delay = struct.unpack("<4I", f.read(16))
        data = f.read()
    size = w * h * 3
    frames = [data[i * size:(i + 1) * size] for i in range(n)]
    return w, h, delay, frames


def build_palette(frames):
    """Popularity palette: 5-bit bins, each represented by its pixels' mean color."""
    counts = Counter()
    for fr in frames:
        counts.update(zip(fr[0::3], fr[1::3], fr[2::3]))
    bins = {}
    for (r, g, b), c in counts.items():
        k = (r >> 3, g >> 3, b >> 3)
        acc = bins.get(k)
        if acc is None:
            bins[k] = [c, r * c, g * c, b * c]
        else:
            acc[0] += c
            acc[1] += r * c
            acc[2] += g * c
            acc[3] += b * c
    top = sorted(bins.values(), key=lambda a: -a[0])[:TRANSPARENT]
    palette = [(a[1] // a[0], a[2] // a[0], a[3] // a[0]) for a in top]
    lut = {}
    for col in counts:
        r, g, b = col
        best = 0
        best_d = 1 << 30
        for i, (pr, pg, pb) in enumerate(palette):
            d = (r - pr) * (r - pr) * 3 + (g - pg) * (g - pg) * 4 + (b - pb) * (b - pb) * 2
            if d < best_d:
                best_d = d
                best = i
        lut[col] = best
    return palette, lut


def lzw(indices, min_size=8):
    """GIF LZW (variable code width up to 12 bits, clear code when the table is full)."""
    clear = 1 << min_size
    eoi = clear + 1
    out = bytearray()
    acc = 0
    nbits = 0
    size = min_size + 1
    next_code = eoi + 1
    table = {}

    def emit(code):
        nonlocal acc, nbits, size
        acc |= code << nbits
        nbits += size
        while nbits >= 8:
            out.append(acc & 0xFF)
            acc >>= 8
            nbits -= 8
        # Same rule as giflib: widen once the next free code no longer fits.
        if next_code >= (1 << size) and size < 12:
            size += 1

    emit(clear)
    prefix = indices[0]
    for px in indices[1:]:
        key = (prefix << 8) | px
        code = table.get(key)
        if code is not None:
            prefix = code
            continue
        emit(prefix)
        if next_code >= 4095:
            emit(clear)
            table.clear()
            next_code = eoi + 1
            size = min_size + 1
        else:
            table[key] = next_code
            next_code += 1
        prefix = px
    emit(prefix)
    emit(eoi)
    if nbits > 0:
        out.append(acc & 0xFF)
    return bytes(out)


def sub_blocks(data):
    out = bytearray()
    for i in range(0, len(data), 255):
        chunk = data[i:i + 255]
        out.append(len(chunk))
        out += chunk
    out.append(0)
    return bytes(out)


def encode(w, h, delay, frames):
    palette, lut = build_palette(frames)
    gif = bytearray(b"GIF89a")
    gif += struct.pack("<HHBBB", w, h, 0xF7, 0, 0)
    for i in range(256):
        gif += bytes(palette[i]) if i < len(palette) else b"\0\0\0"
    gif += b"\x21\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00"  # loop forever
    prev = None
    for fr in frames:
        idx = bytes(lut[c] for c in zip(fr[0::3], fr[1::3], fr[2::3]))
        if prev is None:
            x0, y0, x1, y1 = 0, 0, w, h
            pixels = idx
            flags = 0x04  # disposal: keep
        else:
            rows = [y for y in range(h) if idx[y * w:(y + 1) * w] != prev[y * w:(y + 1) * w]]
            if not rows:
                rows = [0]
            y0, y1 = rows[0], rows[-1] + 1
            x0, x1 = w, 0
            for y in rows:
                a = idx[y * w:(y + 1) * w]
                b = prev[y * w:(y + 1) * w]
                if a == b:
                    continue
                lo = next(x for x in range(w) if a[x] != b[x])
                hi = next(x for x in range(w - 1, -1, -1) if a[x] != b[x]) + 1
                x0, x1 = min(x0, lo), max(x1, hi)
            if x1 <= x0:
                x0, x1 = 0, 1
            buf = bytearray()
            for y in range(y0, y1):
                a = idx[y * w + x0:y * w + x1]
                b = prev[y * w + x0:y * w + x1]
                buf += bytes(TRANSPARENT if p == q else p for p, q in zip(a, b))
            pixels = bytes(buf)
            flags = 0x05  # keep + transparent index
        gif += b"\x21\xF9\x04" + struct.pack("<BHBB", flags, delay, TRANSPARENT, 0)
        gif += b"\x2C" + struct.pack("<HHHHB", x0, y0, x1 - x0, y1 - y0, 0)
        gif += b"\x08" + sub_blocks(lzw(pixels))
        prev = idx
    gif += b"\x3B"
    return bytes(gif)


def main():
    if not os.path.isdir(SRC):
        sys.exit("no recorded clips in %s (run the gifs suite first)" % SRC)
    names = sys.argv[1:] or sorted(f[:-4] for f in os.listdir(SRC) if f.endswith(".rgb"))
    os.makedirs(OUT, exist_ok=True)
    # Godot must not try to import the GIFs.
    open(os.path.join(OUT, ".gdignore"), "w").close()
    for name in names:
        w, h, delay, frames = read_clip(os.path.join(SRC, name + ".rgb"))
        data = encode(w, h, delay, frames)
        with open(os.path.join(OUT, name + ".gif"), "wb") as f:
            f.write(data)
        print("[OK] %s.gif: %dx%d, %d frames, %d KB" % (name, w, h, len(frames), len(data) // 1024))


if __name__ == "__main__":
    main()
