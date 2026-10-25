class_name Vine
extends Area2D
## Climbable vine: press Up to grab, Up/Down to climb, Jump to let go.
## Origin = center. Put its top edge level with the ledge it leads to.

@export var size: Vector2 = Vector2(28, 256)
@export var color: Color = Color(0.36, 0.62, 0.36)


func _ready() -> void:
	CompUtil.setup_trigger(self)
	collision_mask = CompUtil.LAYER_PLAYERS
	CompUtil.add_rect_shape(self, size)
	body_entered.connect(func(b: Node) -> void:
		if b.has_method(&"register_vine"):
			b.call(&"register_vine", self))
	body_exited.connect(func(b: Node) -> void:
		if b.has_method(&"unregister_vine"):
			b.call(&"unregister_vine", self))


func _draw() -> void:
	var half := size * 0.5
	var pts := PackedVector2Array()
	var y := -half.y
	while y <= half.y:
		pts.append(Vector2(sin(y * 0.05) * 5.0, y))
		y += 8.0
	draw_polyline(pts, color.darkened(0.2), 4.0)
	var i := 0
	y = -half.y + 10.0
	while y < half.y:
		var side := 1.0 if i % 2 == 0 else -1.0
		var c := Vector2(side * 8.0 + sin(y * 0.05) * 5.0, y)
		draw_colored_polygon(PackedVector2Array([c, c + Vector2(side * 10.0, -6.0), c + Vector2(side * 4.0, 6.0)]), color)
		y += 22.0
		i += 1
