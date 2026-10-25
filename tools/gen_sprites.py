"""Builds the character sprite parts (SVG) from the Bubu & Dudu vector pack.
Run from the project root:  python -I tools/gen_sprites.py [path/to/pack_dir]

The pack's illustrations draw both characters with the same shapes (head, ears, muzzle,
body, arms) and two palettes. This script cuts those shapes into separate parts, each
centered on its pivot, so scenes/characters/CharacterRig.gd can animate them:

  art/characters/<name>/head.svg  ear.svg  body.svg  arm.svg  foot.svg
  art/characters/<name>/face_open.svg  face_blink.svg  face_happy.svg  face_oh.svg

Coordinates stay in pack units (the pack draws a head of radius 123) and are scaled by
EXPORT_SCALE, which renders the textures at 2x their on-screen size (the rig draws them
at 0.5) so they stay sharp in a 1080p window. With a pack dir, the six illustrations are
also copied to art/illustrations/ for the menus (see fix_illustration).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art")

## Pack units -> texture pixels. On screen the rig shows them at half this (0.15 px/unit).
EXPORT_SCALE = 0.3
STROKE = 9

# Palettes copied from the pack's illustrations.
PALETTES = {
    "bubu": {  # panda
        "head": "#ffffff", "body": "#ffffff", "line": "#34343b",
        "ear": "#34343b", "ear_in": "#f5b6c1", "muzzle": "#ffffff",
        "nose": "#34343b", "eye": "#25252a", "cheek": "#ef9da5", "cheek_op": ".75",
        "limb": "#34343b", "foot": "#34343b", "pad": "#f5b6c1", "patches": True,
    },
    "dudu": {  # honey-brown bear
        "head": "#d99d73", "body": "#c98b62", "line": "#6f4938",
        "ear": "#c98b62", "ear_in": "#f0c4a5", "muzzle": "#f5d8c1",
        "nose": "#49362f", "eye": "#302722", "cheek": "#ef9da5", "cheek_op": ".7",
        "limb": "#6f4938", "foot": "#b97c55", "pad": "#f0c4a5", "patches": False,
    },
}


def svg(w, h, body):
    """An SVG of w x h pack units with the origin (pivot) at the center."""
    pw, ph = round(w * EXPORT_SCALE), round(h * EXPORT_SCALE)
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%g %g %g %g">\n%s\n</svg>\n'
            % (pw, ph, -w / 2, -h / 2, w, h, body))


def head(p):
    return svg(260, 260, '<circle cx="0" cy="0" r="123" fill="%s" stroke="%s" stroke-width="%d"/>'
               % (p["head"], p["line"], STROKE))


def ear(p):
    return svg(120, 120, '<circle cx="0" cy="0" r="53" fill="%s" stroke="%s" stroke-width="%d"/>'
               '<circle cx="0" cy="0" r="25" fill="%s"/>' % (p["ear"], p["line"], STROKE, p["ear_in"]))


def body(p):
    return svg(270, 310, '<ellipse cx="0" cy="0" rx="126" ry="148" fill="%s" stroke="%s" stroke-width="%d"/>'
               '<ellipse cx="0" cy="38" rx="78" ry="82" fill="%s" opacity=".55"/>'
               % (p["body"], p["line"], STROKE, p["muzzle"]))


def arm(p):
    # A rounded limb hanging from its pivot (the shoulder) at the top center.
    return svg(60, 240, '<path d="M0 -0 L0 100" stroke="%s" stroke-width="34" stroke-linecap="round" fill="none"/>'
               % p["limb"])


def foot(p):
    return svg(130, 90, '<ellipse cx="0" cy="0" rx="52" ry="32" fill="%s" stroke="%s" stroke-width="%d"/>'
               '<ellipse cx="0" cy="6" rx="24" ry="13" fill="%s"/>' % (p["foot"], p["line"], STROKE, p["pad"]))


def face(p, kind):
    """Eyes, muzzle, nose, mouth and cheeks, centered on the head center."""
    out = []
    if p["patches"]:
        out.append('<ellipse cx="-46" cy="-3" rx="29" ry="39" fill="%s" transform="rotate(25 -46 -3)"/>' % p["line"])
        out.append('<ellipse cx="46" cy="-3" rx="29" ry="39" fill="%s" transform="rotate(-25 46 -3)"/>' % p["line"])
    eye_on_patch = p["patches"]
    for x in (-43, 43):
        if kind in ("open", "oh"):
            if eye_on_patch:
                out.append('<circle cx="%d" cy="0" r="10" fill="#fff"/><circle cx="%d" cy="0" r="5" fill="%s"/>' % (x, x, p["eye"]))
            else:
                out.append('<circle cx="%d" cy="1" r="10" fill="%s"/>' % (x, p["eye"]))
        else:
            col = "#fff" if eye_on_patch else p["eye"]
            if kind == "blink":
                d = "M%d 2 Q%d 8 %d 2" % (x - 11, x, x + 11)
            else:  # happy: upward arcs
                d = "M%d 5 Q%d -9 %d 5" % (x - 12, x, x + 12)
            out.append('<path d="%s" fill="none" stroke="%s" stroke-width="7" stroke-linecap="round"/>' % (d, col))
    out.append('<ellipse cx="0" cy="44" rx="62" ry="46" fill="%s"/>' % p["muzzle"])
    out.append('<ellipse cx="0" cy="31" rx="19" ry="13" fill="%s"/>' % p["nose"])
    if kind == "oh":
        out.append('<ellipse cx="0" cy="64" rx="10" ry="12" fill="%s"/>' % p["nose"])
    elif kind == "happy":
        out.append('<path d="M-28 54 Q0 88 28 54 Z" fill="%s"/>' % p["nose"])
    else:
        out.append('<path d="M-25 56 Q0 79 25 56" fill="none" stroke="%s" stroke-width="8" stroke-linecap="round"/>' % p["nose"])
    cx = 72 if p["patches"] else 57
    cy = 31 if p["patches"] else 26
    out.append('<ellipse cx="-%d" cy="%d" rx="18" ry="10" fill="%s" opacity="%s"/>' % (cx, cy, p["cheek"], p["cheek_op"]))
    out.append('<ellipse cx="%d" cy="%d" rx="18" ry="10" fill="%s" opacity="%s"/>' % (cx, cy, p["cheek"], p["cheek_op"]))
    return svg(260, 260, "\n".join(out))


## The pack places each character group with translate(dx y) relative to the canvas center
## but forgets the center itself (x = 400), so both characters end up on the left edge in
## every viewer. Everything else in those files is drawn around x = 400.
CHAR_GROUP = re.compile(r'<g transform="translate\((-?\d+(?:\.\d+)?) (-?\d+(?:\.\d+)?)\) rotate')


def fix_illustration(text):
    def shift(m):
        return '<g transform="translate(%g %s) rotate' % (400 + float(m.group(1)), m.group(2))
    return CHAR_GROUP.subn(shift, text)


def head_badge(p, kind="open", size=256, backdrop="#ffd9df"):
    """The character's head with ears and face on a round backdrop (icon, portraits)."""
    inner = []
    for x in (-82, 82):
        inner.append('<circle cx="%d" cy="-74" r="53" fill="%s" stroke="%s" stroke-width="%d"/>'
                     '<circle cx="%d" cy="-74" r="25" fill="%s"/>' % (x, p["ear"], p["line"], STROKE, x, p["ear_in"]))
    inner.append('<circle cx="0" cy="0" r="123" fill="%s" stroke="%s" stroke-width="%d"/>' % (p["head"], p["line"], STROKE))
    face_svg = face(p, kind)
    inner.append(face_svg[face_svg.index(">") + 2:face_svg.rindex("</svg>")])
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="-150 -150 300 300">\n'
            '<circle cx="0" cy="0" r="148" fill="%s"/>\n%s\n</svg>\n' % (size, size, backdrop, "\n".join(inner)))


def icon(p):
    """Project / window icon: the panda's head, 256 px."""
    return head_badge(p)


# UI icons (vector, so no font glyphs or emoji are needed). Colors match UiTheme.
HEART = ('<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">\n'
         '<path d="M24 41 C10 31 4 24 4 16 C4 9 9 5 15 5 C19 5 22 7 24 11 C26 7 29 5 33 5 C39 5 44 9 44 16 '
         'C44 24 38 31 24 41Z" fill="#f2737f" stroke="#b3384f" stroke-width="3" stroke-linejoin="round"/>\n'
         '<ellipse cx="15" cy="14" rx="5" ry="3.5" fill="#ffffff" opacity=".55"/>\n</svg>\n')
NEXT = ('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">\n'
        '<path d="M6 9 L26 9 L16 24 Z" fill="#b3384f" stroke="#b3384f" stroke-width="3" stroke-linejoin="round"/>\n</svg>\n')

# Option toggles: a filled ACCENT_INK track when on, a light track with a 3:1 outline
# when off, so the state reads by shape (knob side) and not by color alone.
TOGGLE = ('<svg xmlns="http://www.w3.org/2000/svg" width="56" height="32" viewBox="0 0 56 32">\n'
          '<rect x="2" y="3" width="52" height="26" rx="13" fill="%s" stroke="%s" stroke-width="2.5"/>\n'
          '<circle cx="%d" cy="16" r="9" fill="#ffffff" stroke="%s" stroke-width="2"/>\n</svg>\n')
# Slider knob: white with an ACCENT_INK ring so it stands out on the light track.
GRABBER = ('<svg xmlns="http://www.w3.org/2000/svg" width="26" height="26" viewBox="0 0 26 26">\n'
           '<circle cx="13" cy="13" r="10" fill="#ffffff" stroke="#b3384f" stroke-width="3.5"/>\n</svg>\n')
TOGGLE_ON = TOGGLE % ("#b3384f", "#b3384f", 40, "#8f2a3e")
TOGGLE_OFF = TOGGLE % ("#e9e0d6", "#8a7d80", 16, "#8a7d80")


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main():
    count = 0
    for name, p in PALETTES.items():
        d = os.path.join(OUT, "characters", name)
        parts = {"head": head(p), "ear": ear(p), "body": body(p), "arm": arm(p), "foot": foot(p)}
        for kind in ("open", "blink", "happy", "oh"):
            parts["face_" + kind] = face(p, kind)
        for part, text in parts.items():
            write(os.path.join(d, part + ".svg"), text)
            count += 1
    print("[OK] character parts written: %d" % count)
    write(os.path.join(OUT, "icon.svg"), icon(PALETTES["bubu"]))
    for name, p in PALETTES.items():
        for kind in ("open", "blink", "happy"):
            write(os.path.join(OUT, "characters", name, "portrait_%s.svg" % kind), head_badge(p, kind, 192, "#fff1e6"))
    write(os.path.join(OUT, "ui", "heart.svg"), HEART)
    write(os.path.join(OUT, "ui", "next.svg"), NEXT)
    write(os.path.join(OUT, "ui", "toggle_on.svg"), TOGGLE_ON)
    write(os.path.join(OUT, "ui", "grabber.svg"), GRABBER)
    write(os.path.join(OUT, "ui", "toggle_off.svg"), TOGGLE_OFF)
    print("[OK] project icon, portraits and UI icons written")
    if len(sys.argv) > 1:
        src = sys.argv[1]
        dst = os.path.join(OUT, "illustrations")
        os.makedirs(dst, exist_ok=True)
        n = 0
        fixed = 0
        for f in sorted(os.listdir(src)):
            if f.lower().endswith(".svg"):
                with open(os.path.join(src, f), encoding="utf-8") as fh:
                    text, k = fix_illustration(fh.read())
                write(os.path.join(dst, f), text)
                n += 1
                fixed += k
        print("[OK] illustrations copied: %d (character groups re-centered: %d)" % (n, fixed))


if __name__ == "__main__":
    main()
