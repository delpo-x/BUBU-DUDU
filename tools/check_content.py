"""Content checks that need no Godot: python -I tools/check_content.py

Checks dialogue/bark/memory/credits data (shape, speakers, empty or duplicate text, long lines,
repeated punctuation) and that the UI color tokens in scenes/ui/UiTheme.gd keep the contrast the
README promises (4.5:1 for text on the panel). Exit code 1 if anything fails. Only reads data
files; it never prints dialogue text except for the offending line itself.
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEAKERS = ("bubu", "dudu", "both", "narr")
MAX_LINE = 170          # characters in one dialogue line before the box gets crowded
MIN_CONTRAST = 4.5
TEXT_TOKENS = ("INK", "MUTED", "ACCENT_INK", "BUBU", "DUDU")
# Names a dialogue condition or {placeholder} may use: read from scenes/core/DialogueText.gd.
DIALOGUE_VARS = re.findall(r'"(\w+)"', re.search(r"const VARS := \[(.*?)\]",
                           open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scenes", "core", "DialogueText.gd"), encoding="utf-8").read(), re.S).group(1))
problems = []


def path(*p):
    return os.path.join(ROOT, *p)


def load(rel):
    with open(path(rel), encoding="utf-8") as f:
        return json.load(f)


def fail(msg):
    problems.append(msg)
    print("   " + msg)


def check_lines(where, lines):
    if not isinstance(lines, list) or not lines:
        fail("%s: not a non-empty list of lines" % where)
        return
    for i, ln in enumerate(lines):
        t = ln.get("t") if isinstance(ln, dict) else None
        if not isinstance(ln, dict) or ln.get("s") not in SPEAKERS or not isinstance(t, str) or not t.strip():
            fail("%s[%d]: bad speaker or empty text" % (where, i))
            continue
        if len(t) > MAX_LINE:
            fail("%s[%d]: %d characters (max %d)" % (where, i, len(t), MAX_LINE))
        mood = ln.get("m")
        if mood is not None and not any(os.path.exists(path("art", "stickers", "%s_%s.tres" % (w, mood))) for w in (ln["s"], "both")):
            fail("%s[%d]: no sticker art/stickers/%s_%s.tres for mood" % (where, i, ln["s"], mood))
        cond = ln.get("if")
        if cond is not None:
            words = set(re.findall(r"[A-Za-z_]+", re.sub(r"\"[^\"]*\"|'[^']*'", "", cond)))
            unknown = words - set(DIALOGUE_VARS) - {"mem", "seen", "and", "or", "not", "true", "false"}
            if unknown or not cond.strip():
                fail("%s[%d]: condition uses unknown names %s" % (where, i, sorted(unknown)))
        for ph in re.findall(r"\{([^{}|]*)\}", t):
            if ph not in DIALOGUE_VARS:
                fail("%s[%d]: unknown placeholder {%s}" % (where, i, ph))
        if t != t.strip() or "  " in t or re.search(r"[.!?,]{4,}", t):
            fail("%s[%d]: stray spaces or repeated punctuation" % (where, i))


def section(name):
    print("[%s]" % name)


section("dialogue")
seen_ids = {}
for f in sorted(glob.glob(path("data", "dialogue", "ch*.json")) + [path("data", "dialogue", "common.json")]):
    rel = os.path.relpath(f, ROOT)
    for key, lines in load(rel).items():
        if key in seen_ids:
            fail("%s: id %s also in %s" % (rel, key, seen_ids[key]))
        seen_ids[key] = rel
        check_lines("%s:%s" % (rel, key), lines)

section("barks")
for pool, entries in load("data/dialogue/barks.json").items():
    if not isinstance(entries, list) or not entries:
        fail("barks:%s: empty pool" % pool)
        continue
    texts = set()
    for n, entry in enumerate(entries):
        check_lines("barks:%s#%d" % (pool, n), entry)
        key = json.dumps(entry, ensure_ascii=False)
        if key in texts:
            fail("barks:%s#%d: duplicate entry" % (pool, n))
        texts.add(key)

section("memories")
memories = load("data/memories.json")
chapters = {c["id"] for c in load("data/chapters.json")}
for mid, m in memories.items():
    for field in ("chapter", "title", "short", "text"):
        if not isinstance(m.get(field), str) or not m[field].strip():
            fail("memories:%s: missing %s" % (mid, field))
    if m.get("chapter") not in chapters:
        fail("memories:%s: unknown chapter %r" % (mid, m.get("chapter")))
    if len(m.get("short", "")) > 60:
        fail("memories:%s: caption longer than 60 characters" % mid)

section("credits")
for i, row in enumerate(load("data/credits.json")):
    if not isinstance(row.get("t"), str) or not isinstance(row.get("size"), int):
        fail("credits[%d]: needs text 't' and integer 'size'" % i)


def luminance(rgb):
    def ch(v):
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


section("ui contrast")
src = open(path("scenes", "ui", "UiTheme.gd"), encoding="utf-8").read()
colors = {m.group(1): tuple(float(x) for x in m.group(2).split(","))
          for m in re.finditer(r"^const (\w+) := Color\(([\d.,\s]+)\)", src, re.M)}
if "PANEL" not in colors:
    fail("UiTheme.gd: PANEL token not found")
else:
    for tok in TEXT_TOKENS:
        if tok not in colors:
            fail("UiTheme.gd: %s token not found" % tok)
            continue
        c = contrast(colors[tok][:3], colors["PANEL"][:3])
        print("   %-10s %.1f:1" % (tok, c))
        if c < MIN_CONTRAST:
            fail("%s on PANEL is %.1f:1 (needs %.1f:1)" % (tok, c, MIN_CONTRAST))

print("\n%s (%d problem%s)" % ("FAIL" if problems else "OK", len(problems), "" if len(problems) == 1 else "s"))
sys.exit(1 if problems else 0)
