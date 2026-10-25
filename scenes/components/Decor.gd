@tool
class_name Decor
extends Node2D
## Purely decorative placeholder shapes (no collision). Origin = floor point.
## kinds: tree, pine, bush, flower, rock, lamp, house, fence, crystal, mushroom,
##        cloud, star, window, banner, grass

@export var kind: String = "tree":
	set(v):
		kind = v
		queue_redraw()
@export var scale_factor: float = 1.0:
	set(v):
		scale_factor = v
		queue_redraw()
@export var color: Color = Color(0.45, 0.7, 0.45):
	set(v):
		color = v
		queue_redraw()
@export var seed_value: int = 0:
	set(v):
		seed_value = v
		queue_redraw()




func _draw() -> void:
	var s := scale_factor
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	match kind:
		"tree":
			draw_rect(Rect2(-8 * s, -70 * s, 16 * s, 70 * s), Color(0.5, 0.36, 0.26))
			draw_circle(Vector2(0, -100 * s), 46 * s, color)
			draw_circle(Vector2(-30 * s, -80 * s), 30 * s, color.darkened(0.08))
			draw_circle(Vector2(30 * s, -84 * s), 32 * s, color.lightened(0.06))
		"pine":
			draw_rect(Rect2(-6 * s, -30 * s, 12 * s, 30 * s), Color(0.45, 0.32, 0.24))
			for i in 3:
				var y := -30 * s - i * 34 * s
				var w := (54 - i * 12) * s
				draw_colored_polygon(PackedVector2Array([Vector2(-w, y), Vector2(w, y), Vector2(0, y - 56 * s)]), color.darkened(0.05 * i))
		"bush":
			draw_circle(Vector2(-18 * s, -16 * s), 20 * s, color.darkened(0.1))
			draw_circle(Vector2(14 * s, -18 * s), 22 * s, color)
			draw_circle(Vector2(0, -28 * s), 20 * s, color.lightened(0.05))
		"flower":
			draw_line(Vector2.ZERO, Vector2(0, -26 * s), Color(0.35, 0.6, 0.35), 3.0)
			for i in 5:
				var a := TAU * i / 5.0
				draw_circle(Vector2(0, -30 * s) + Vector2(cos(a), sin(a)) * 7 * s, 5 * s, color)
			draw_circle(Vector2(0, -30 * s), 4 * s, Color(1.0, 0.9, 0.4))
		"rock":
			draw_colored_polygon(PackedVector2Array([Vector2(-34 * s, 0), Vector2(-26 * s, -26 * s), Vector2(4 * s, -36 * s), Vector2(30 * s, -20 * s), Vector2(36 * s, 0)]), color)
		"lamp":
			draw_rect(Rect2(-3 * s, -110 * s, 6 * s, 110 * s), Color(0.3, 0.3, 0.35))
			draw_circle(Vector2(0, -116 * s), 12 * s, Color(1.0, 0.9, 0.6))
			draw_circle(Vector2(0, -116 * s), 30 * s, Color(1.0, 0.9, 0.6, 0.12))
		"house":
			var w := 160 * s
			var h := 120 * s
			draw_rect(Rect2(-w * 0.5, -h, w, h), color)
			draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.6, -h), Vector2(w * 0.6, -h), Vector2(0, -h - 70 * s)]), color.darkened(0.35))
			draw_rect(Rect2(-18 * s, -60 * s, 36 * s, 60 * s), color.darkened(0.45))
			draw_rect(Rect2(-w * 0.4, -h + 24 * s, 30 * s, 30 * s), Color(1.0, 0.9, 0.6))
			draw_rect(Rect2(w * 0.4 - 30 * s, -h + 24 * s, 30 * s, 30 * s), Color(1.0, 0.9, 0.6))
		"fence":
			for i in 5:
				draw_rect(Rect2((-60 + i * 28) * s, -40 * s, 8 * s, 40 * s), color)
			draw_rect(Rect2(-64 * s, -30 * s, 128 * s, 6 * s), color.darkened(0.15))
		"crystal":
			for i in 3:
				var x := (i - 1) * 16.0 * s
				var hh := (40 + rng.randi_range(0, 30)) * s
				draw_colored_polygon(PackedVector2Array([Vector2(x - 9 * s, 0), Vector2(x + 9 * s, 0), Vector2(x, -hh)]), color.lightened(0.1 * i))
		"mushroom":
			draw_rect(Rect2(-5 * s, -18 * s, 10 * s, 18 * s), Color(0.95, 0.92, 0.85))
			draw_colored_polygon(PackedVector2Array([Vector2(-20 * s, -16 * s), Vector2(20 * s, -16 * s), Vector2(0, -36 * s)]), color)
		"cloud":
			draw_circle(Vector2(-30 * s, 0), 24 * s, color)
			draw_circle(Vector2(0, -12 * s), 30 * s, color)
			draw_circle(Vector2(32 * s, 0), 22 * s, color)
		"star":
			draw_circle(Vector2.ZERO, 3 * s, color)
			draw_line(Vector2(-8 * s, 0), Vector2(8 * s, 0), Color(color, 0.5), 1.5)
			draw_line(Vector2(0, -8 * s), Vector2(0, 8 * s), Color(color, 0.5), 1.5)
		"window":
			draw_rect(Rect2(-24 * s, -60 * s, 48 * s, 48 * s), Color(1.0, 0.88, 0.6))
			draw_rect(Rect2(-24 * s, -60 * s, 48 * s, 48 * s), color, false, 4.0)
			draw_line(Vector2(0, -60 * s), Vector2(0, -12 * s), color, 3.0)
			draw_line(Vector2(-24 * s, -36 * s), Vector2(24 * s, -36 * s), color, 3.0)
		"banner":
			var n := 7
			for i in n:
				var x0 := (-120 + i * 34) * s
				var c := Color.from_hsv(fmod(0.08 * i + 0.95, 1.0), 0.45, 0.95)
				draw_colored_polygon(PackedVector2Array([Vector2(x0, -140 * s), Vector2(x0 + 26 * s, -140 * s), Vector2(x0 + 13 * s, -116 * s)]), c)
			draw_line(Vector2(-124 * s, -140 * s), Vector2(124 * s, -140 * s), Color(0.4, 0.35, 0.3), 2.0)
		_:  # grass
			for i in 6:
				var x := (i - 2.5) * 6.0 * s
				draw_line(Vector2(x, 0), Vector2(x + rng.randf_range(-4, 4) * s, -rng.randf_range(8, 18) * s), color, 2.0)
