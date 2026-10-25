@tool
class_name WhiteboxBlock
extends StaticBody2D
## Whitebox level geometry: a flat-colored rectangle with a matching collision shape.
## Set `size` in the Inspector; the node's position is the block's center.
## The collision child is generated at runtime/in-editor and is not saved in the scene.

@export var size: Vector2 = Vector2(256, 64):
	set(value):
		size = value.max(Vector2.ONE)
		_rebuild()
@export var color: Color = Color(0.55, 0.58, 0.62):
	set(value):
		color = value
		queue_redraw()
## Players can jump up through it and land on top.
@export var one_way: bool = false:
	set(value):
		one_way = value
		_rebuild()

var _shape_node: CollisionShape2D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_node_ready():
		return
	if _shape_node == null:
		_shape_node = CollisionShape2D.new()
		add_child(_shape_node)  # no owner: never serialized into the .tscn
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape_node.shape = rect
	_shape_node.one_way_collision = one_way
	queue_redraw()


func _draw() -> void:
	var r := Rect2(-size * 0.5, size)
	draw_rect(r, color)
	# Top edge highlight; one-way platforms get a dashed look to read as "jump-through".
	var top_color := color.lightened(0.25)
	if one_way:
		var x := r.position.x
		while x < r.end.x:
			draw_rect(Rect2(x, r.position.y, minf(16.0, r.end.x - x), 4.0), top_color)
			x += 32.0
	else:
		draw_rect(Rect2(r.position, Vector2(size.x, 4.0)), top_color)
