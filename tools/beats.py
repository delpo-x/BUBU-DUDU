"""Reusable puzzle beats. Each lays geometry from tile x on floor surface g, appends the
bot steps that carry both players across it and returns (x_end, g_end).

Design rules (see roomkit docstring for reach numbers):
- Beats that separate the players have no pits or hazards on the waiting side, so a
  fall (which floats the player back to the partner) can never skip the puzzle.
- High ledges are solid pillars (no undersides to bump into while jumping up).
- Only grooved blocks (wall_jump=True) allow Bubu's wall jump.
"""
from roomkit import T, SN, SNArray, V2, Col, px, hexcol

BUBU_HALF = 22 / T
DUDU_HALF = 24 / T
BOOST_H = 2.75     # ledge only reachable by a boosted dismount (176 px)
PULLEY_H = 3.5     # ledge reachable from a pulley pad raised 96 px (224 px)


def _wall_to_ceiling(b, x, w, bottom):
    """Unclimbable wall from the top of the room down to surface `bottom`."""
    b.rock(x, -1, w, bottom + 1)


def _cliff(b, x, w, top):
    """Rock cliff with its top at surface `top`, filling down to the room bottom."""
    b.solid(x, top, w, b.h - top + 0.5, color=b.pal["rock"], name="Cliff")


def _gate(b, x_center, g, ch_list, height=2, latch=True, require_all=True, invert=False, width=1, slide=None):
    props = dict(size=V2(px(width), px(height)), channels=SNArray(ch_list), require_all=require_all, latch=latch)
    if invert:
        props["invert"] = True
    if slide is not None:
        props["slide"] = V2(*slide)
    return b.add("Gate", "Things", (px(x_center), px(g - height / 2)), **props)


def _plate(b, x_center, g, ch, weight=1, width=1.5, hold=0.0, latch=False):
    props = dict(size=V2(px(width), 10.0), channel=SN(ch), required_weight=weight)
    if hold:
        props["hold_time"] = float(hold)
    if latch:
        props["latch"] = True
    return b.add("PressurePlate", "Things", (px(x_center), px(g)), **props)


def _lever(b, x, g, ch, start_on=False):
    props = dict(mode=1, channel=SN(ch))
    if start_on:
        props["start_on"] = True
    return b.add("WallButton", "Things", (px(x), px(g)), name="Lever", **props)


def _button(b, x, g, ch, active=2.5):
    return b.add("WallButton", "Things", (px(x), px(g)), name="Button", mode=0, channel=SN(ch), active_time=float(active))


def memory(b, mid, x, y, collect_steps=None):
    """Floating keepsake at tile (x, y) (center). The bot collects it on its path."""
    b.add("MemoryPickup", "Things", (px(x), px(y)), name="Memory", memory_id=mid)
    b.memories.append(mid)
    if collect_steps:
        for s in collect_steps:
            b.steps.append(s)
    b.step("expect", what="memory", id=mid, within=1.0)


def scatter(b, x0, x1, g, kinds=None, every=3.0):
    """Light decoration on a flat stretch (deterministic per room)."""
    import random
    import zlib
    rng = random.Random(zlib.crc32(("%s:%.2f" % (b.room_id, x0)).encode()))
    kinds = kinds or {1: ["flower", "bush", "grass", "tree", "flower"],
                      2: ["lamp", "fence", "grass", "bush", "window"],
                      3: ["crystal", "mushroom", "grass", "rock", "pine"],
                      4: ["lamp", "pine", "grass", "crystal", "star"]}[b.chapter]
    x = x0 + rng.uniform(0.3, 1.2)
    while x < x1 - 0.4:
        k = rng.choice(kinds)
        if k == "star":
            b.decor(k, x, g - rng.uniform(4, 8), scale=rng.uniform(0.8, 1.4), color=Col(1, 1, 0.85))
        elif k == "tree":
            b.decor(k, x, g, scale=rng.uniform(0.8, 1.1), color=b.pal["leaf"])
        elif k == "pine":
            b.decor(k, x, g, scale=rng.uniform(0.7, 1.0), color=b.pal["leaf"].__class__(*(c * 0.85 for c in (b.pal["leaf"].r, b.pal["leaf"].g, b.pal["leaf"].b))))
        elif k in ("bush", "grass"):
            b.decor(k, x, g, scale=rng.uniform(0.7, 1.2), color=b.pal["leaf"], seed=rng.randint(0, 99))
        elif k == "flower":
            b.decor(k, x, g, scale=rng.uniform(0.8, 1.2), color=Col(*rng.choice([(1, .6, .7), (1, .85, .4), (.75, .65, 1)])))
        elif k == "crystal":
            b.decor(k, x, g, scale=rng.uniform(0.7, 1.2), color=hexcol("b7a6f0"), seed=rng.randint(0, 99))
        elif k == "mushroom":
            b.decor(k, x, g, scale=rng.uniform(0.8, 1.2), color=hexcol("e8907a"))
        elif k == "lamp":
            b.decor(k, x, g, scale=1.0)
        elif k == "fence":
            b.decor(k, x, g, scale=0.8, color=hexcol("c9a77c"))
        elif k == "window":
            b.decor("house", x, g, scale=rng.uniform(0.7, 0.9), color=hexcol(rng.choice(["e7c9a9", "d9b8c4", "c4d2b0"])))
        elif k == "rock":
            b.decor(k, x, g, scale=rng.uniform(0.6, 1.0), color=b.pal["rock"])
        x += every * rng.uniform(0.7, 1.4)


# --- Room frame -----------------------------------------------------------------------------

def start(b, g, x=1.0, length=4):
    """Left wall + starting floor with both spawns."""
    b.rock(0, -1, 1, b.h + 1)
    b.ground(x, x + length, g)
    b.spawn(x + 1.0, x + 1.9, g)
    scatter(b, x, x + length, g)
    return x + length, g


def flat(b, x, g, n=4, deco=True):
    b.ground(x, x + n, g)
    if deco:
        scatter(b, x, x + n, g)
    b.walk2(x + n - 1.2, x + n - 0.7)
    return x + n, g


def exit_door(b, x, g, n=5):
    b.ground(x, x + n, g)
    b.add("Exit", "Things", (px(x + n / 2), px(g)))
    b.rock(x + n, -1, 1, b.h + 1)
    b.has_exit = True
    b.walk2(x + n / 2 - 0.25, x + n / 2 + 0.25)
    b.step("wait_complete", timeout=3.0)
    return x + n, g


def sign(b, x, g, dialogue, kind="post"):
    b.add("Sign", "Things", (px(x), px(g)), dialogue=SN(dialogue), kind=kind)
    b.dialogues.append(dialogue)


def talk(b, x, g, dialogue, both=True, width=2, height=4):
    """Dialogue played the first time the players reach tile x."""
    b.add("DialogueTrigger", "Things", (px(x), px(g - height / 2)), size=V2(px(width), px(height)),
          dialogue=SN(dialogue), require_both=both)
    b.dialogues.append(dialogue)


def checkpoint(b, x, g):
    b.add("Checkpoint", "Things", (px(x), px(g)))


# --- Chapter 1: movement, piggyback, plates, gates, call, cozy ------------------------------

def steps_up(b, x, g, k=2, w=2):
    for i in range(1, k + 1):
        x0 = x + (i - 1) * w
        b.ground(x0, x0 + w, g - i)
        b.walk2(x0 - 0.55, x0 - 0.5)
        b.jump(1, x0 + w / 2 - 0.2)
        b.jump(2, x0 + w / 2 + 0.2)
    scatter(b, x + (k - 1) * w, x + k * w, g - k)
    return x + k * w, g - k


def steps_down(b, x, g, k=2, w=2):
    for i in range(1, k + 1):
        b.ground(x + (i - 1) * w, x + i * w, g + i)
    b.walk2(x + k * w - 0.9, x + k * w - 0.5)
    return x + k * w, g + k


def gap(b, x, g, w=2.0, g2=None, hazard=True):
    """A pit to jump over (both cross, so falling is harmless)."""
    g2 = g if g2 is None else g2
    b.ground(x, x + 1, g)
    b.ground(x + 1 + w, x + 3 + w, g2)
    if hazard:
        b.pit_hazard(x + 1, x + 1 + w)
    for p, off in ((1, -0.45), (2, -0.42)):
        b.walk(p, x + 1 + off)
        b.jump(p, x + 1 + w + 0.8 + (0.3 if p == 2 else 0.0))
    return x + 3 + w, g2


def boost_gate(b, x, g, mem=None):
    """Pillar only a boosted dismount reaches; its lever opens the door below a wall."""
    c = b.ch()
    b.ground(x, x + 10, g)
    # A slab over a low tunnel: the tunnel leads to the door, the slab top to the lever.
    b.rock(x + 4, g - BOOST_H, 2, BOOST_H - 2)
    _wall_to_ceiling(b, x + 6, 1, g - 2)
    _gate(b, x + 6.5, g, [c])
    _lever(b, x + 5.3, g - BOOST_H, c)
    scatter(b, x, x + 3.5, g)
    b.walk2(x + 3.2, x + 4 - DUDU_HALF - 0.07)
    b.step("piggy", p=1)
    b.step("dismount", p=1, x=px(x + 5.0), top=px(g - BOOST_H))
    if mem:
        memory(b, mem, x + 4.6, g - BOOST_H - 0.6)
    b.step("interact", p=1)
    b.step("wait_ch", ch=c)
    b.walk(1, x + 3.0)
    b.walk2(x + 8.4, x + 8.9)
    return x + 10, g


def two_plates(b, x, g, bridge=False):
    """Hold-the-door: a plate on each side of a door, both on the same channel."""
    c = b.ch()
    if bridge:
        # Trench with a fading bridge; the trench has a way back up on the left.
        b.ground(x, x + 2, g)
        b.ground(x + 2, x + 6, g + 3)
        b.solid(x + 2, g + 1.5, 1, 1.5, color=b.pal["rock"])
        b.ground(x + 6, x + 10, g)
        b.add("Gate", "Things", (px(x + 4), px(g) + 12), size=V2(px(4), 24.0), channels=SNArray([c]),
              invert=True, latch=False, color=hexcol("c9b28f"))
        _plate(b, x + 1.0, g, c)
        _plate(b, x + 7.5, g, c)
    else:
        b.ground(x, x + 11, g)
        _wall_to_ceiling(b, x + 5, 1, g - 2)
        _gate(b, x + 5.5, g, [c], latch=False)
        _plate(b, x + 2.0, g, c)
        _plate(b, x + 8.5, g, c)
    far = 7.5 if bridge else 8.5
    near = 1.0 if bridge else 2.0
    b.walk(2, x + near)
    b.step("wait_ch", ch=c)
    b.step("wait", s=0.4)
    b.walk(1, x + far)
    b.step("wait", s=0.2)
    b.walk(2, x + far + 1.0)
    b.walk(1, x + far + 1.4)
    return x + (10 if bridge else 11), g


def heavy_plate(b, x, g):
    """Plate needing both weights (3); the door latches open."""
    c = b.ch()
    b.ground(x, x + 10, g)
    _plate(b, x + 3, g, c, weight=3, width=2.5)
    _wall_to_ceiling(b, x + 6, 1, g - 2)
    _gate(b, x + 6.5, g, [c])
    scatter(b, x, x + 2, g)
    b.walk2(x + 2.8, x + 3.2)
    b.step("wait_ch", ch=c)
    b.step("wait", s=0.4)
    b.walk2(x + 8.4, x + 8.9)
    return x + 10, g


def cozy(b, x, g, dialogue="", mem="", kind="bench", required=True):
    """A warm spot where both hug (each taps Y). Required spots open the way on."""
    c = b.ch() if required else ""
    n = 10 if required else 7
    b.ground(x, x + n, g)
    props = dict(kind=kind, size=V2(px(3.4), px(2)))
    if dialogue:
        props["dialogue"] = SN(dialogue)
        b.dialogues.append(dialogue)
    if mem:
        props["memory_id"] = mem
        b.memories.append(mem)
    if c:
        props["channel"] = SN(c)
    b.add("CozySpot", "Things", (px(x + 3), px(g)), **props)
    if required:
        _wall_to_ceiling(b, x + 6.5, 1, g - 2)
        _gate(b, x + 7, g, [c])
    b.decor("lamp", x + 0.8, g)
    b.walk2(x + 2.7, x + 3.3)
    b.step("hug")
    if mem:
        b.step("expect", what="memory", id=mem, within=1.0)
    if required:
        b.step("wait_ch", ch=c)
        b.step("wait", s=0.4)
    b.walk2(x + n - 1.4, x + n - 0.9)
    return x + n, g


def call_lesson(b, x, g):
    """A fence only a boost clears; once over, Bubu holds Y to call Dudu across."""
    b.ground(x, x + 11, g)
    b.rock(x + 4, g - BOOST_H, 1, BOOST_H)
    b.walk2(x + 3.2, x + 4 - DUDU_HALF - 0.07)
    b.step("piggy", p=1)
    b.step("dismount", p=1, x=px(x + 4.5), top=px(g - BOOST_H))
    b.walk(1, x + 7.0)
    b.step("call", p=1)
    b.step("settle")
    b.walk2(x + 9.2, x + 9.7)
    return x + 11, g


# --- Chapter 2: crates, pulleys, levers, platforms, wall jumps, fragile floors ---------------

def _crate(b, x, g, heavy=False):
    size = 48 if heavy else 40
    return b.add("CarryableItem", "Things", (px(x), px(g) - size / 2 - 1), name="HeavyCrate" if heavy else "Crate",
                 size=V2(float(size), float(size)), weight=2 if heavy else 1,
                 color=hexcol("8c6a4a") if heavy else hexcol("c49464"))


def crate_ledge(b, x, g, up=BOOST_H):
    """Carry a crate under a ledge and use it as a step (both climb)."""
    b.ground(x, x + 5, g)
    crate = _crate(b, x + 2, g)
    b.ground(x + 5, x + 9, g - up)
    face = px(x + 5)
    b.walk(1, x + 2 - 0.6)
    b.step("pickup", p=1)
    b.step("walk", p=1, x=face - 70)
    b.step("face", p=1, dir=1)
    b.step("drop", p=1)
    b.step("wait", s=0.5)
    for p in (1, 2):
        b.step("walk", p=p, x_node=crate, x_dx=-62 - (4 if p == 2 else 0))
        b.step("jump", p=p, x_node=crate, x_dx=0 if p == 1 else -2, top=px(g) - 40, land_tol=26)
        b.step("jump", p=p, x=px(x + 6.2 + 0.4 * (p - 1)), top=px(g - up))
    scatter(b, x + 5.3, x + 9, g - up)
    return x + 9, g - up


def heavy_crate_plate(b, x, g):
    """Only Dudu can lift the heavy crate; left on the plate it holds the door open."""
    c = b.ch()
    b.ground(x, x + 12, g)
    crate = _crate(b, x + 2, g, heavy=True)
    _plate(b, x + 6, g, c, weight=2)
    _wall_to_ceiling(b, x + 8.5, 1, g - 2)
    _gate(b, x + 9, g, [c], latch=False)
    b.walk(2, x + 2 - 0.75)
    b.step("pickup", p=2)
    b.step("walk", p=2, x=px(x + 6) - 54)
    b.step("face", p=2, dir=1)
    b.step("drop", p=2)
    b.step("wait_ch", ch=c, timeout=4.0)
    b.step("wait", s=0.5)
    for p in (1, 2):
        b.walk(p, x + 6 - 0.95)
        b.jump(p, x + 7.3)
    b.walk2(x + 10.4, x + 10.9)
    return x + 12, g


def crate_plate_door(b, x, g):
    """A plate holds a door open only while pressed: a small crate stands in for a player."""
    c = b.ch()
    b.ground(x, x + 12, g)
    crate = _crate(b, x + 1.5, g)
    _plate(b, x + 6, g, c, weight=1)
    _wall_to_ceiling(b, x + 8.5, 1, g - 2)
    _gate(b, x + 9, g, [c], latch=False)
    b.walk(1, x + 1.5 - 0.6)
    b.step("pickup", p=1)
    b.step("walk", p=1, x=px(x + 6) - 48)
    b.step("face", p=1, dir=1)
    b.step("drop", p=1)
    b.step("wait_ch", ch=c, timeout=4.0)
    b.step("wait", s=0.5)
    for p in (1, 2):
        b.walk(p, x + 6 - 0.9)
        b.jump(p, x + 7.3)
    b.walk2(x + 10.4, x + 10.9)
    return x + 12, g


def boost_memory(b, x, g, mem):
    """Optional keepsake on a slab only a boosted dismount reaches (walk under it otherwise)."""
    b.ground(x, x + 8, g)
    b.rock(x + 3.5, g - BOOST_H, 2, BOOST_H - 2)
    memory(b, mem, x + 4.5, g - BOOST_H - 0.6)
    b.steps.pop()  # collected by the steps below
    b.walk2(x + 2.7, x + 3.5 - DUDU_HALF - 0.07)
    b.step("piggy", p=1)
    b.step("dismount", p=1, x=px(x + 4.5), top=px(g - BOOST_H))
    b.step("expect", what="memory", id=mem, within=1.0)
    b.walk(1, x + 6.2)
    b.walk2(x + 6.6, x + 7.1)
    scatter(b, x + 5, x + 8, g)
    return x + 8, g


def pulley(b, x, g, mem=None):
    """Dudu's weight on one pad lifts Bubu on the other up to a lever above a tunnel door."""
    c = b.ch()
    b.ground(x, x + 1, g)
    b.ground(x + 1, x + 2.75, g + 2)
    b.ground(x + 2.75, x + 4.75, g)
    b.ground(x + 4.75, x + 6.5, g + 2)
    b.ground(x + 6.5, x + 12, g)
    b.rock(x + 6.5, g - PULLEY_H, 3, PULLEY_H - 2)
    _gate(b, x + 8.0, g, [c])
    _lever(b, x + 7.3, g - PULLEY_H, c)
    b.add("BalancePair", "Things", (px(x + 3.75), px(g) + 10), name="Pulley", mode=0,
          pad_size=V2(112.0, 20.0), pad_a=V2(-120.0, 0.0), pad_b=V2(120.0, 0.0), travel=96.0,
          px_per_weight=96.0, speed=150.0)
    b.walk2(x + 0.5, x + 0.3)
    b.jump(1, x + 3.75)
    b.walk(1, x + 5.625)
    b.step("wait", s=0.9)
    b.jump(2, x + 1.875, top=g - 1.5)
    b.step("wait", s=1.5)
    b.jump(1, x + 7.6, top=g - PULLEY_H)
    if mem:
        memory(b, mem, x + 8.8, g - PULLEY_H - 0.6, [{"op": "walk", "p": 1, "x": px(x + 8.8)}])
        b.walk(1, x + 7.5)
    b.step("interact", p=1)
    b.step("wait_ch", ch=c)
    b.jump(2, x + 3.6, top=g)
    b.step("wait", s=1.0)
    b.walk(2, x + 5.625)
    b.step("wait", s=0.9)
    b.jump(2, x + 7.0, top=g)
    b.walk2(x + 10.4, x + 10.9)
    return x + 12, g


def moving_cross(b, x, g, span=6):
    """A wide pit crossed together on a ferry platform."""
    b.ground(x, x + 1.5, g)
    b.pit_hazard(x + 1.5, x + 1.5 + span)
    b.ground(x + 1.5 + span, x + 4.5 + span, g)
    start_c = x + 2.5
    path = b.add("MovingPlatform", "Things", (px(start_c), px(g) + 10), name="Ferry",
                 size=V2(128.0, 20.0), travel=V2(px(span - 2), 0.0), speed=95.0, pause_time=1.4)
    end_c = start_c + span - 2
    path_rel = path
    b.walk2(x + 0.9, x + 0.6)
    b.step("wait_near", node=path_rel, x=px(start_c), y=px(g) + 10, tol=3, arrive=True, timeout=20)
    b.walk2(start_c - 0.2, start_c + 0.25, timeout=3)
    b.step("wait_near", node=path_rel, x=px(end_c), y=px(g) + 10, tol=3, arrive=True, timeout=20)
    b.walk2(x + 1.5 + span + 1.2, x + 1.5 + span + 1.7, timeout=4)
    return x + 4.5 + span, g


def elevator(b, x, g, height=4):
    """Plate below and plate above both raise the lift: take turns to ride it up."""
    c = b.ch()
    b.ground(x, x + 6, g)
    _plate(b, x + 1.5, g, c)
    lift = b.add("MovingPlatform", "Things", (px(x + 5), px(g) + 10), name="Lift", size=V2(128.0, 20.0),
                 travel=V2(0.0, -px(height)), speed=120.0, mode=1, channels=SNArray([c]))
    _cliff(b, x + 6, 5, g - height)
    _plate(b, x + 7.5, g - height, c)
    top = g - height
    up_t = height * T / 120 + 0.6
    b.walk(1, x + 5)
    b.walk(2, x + 1.5)
    b.step("wait", s=up_t)
    b.walk(1, x + 7.5)
    b.walk(2, x + 3.4)
    b.walk(1, x + 9.3)
    b.step("wait", s=up_t)
    b.walk(2, x + 5)
    b.walk(1, x + 7.5)
    b.step("wait", s=up_t)
    b.walk(2, x + 8.6)
    b.walk(1, x + 9.6)
    scatter(b, x + 8, x + 11, top)
    return x + 11, top


def fragile_drop(b, x, g, depth=3):
    """Cracked planks hold Bubu but give way under Dudu: the way on is down."""
    lower = g + depth
    b.solid(x, g, 2, 1, color=b.pal["rock"])
    b.add("FragileFloor", "Things", (px(x + 3), px(g) + 10), size=V2(128.0, 20.0), break_weight=2)
    b.solid(x + 4, g, 1.5, 1, color=b.pal["rock"])
    _wall_to_ceiling(b, x + 5.5, 1, lower - 2)
    b.ground(x, x + 10, lower)
    b.walk(2, x + 3)
    b.walk(1, x + 3.2)
    b.walk2(x + 8.2, x + 8.7)
    scatter(b, x + 6.5, x + 10, lower)
    return x + 10, lower


def walljump_shaft(b, x, g, height=6, mem=None):
    """Bubu climbs a grooved shaft by wall jumps to a lever that opens Dudu's door."""
    c = b.ch()
    b.ground(x, x + 12, g)
    # The far wall is 2 tiles taller: the last kick off it arcs onto the lever wall.
    b.rock(x + 3, g - height - 2, 1, height + 0.5, wall_jump=True)
    b.rock(x + 5.5, g - height, 1, height - 2, wall_jump=True)
    _gate(b, x + 6, g, [c])
    _lever(b, x + 6.0, g - height, c)
    b.walk(1, x + 4.75)
    b.step("walljump", p=1, top=px(g - height), x=px(x + 6.0), dir=1, timeout=10)
    if mem:
        memory(b, mem, x + 6.0, g - height - 1.5)
    b.step("interact", p=1)
    b.step("wait_ch", ch=c)
    b.walk(1, x + 7.6)
    b.walk2(x + 9.4, x + 9.9)
    return x + 12, g


# --- Chapter 3: seesaw, bounce, timed and co-op buttons, vines, wind ---------------------------

def seesaw(b, x, g, mem=None, crate_launch=False):
    """Dudu lands on one end and launches Bubu to a lever on a high slab.
    crate_launch: reversed - Bubu, carrying a crate (weight 2), launches Dudu."""
    c = b.ch()
    slab_top = g - 5
    b.ground(x, x + 1.125, g)
    b.ground(x + 1.125, x + 2.875, g + 1.25)
    b.ground(x + 2.875, x + 4.125, g)
    b.ground(x + 4.125, x + 5.875, g + 1.25)
    b.ground(x + 5.875, x + 12, g)
    b.rock(x + 6.5, slab_top, 3, 1.5)
    _gate(b, x + 8.0, g, [c], height=3.5)
    _lever(b, x + 7.4, slab_top, c)
    b.add("BalancePair", "Things", (px(x + 3.5), px(g) + 10), name="Seesaw", mode=1,
          pad_size=V2(112.0, 20.0), pad_a=V2(-96.0, 0.0), pad_b=V2(96.0, 0.0), travel=48.0, speed=160.0)
    flyer, lander = (2, 1) if crate_launch else (1, 2)
    if crate_launch:
        crate = _crate(b, x + 0.4, g)
        b.walk(1, x + 0.4 - 0.6)
        b.step("pickup", p=1)
    b.walk(flyer, x + 0.55)
    b.jump(flyer, x + 3.5)
    b.jump(flyer, x + 5.0, top=g - 0.75, nocheck=True)
    b.step("wait", s=0.6)
    b.walk(lander, x + 0.55)
    b.jump(lander, x + 2.0, top=g - 0.75)
    b.step("fly", p=flyer, x=px(x + 7.5), top=px(slab_top), timeout=4)
    if mem:
        memory(b, mem, x + 8.7, slab_top - 0.6, [{"op": "walk", "p": flyer, "x": px(x + 8.7)}])
        b.walk(flyer, x + 7.5)
    b.step("interact", p=flyer)
    b.step("wait_ch", ch=c)
    b.jump(lander, x + 3.5, top=g)
    b.step("wait", s=0.5)
    b.jump(lander, x + 5.0, top=g - 0.75)
    b.step("wait", s=0.5)
    b.jump(lander, x + 6.2, top=g)
    if crate_launch:
        # Leave the crate behind on the seesaw.
        b.step("face", p=1, dir=-1)
        b.step("drop", p=1)
        b.step("wait", s=0.4)
    b.walk2(x + 10.4, x + 10.9)
    return x + 12, g


def bounce_up(b, x, g, height=4):
    """Springy mushroom up to a high ledge (both bounce)."""
    b.ground(x, x + 4.2, g)
    pad_x = x + 3.0
    b.add("BouncePad", "Things", (px(pad_x), px(g) - 9), size=V2(72.0, 18.0), bounce_speed=1100.0)
    _cliff(b, x + 4.2, 4, g - height)
    top = g - height
    for p in (1, 2):
        b.walk(p, pad_x - 1.0)
        b.step("bounce", p=p, via=px(pad_x), x=px(x + 5.4 + 0.4 * (p - 1)), top=px(top), timeout=5)
    scatter(b, x + 5, x + 8.2, top)
    return x + 8.2, top


def timed_pair(b, x, g, active=2.5):
    """Two timed buttons too far apart for one: press them together."""
    c1, c2 = b.ch(), b.ch()
    b.ground(x, x + 17, g)
    _button(b, x + 1.5, g, c1, active)
    _button(b, x + 12.5, g, c2, active)
    _wall_to_ceiling(b, x + 14, 1, g - 2)
    _gate(b, x + 14.5, g, [c1, c2])
    scatter(b, x + 3, x + 11, g)
    b.walk2(x + 1.5, x + 12.5)
    b.step("interact", p=1)
    b.step("interact", p=2)
    b.step("wait", s=0.6)
    b.walk2(x + 15.6, x + 16.1)
    return x + 17, g


def vine_climb(b, x, g, height=5):
    """A vine up a cliff (both climb)."""
    b.ground(x, x + 5, g)
    _cliff(b, x + 5, 4, g - height)
    vx = x + 5 - 30 / T
    b.add("Vine", "Things", (px(vx), px(g - height / 2)), size=V2(28.0, px(height)))
    top = g - height
    for p in (1, 2):
        b.walk(p, vx)
        b.step("climb", p=p, top=px(top), x=px(x + 6 + 0.4 * (p - 1)), timeout=8)
    scatter(b, x + 6.5, x + 9, top)
    return x + 9, top


def wind_lift(b, x, g, height=5):
    """A fan powered by a plate lifts one player to a lever that keeps it running."""
    c1, c2 = b.ch(), b.ch()
    b.ground(x, x + 5.25, g)
    _plate(b, x + 1.5, g, c1)
    zone_top = px(g - height) - 16
    zone_h = px(g) - zone_top
    b.add("WindZone", "Things", (px(x + 4.5), zone_top + zone_h / 2), size=V2(96.0, zone_h),
          channels=SNArray([c1, c2]), require_all=False)
    _cliff(b, x + 5.25, 4, g - height)
    _lever(b, x + 6.3, g - height, c2)
    top = g - height
    b.walk(2, x + 1.5)
    b.step("wait_ch", ch=c1)
    b.step("fly", p=1, via=px(x + 4.5), x=px(x + 6.0), top=px(top), timeout=6)
    b.walk(1, x + 6.3)
    b.step("interact", p=1)
    b.step("wait_ch", ch=c2)
    b.step("fly", p=2, via=px(x + 4.5), x=px(x + 6.8), top=px(top), timeout=6)
    b.walk2(x + 7.5, x + 8.0)
    return x + 9.25, top
