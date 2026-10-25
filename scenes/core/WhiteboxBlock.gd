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

## Grooved surface: Bubu can wall-jump off its sides.
@export var wall_jump: bool = false:
	set(value):
		wall_jump = value
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
	if wall_jump:
		add_to_group(&"walljump")
	elif is_in_group(&"walljump"):
		remove_from_group(&"walljump")
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
	if wall_jump:
		# Vertical grooves on both sides read as "climbable by wall jumps".
		var groove := color.lightened(0.35)
		var y := r.position.y + 10.0
		while y < r.end.y - 10.0:
			draw_rect(Rect2(Vector2(r.position.x, y), Vector2(6.0, 12.0)), groove)
			draw_rect(Rect2(Vector2(r.end.x - 6.0, y), Vector2(6.0, 12.0)), groove)
			y += 22.0
