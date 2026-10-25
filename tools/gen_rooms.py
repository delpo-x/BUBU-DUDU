"""Generates every room scene + bot solution, and data/chapters.json.
Run from the project root:  python -I tools/gen_rooms.py [dev]
Only technical status lines are printed (content stays in the files).
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import beats as B  # noqa: E402
from roomkit import Builder  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def dev_rooms():
    """One whitebox room per beat: proves every beat is solvable by the bot."""
    specs = [
        ("steps", lambda b, x, g: B.gap(b, *B.steps_down(b, *B.steps_up(b, x, g, 3), 2))),
        ("boost", lambda b, x, g: B.boost_gate(b, x, g, mem="dev_m1")),
        ("plates", lambda b, x, g: B.two_plates(b, *B.two_plates(b, x, g), bridge=True)),
        ("heavy", lambda b, x, g: B.heavy_plate(b, x, g)),
        ("cozy", lambda b, x, g: B.cozy(b, x, g, mem="dev_m2")),
        ("call", lambda b, x, g: B.call_lesson(b, x, g)),
        ("crate", lambda b, x, g: B.crate_ledge(b, x, g)),
        ("hcrate", lambda b, x, g: B.heavy_crate_plate(b, x, g)),
        ("pulley", lambda b, x, g: B.pulley(b, x, g, mem="dev_m3")),
        ("ferry", lambda b, x, g: B.moving_cross(b, x, g)),
        ("lift", lambda b, x, g: B.elevator(b, x, g)),
        ("fragile", lambda b, x, g: B.fragile_drop(b, x, g)),
        ("wjump", lambda b, x, g: B.walljump_shaft(b, x, g, mem="dev_m4")),
        ("seesaw", lambda b, x, g: B.seesaw(b, x, g, mem="dev_m5")),
        ("seesaw2", lambda b, x, g: B.seesaw(b, x, g, crate_launch=True)),
        ("bounce", lambda b, x, g: B.bounce_up(b, x, g)),
        ("timed", lambda b, x, g: B.timed_pair(b, x, g)),
        ("vine", lambda b, x, g: B.vine_climb(b, x, g)),
        ("wind", lambda b, x, g: B.wind_lift(b, x, g)),
        ("cplate", lambda b, x, g: B.crate_plate_door(b, x, g)),
        ("bmem", lambda b, x, g: B.boost_memory(b, x, g, "dev_m6")),
    ]
    out = []
    for name, fn in specs:
        h = 16
        b = Builder("dev_r" + name, 1, 60, h, est=1, hint="dev", call=(name == "call"))
        b.folder = "dev"
        g = 12
        x, g = B.start(b, g)
        x, g = fn(b, x, g)
        x, g = B.exit_door(b, x, g)
        b.w = int(x + 2)
        out.append(b.write(ROOT))
    return out


def main():
    args = sys.argv[1:]
    if "dev" in args:
        paths = dev_rooms()
        print("[OK] dev rooms generated: %d" % len(paths))
        return
    import chapters  # noqa: E402
    data, builders = chapters.build(ROOT)
    with open(os.path.join(ROOT, "data", "chapters.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
    total = sum(len(c["rooms"]) for c in data)
    print("[OK] rooms generated: %d in %d chapters" % (total, len(data)))
    check_content(data, builders)


def _load(rel):
    path = os.path.join(ROOT, *rel.replace("res://", "").split("/"))
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def check_content(data, builders):
    """Every referenced dialogue / memory id exists (ids only, never content)."""
    dialogues = dict(_load("res://data/dialogue/common.json") or {})
    for c in data:
        dialogues.update(_load(c["dialogue"]) or {})
    memories = _load("res://data/memories.json") or {}
    wanted_d = set()
    for c in data:
        wanted_d.update([c["intro"], c["outro"]])
    wanted_m = set()
    for b in builders:
        wanted_d.update(b.dialogues)
        wanted_m.update(b.memories)
    miss_d = sorted(d for d in wanted_d if d not in dialogues)
    miss_m = sorted(m for m in wanted_m if m not in memories)
    bad_lines = 0
    for lines in dialogues.values():
        for ln in lines:
            if ln.get("s") not in ("bubu", "dudu", "both", "narr") or not ln.get("t"):
                bad_lines += 1
    print("[%s] dialogue ids referenced: %d, missing: %d" % ("OK" if not miss_d else "FAIL", len(wanted_d), len(miss_d)))
    for d in miss_d:
        print("   missing dialogue id: " + d)
    print("[%s] memory ids referenced: %d, missing: %d" % ("OK" if not miss_m else "FAIL", len(wanted_m), len(miss_m)))
    for m in miss_m:
        print("   missing memory id: " + m)
    print("[%s] dialogue line format (%d malformed)" % ("OK" if bad_lines == 0 else "FAIL", bad_lines))
    # Contextual line pools used by scenes/core/BarkDirector.gd.
    barks = _load("res://data/dialogue/barks.json") or {}
    pools = ["fall_bubu", "fall_dudu", "falls_many", "call_bubu", "call_dudu", "piggy", "memory", "progress",
             "slow", "stuck", "idle", "resume", "fast"] + ["ambient_c%d" % (i + 1) for i in range(len(data))]
    miss_p = [q for q in pools if not barks.get(q)]
    bad_b = sum(1 for v in barks.values() for e in v for ln in e if ln.get("s") not in ("bubu", "dudu", "both", "narr") or not ln.get("t"))
    print("[%s] contextual line pools: %d/%d, entries: %d, malformed: %d" % (
        "OK" if not miss_p and bad_b == 0 else "FAIL", len(pools) - len(miss_p), len(pools), sum(len(v) for v in barks.values()), bad_b))
    for q in miss_p:
        print("   missing pool: " + q)
    # Duration: puzzle effort + reading every referenced dialogue once (about 14 chars/s
    # plus a beat per line to press A) + fades and title cards between rooms.
    effort = sum(b.est for b in builders)
    reading = sum(len(ln["t"]) / 14.0 + 1.2 for d in wanted_d if d in dialogues for ln in dialogues[d]) / 60.0
    transitions = len(builders) * 6.0 / 60.0 + len(data) * 0.25
    # Contextual lines: about one per room on average (cooldown 75 s, cap 3 per room).
    entries = [e for v in barks.values() for e in v]
    avg = sum(len(ln["t"]) / 14.0 + 1.2 for e in entries for ln in e) / max(len(entries), 1)
    contextual = len(builders) * 1.0 * avg / 60.0
    total = effort + reading + contextual + transitions
    print("[OK] effort estimate: %.0f min puzzles + %.0f min reading + %.0f min contextual lines + %.0f min transitions = %.0f min"
          % (effort, reading, contextual, transitions, total))
    return dialogues


if __name__ == "__main__":
    main()
