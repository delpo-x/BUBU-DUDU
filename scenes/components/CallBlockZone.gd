class_name CallBlockZone
extends Node2D
## While either player is inside this rectangle, Call/Tether is refused (until the room
## exit unlocks). Keeps Call from skipping a puzzle section. Origin = center.

@export var size: Vector2 = Vector2(512, 512)
## Draws a faint dotted outline (hidden by default; the "nope" feedback is enough).
@export var show_outline: bool = false


func _ready() -> void:
	add_to_group(&"call_block_zones")


func contains_point(p: Vector2) -> bool:
	return Rect2(global_position - size * 0.5, size).has_point(p)


func _draw() -> void:
	if not show_outline:
		return
	var r := Rect2(-size * 0.5, size)
	var c := Color(1, 1, 1, 0.15)
	var x := r.position.x
	while x < r.end.x:
		draw_line(Vector2(x, r.position.y), Vector2(minf(x + 12.0, r.end.x), r.position.y), c, 2.0)
		draw_line(Vector2(x, r.end.y), Vector2(minf(x + 12.0, r.end.x), r.end.y), c, 2.0)
		x += 24.0
