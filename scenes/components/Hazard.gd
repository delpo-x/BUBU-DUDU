class_name Hazard
extends Area2D
## Touching it sends a player home on a heart balloon (no damage, no lost progress);
## crates pop back to their start. Origin = center of the hazard rectangle.

@export var size: Vector2 = Vector2(128, 24)
## "spikes", "thorns", "water", "brambles" (visual only).
@export var kind: String = "thorns"
@export var color: Color = Color(0.55, 0.3, 0.45)

var _t: float = 0.0


func _ready() -> void:
	collision_layer = CompUtil.LAYER_HAZARDS
	collision_mask = CompUtil.LAYER_PLAYERS | CompUtil.LAYER_PROPS
	monitorable = false
	CompUtil.add_rect_shape(self, size - Vector2(8.0, 6.0), Vector2(0, 3.0))


func _physics_process(delta: float) -> void:
	_t += delta
	for b in get_overlapping_bodies():
		if b is BasePlayer:
			(b as BasePlayer).lose_balance()
		elif b.has_method(&"respawn_home"):
			b.call(&"respawn_home")
	if kind == "water":
		queue_redraw()


func _draw() -> void:
	var half := size * 0.5
	match kind:
		"water":
			draw_rect(Rect2(-half, size), Color(0.35, 0.55, 0.85, 0.75))
			var x := -half.x
			while x < half.x:
				var y := -half.y + sin(_t * 3.0 + x * 0.05) * 3.0
				draw_line(Vector2(x, y), Vector2(minf(x + 14.0, half.x), y), Color(0.85, 0.92, 1.0, 0.8), 2.0)
				x += 24.0
		"spikes":
			draw_rect(Rect2(Vector2(-half.x, half.y - 6.0), Vector2(size.x, 6.0)), color.darkened(0.3))
			var n := maxi(int(size.x / 16.0), 1)
			var w := size.x / n
			for i in n:
				var x0 := -half.x + i * w
				draw_colored_polygon(PackedVector2Array([Vector2(x0, half.y - 6.0), Vector2(x0 + w, half.y - 6.0), Vector2(x0 + w * 0.5, -half.y)]), color)
		_:
			# Thorny bramble: a dark mass with spiky outline.
			draw_rect(Rect2(Vector2(-half.x, -half.y + 6.0), Vector2(size.x, size.y - 6.0)), color.darkened(0.25))
			var n2 := maxi(int(size.x / 12.0), 1)
			var w2 := size.x / n2
			for i in n2:
				var x1 := -half.x + i * w2
				var tip_y := -half.y - (4.0 if i % 2 == 0 else 0.0)
				draw_colored_polygon(PackedVector2Array([Vector2(x1, -half.y + 8.0), Vector2(x1 + w2, -half.y + 8.0), Vector2(x1 + w2 * 0.5, tip_y)]), color)
