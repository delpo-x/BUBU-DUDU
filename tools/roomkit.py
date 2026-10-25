"""Room DSL: builds Room_XX.tscn files plus a bot solution for each room.

Units: tiles of 64 px. y grows downwards; a "surface" g is the y (in tiles) of a floor top.
Every beat function receives the builder, the x (tiles) where it starts and the floor
surface g, lays its own geometry, appends bot steps that move both players across it
and returns (x_end, g_end). Players enter a beat standing somewhere left of x.

Body sizes: Bubu 44x58 (weight 1, wall jump), Dudu 48x62 (weight 2, strong).
Reach (px): jump 150, boosted dismount ~200, crate step +40, bounce 1100 -> ~290,
seesaw launch by Dudu -> ~480, pulley +96 per weight difference.
"""
import json
import os

T = 64
BUBU_H = 58
DUDU_H = 62
BUBU_W = 44
DUDU_W = 48


def px(v):
    return round(v * T, 2)


# --- Godot value formatting -----------------------------------------------------------

def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        s = repr(round(v, 3))
        return s if "." in s or "e" in s else s + ".0"
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    if isinstance(v, SN):
        return '&"%s"' % v.s
    if isinstance(v, V2):
        return "Vector2(%s, %s)" % (fmt(float(v.x)), fmt(float(v.y)))
    if isinstance(v, Col):
        return "Color(%s, %s, %s, %s)" % tuple(fmt(float(c)) for c in (v.r, v.g, v.b, v.a))
    if isinstance(v, R2):
        return "Rect2(%s, %s, %s, %s)" % tuple(fmt(float(c)) for c in (v.x, v.y, v.w, v.h))
    if isinstance(v, SNArray):
        return "Array[StringName]([%s])" % ", ".join('&"%s"' % s for s in v.items)
    raise TypeError(repr(v))


class SN:
    def __init__(self, s):
        self.s = s


class SNArray:
    def __init__(self, items):
        self.items = list(items)


class V2:
    def __init__(self, x, y):
        self.x, self.y = x, y


class Col:
    def __init__(self, r, g, b, a=1.0):
        self.r, self.g, self.b, self.a = r, g, b, a


class R2:
    def __init__(self, x, y, w, h):
        self.x, self.y, self.w, self.h = x, y, w, h


def hexcol(h, a=1.0):
    h = h.lstrip("#")
    return Col(int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, a)


SCRIPTS = {
    "Room": "res://scenes/core/Room.gd",
    "Block": "res://scenes/core/WhiteboxBlock.gd",
    "PressurePlate": "res://scenes/components/PressurePlate.gd",
    "WallButton": "res://scenes/components/WallButton.gd",
    "Gate": "res://scenes/components/Gate.gd",
    "MovingPlatform": "res://scenes/components/MovingPlatform.gd",
    "BalancePair": "res://scenes/components/BalancePair.gd",
    "CarryableItem": "res://scenes/components/CarryableItem.gd",
    "CozySpot": "res://scenes/components/CozySpot.gd",
    "Exit": "res://scenes/components/Exit.gd",
    "Hazard": "res://scenes/components/Hazard.gd",
    "FragileFloor": "res://scenes/components/FragileFloor.gd",
    "BouncePad": "res://scenes/components/BouncePad.gd",
    "WindZone": "res://scenes/components/WindZone.gd",
    "Vine": "res://scenes/components/Vine.gd",
    "MemoryPickup": "res://scenes/components/MemoryPickup.gd",
    "DialogueTrigger": "res://scenes/components/DialogueTrigger.gd",
    "Sign": "res://scenes/components/Sign.gd",
    "CallBlockZone": "res://scenes/components/CallBlockZone.gd",
    "Checkpoint": "res://scenes/components/Checkpoint.gd",
    "Decor": "res://scenes/components/Decor.gd",
}
BASE_TYPES = {
    "Block": "StaticBody2D", "PressurePlate": "Area2D", "WallButton": "Node2D", "Gate": "StaticBody2D",
    "MovingPlatform": "AnimatableBody2D", "BalancePair": "Node2D", "CarryableItem": "RigidBody2D",
    "CozySpot": "Area2D", "Exit": "Area2D", "Hazard": "Area2D", "FragileFloor": "StaticBody2D",
    "BouncePad": "StaticBody2D", "WindZone": "Area2D", "Vine": "Area2D", "MemoryPickup": "Area2D",
    "DialogueTrigger": "Area2D", "Sign": "Node2D", "CallBlockZone": "Node2D", "Checkpoint": "Area2D",
    "Decor": "Node2D",
}

# Chapter palettes: ground, accent block, backdrop name, background color.
PALETTES = {
    1: dict(ground=hexcol("8fb77c"), rock=hexcol("a0a58f"), bg=hexcol("d9eef0"), backdrop="meadow", leaf=hexcol("6fa865")),
    2: dict(ground=hexcol("b39a86"), rock=hexcol("9a8f99"), bg=hexcol("f3e2cf"), backdrop="town", leaf=hexcol("7fa070")),
    3: dict(ground=hexcol("8a8fae"), rock=hexcol("7c7fa0"), bg=hexcol("cfd8f0"), backdrop="sky", leaf=hexcol("7fb3a0")),
    4: dict(ground=hexcol("6f6a8c"), rock=hexcol("5d5878"), bg=hexcol("2e2c48"), backdrop="night", leaf=hexcol("5f8f7a")),
}


class Node:
    def __init__(self, kind, name, parent, pos, props):
        self.kind, self.name, self.parent, self.pos, self.props = kind, name, parent, pos, props


class Builder:
    def __init__(self, room_id, chapter, w, h, est, hint, intro="", call=False, backdrop=None,
                 seed=1, min_zoom=0.55, max_zoom=1.0):
        self.room_id = room_id
        self.chapter = chapter
        self.w, self.h = w, h
        self.est, self.hint, self.intro, self.call = est, hint, intro, call
        self.pal = PALETTES[chapter]
        self.backdrop = backdrop or self.pal["backdrop"]
        self.seed = seed
        self.min_zoom, self.max_zoom = min_zoom, max_zoom
        self.nodes = []
        self.names = {}
        self.steps = []
        self.spawns = {}
        self.memories = []
        self.dialogues = []
        self.channel_n = 0
        self.has_exit = False
        self.folder = "ch%d" % chapter

    # -- naming / channels
    def uname(self, base):
        n = self.names.get(base, 0) + 1
        self.names[base] = n
        return base if n == 1 else "%s%d" % (base, n)

    def ch(self, base="c"):
        self.channel_n += 1
        return "%s%d" % (base, self.channel_n)

    def add(self, kind, parent, pos, /, name=None, **props):
        name = self.uname(name or kind)
        self.nodes.append(Node(kind, name, parent, pos, props))
        return parent + "/" + name

    # -- geometry (tiles)
    def solid(self, x, y, w, h, color=None, one_way=False, wall_jump=False, name="Block"):
        c = color or self.pal["ground"]
        props = dict(size=V2(px(w), px(h)), color=c)
        if one_way:
            props["one_way"] = True
        if wall_jump:
            props["wall_jump"] = True
        return self.add("Block", "Geometry", (px(x + w / 2), px(y + h / 2)), name=name, **props)

    def ground(self, x0, x1, g, color=None):
        """Floor with its top at surface g, filling down to the room bottom."""
        if x1 <= x0:
            return
        self.solid(x0, g, x1 - x0, self.h - g + 0.5, color=color, name="Ground")

    def rock(self, x, y, w, h, **kw):
        return self.solid(x, y, w, h, color=self.pal["rock"], name="Rock", **kw)

    def pit_hazard(self, x0, x1):
        """Thorns at the bottom of a bottomless pit (visual; falling still sends home)."""
        self.add("Hazard", "Things", (px((x0 + x1) / 2), px(self.h) - 12), size=V2(px(x1 - x0), 24.0), kind="thorns")

    def decor(self, kind, x, g, scale=1.0, color=None, seed=0):
        props = dict(kind=kind, scale_factor=float(scale), seed_value=seed)
        if color is not None:
            props["color"] = color
        self.add("Decor", "Decor", (px(x), px(g)), **props)

    # -- spawns
    def spawn(self, x1, x2, g):
        self.spawns[1] = (px(x1), px(g) - BUBU_H / 2 - 2)
        self.spawns[2] = (px(x2), px(g) - DUDU_H / 2 - 2)

    # -- bot steps (pixels)
    def step(self, op, **kw):
        d = {"op": op}
        d.update(kw)
        self.steps.append(d)

    def walk(self, p, x, **kw):
        self.step("walk", p=p, x=px(x), **kw)

    def walk2(self, x1, x2, **kw):
        self.step("walk2", x1=px(x1), x2=px(x2), **kw)

    def jump(self, p, x, top=None, **kw):
        d = dict(p=p, x=px(x))
        if top is not None:
            d["top"] = px(top)
        d.update(kw)
        self.step("jump", **d)

    # -- output
    def tscn(self):
        used = ["Room"] + sorted({n.kind for n in self.nodes})
        ids = {k: "%d_%s" % (i + 1, k.lower()) for i, k in enumerate(used)}
        out = ["[gd_scene load_steps=%d format=3]" % (len(used) + 1), ""]
        for k in used:
            out.append('[ext_resource type="Script" path="%s" id="%s"]' % (SCRIPTS[k], ids[k]))
        out.append("")
        name = "Room_" + self.room_id.split("_r")[-1]
        out.append('[node name="%s" type="Node2D"]' % name)
        out.append('script = ExtResource("%s")' % ids["Room"])
        room_props = dict(room_id=SN(self.room_id), bounds=R2(0.0, 0.0, float(px(self.w)), float(px(self.h))),
                          background_color=self.pal["bg"], backdrop=self.backdrop, backdrop_seed=self.seed,
                          call_allowed=self.call, camera_min_zoom=float(self.min_zoom), camera_max_zoom=float(self.max_zoom),
                          intro_dialogue=SN(self.intro), hint_text=self.hint, est_minutes=float(self.est))
        for k, v in room_props.items():
            out.append("%s = %s" % (k, fmt(v)))
        out.append("")
        for group in ("Spawns", "Decor", "Geometry", "Things"):
            out.append('[node name="%s" type="Node2D" parent="."]' % group)
            out.append("")
        for i in (1, 2):
            x, y = self.spawns[i]
            out.append('[node name="P%d" type="Marker2D" parent="Spawns"]' % i)
            out.append("position = %s" % fmt(V2(float(x), float(y))))
            out.append("")
        order = {"Decor": 0, "Geometry": 1, "Things": 2}
        for n in sorted(self.nodes, key=lambda n: order.get(n.parent.split("/")[0], 3)):
            out.append('[node name="%s" type="%s" parent="%s"]' % (n.name, BASE_TYPES[n.kind], n.parent))
            out.append("position = %s" % fmt(V2(float(n.pos[0]), float(n.pos[1]))))
            out.append('script = ExtResource("%s")' % ids[n.kind])
            for k, v in n.props.items():
                out.append("%s = %s" % (k, fmt(v)))
            out.append("")
        return "\n".join(out)

    def validate(self):
        assert self.h * T <= 1280, "%s: room too tall" % self.room_id
        assert 1 in self.spawns and 2 in self.spawns, "%s: missing spawns" % self.room_id
        assert self.has_exit, "%s: missing exit" % self.room_id
        assert self.hint, "%s: missing hint" % self.room_id
        assert self.steps and self.steps[-1]["op"] == "wait_complete", "%s: solution must end at the exit" % self.room_id

    def write(self, root):
        self.validate()
        ch_dir = os.path.join(root, "scenes", "rooms", self.folder)
        os.makedirs(ch_dir, exist_ok=True)
        fname = "Room_%s.tscn" % self.room_id.split("_r")[-1]
        with open(os.path.join(ch_dir, fname), "w", encoding="utf-8", newline="\n") as f:
            f.write(self.tscn())
        sol_dir = os.path.join(root, "tests", "solutions")
        os.makedirs(sol_dir, exist_ok=True)
        with open(os.path.join(sol_dir, self.room_id + ".json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump({"room": self.room_id, "path": "res://scenes/rooms/%s/%s" % (self.folder, fname), "steps": self.steps, "memories": self.memories,
                       "dialogues": self.dialogues}, f, indent=1)
        return "res://scenes/rooms/%s/%s" % (self.folder, fname)
