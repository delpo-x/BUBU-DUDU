"""Writes the UI icons (SVG) in art/ui/: heart, next arrow, option toggles, slider knob.
Run from the project root:  python -I tools/gen_sprites.py

The UI draws these instead of font glyphs or emoji that a web font might lack. The
characters themselves are the animated stickers in art/stickers/.
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art")


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
    write(os.path.join(OUT, "ui", "heart.svg"), HEART)
    write(os.path.join(OUT, "ui", "next.svg"), NEXT)
    write(os.path.join(OUT, "ui", "toggle_on.svg"), TOGGLE_ON)
    write(os.path.join(OUT, "ui", "grabber.svg"), GRABBER)
    write(os.path.join(OUT, "ui", "toggle_off.svg"), TOGGLE_OFF)
    print("[OK] UI icons written")


if __name__ == "__main__":
    main()
