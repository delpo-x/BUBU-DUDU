"""Generates project.godot (input map, autoloads, layers). Run: python -I tools/gen_project.py project.godot"""
import sys
out = sys.argv[1]

def key(phys):
    return ('Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,'
            '"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,'
            '"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":%d,"key_label":0,'
            '"unicode":0,"location":0,"echo":false,"script":null)' % phys)

def btn(dev, idx):
    return ('Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"",'
            '"device":%d,"button_index":%d,"pressure":0.0,"pressed":false,"script":null)' % (dev, idx))

def axis(dev, ax, val):
    return ('Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"",'
            '"device":%d,"axis":%d,"axis_value":%.1f,"script":null)' % (dev, ax, val))

# Godot key codes (physical positions, US layout reference)
K = dict(A=65, D=68, W=87, S=83, E=69, Q=81, R=82, SPACE=32, PERIOD=46, SLASH=47,
         ENTER=4194309, KP_ENTER=4194310, LEFT=4194319, ESC=4194305, BACKSPACE=4194308, F5=4194336, UP=4194320, RIGHT=4194321, DOWN=4194322)
# Joypad: A=0 B=1 X=2 Y=3 BACK=4 DPAD_UP=11 DOWN=12 LEFT=13 RIGHT=14; left stick X=0 Y=1
kb = {
    1: dict(left=[K["A"]], right=[K["D"]], up=[K["W"]], down=[K["S"]],
            jump=[K["SPACE"]], interact=[K["E"]], assist=[K["Q"]]),
    2: dict(left=[K["LEFT"]], right=[K["RIGHT"]], up=[K["UP"]], down=[K["DOWN"]],
            jump=[K["ENTER"], K["KP_ENTER"]], interact=[K["PERIOD"]], assist=[K["SLASH"]]),
}
actions = []
for p in (1, 2):
    dev = p - 1
    pad = dict(left=[axis(dev, 0, -1.0), btn(dev, 13)], right=[axis(dev, 0, 1.0), btn(dev, 14)],
               up=[axis(dev, 1, -1.0), btn(dev, 11)], down=[axis(dev, 1, 1.0), btn(dev, 12)],
               jump=[btn(dev, 0)], interact=[btn(dev, 1)], assist=[btn(dev, 3)])
    for verb in ("left", "right", "up", "down", "jump", "interact", "assist"):
        dz = 0.25 if verb in ("left", "right", "up", "down") else 0.5
        evs = pad[verb] + [key(k) for k in kb[p][verb]]
        actions.append((f"p{p}_{verb}", dz, evs))
# Pause: Start (6) on each pad; Esc for keyboard player 1, Backspace for player 2.
actions.append(("p1_pause", 0.5, [btn(0, 6), key(K["ESC"])]))
actions.append(("p2_pause", 0.5, [btn(1, 6), key(K["BACKSPACE"])]))
actions.append(("debug_reset", 0.5, [key(K["F5"])]))

L = ["; Engine configuration file.",
     "; Edit through the Godot editor when possible.", "",
     "config_version=5", "",
     "[application]", "",
     'config/name="Bubu & Dudu"',
     'run/main_scene="res://scenes/ui/MainMenu.tscn"',
     'config/icon="res://art/icon.svg"',
     'config/features=PackedStringArray("4.7", "GL Compatibility")', "",
     "[autoload]", "",
     'Sfx="*res://scenes/core/Sfx.gd"',
     'GameState="*res://scenes/core/GameState.gd"',
     'Voices="*res://scenes/core/Voices.gd"',
     'PadAssigner="*res://scenes/core/PadAssigner.gd"', "",
     "[audio]", "",
     'buses/default_bus_layout="res://default_bus_layout.tres"', "",
     "[display]", "",
     "window/size/viewport_width=1280",
     "window/size/viewport_height=720",
     'window/stretch/mode="canvas_items"',
     'window/stretch/aspect="expand"', "",
     "[editor_plugins]", "",
     "enabled=PackedStringArray()", "",
     "[input_devices]", "",
     "pointing/emulate_touch_from_mouse=false", "",
     "[input]", ""]
for name, dz, evs in actions:
    L.append(name + "={")
    L.append('"deadzone": %s,' % dz)
    L.append('"events": [' + "\n, ".join(evs))
    L.append("]")
    L.append("}")
L += ["", "[layer_names]", "",
      '2d_physics/layer_1="world"',
      '2d_physics/layer_2="players"',
      '2d_physics/layer_3="props"',
      '2d_physics/layer_4="hazards"',
      '2d_physics/layer_5="triggers"', "",
      "[physics]", "",
      "common/physics_jitter_fix=0.0",
      "common/physics_interpolation=true", "",
      "[rendering]", "",
      'renderer/rendering_method="gl_compatibility"',
      'renderer/rendering_method.mobile="gl_compatibility"', ""]
open(out, "w", newline="\n", encoding="utf-8").write("\n".join(L))
