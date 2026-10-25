class_name WindZone
extends Area2D
## An updraft. While blowing, players inside float upwards (gravity is overpowered),
## capped at max_rise_speed. Origin = center of the column. Optional channels gate it.

@export var size: Vector2 = Vector2(96, 320)
@export var strength: float = 3400.0
@export var max_rise_speed: float = 300.0
@export var channels: Array[StringName] = []
@export var require_all: bool = true
@export var color: Color = Color(0.75, 0.88, 0.95)

var _room: Room
var _t: float = 0.0
var _blowing: bool = true


func _ready() -> void:
	CompUtil.setup_trigger(self)
	collision_mask = CompUtil.LAYER_PLAYERS
	CompUtil.add_rect_shape(self, size)
	_room = Room.find_for(self)
	body_entered.connect(func(b: Node) -> void:
		if b.has_method(&"register_wind"):
			b.call(&"register_wind", self))
	body_exited.connect(func(b: Node) -> void:
		if b.has_method(&"unregister_wind"):
			b.call(&"unregister_wind", self))


func is_blowing() -> bool:
	return _blowing


func _physics_process(delta: float) -> void:
	_t += delta
	var on := _room.evaluate(channels, require_all) if _room != null else true
	if on != _blowing:
		_blowing = on
		if on:
			Sfx.play("wind")
	queue_redraw()


func _draw() -> void:
	var half := size * 0.5
	# Fan housing at the bottom.
	draw_rect(Rect2(Vector2(-half.x, half.y - 14.0), Vector2(size.x, 14.0)), color.darkened(0.45))
	if not _blowing:
		return
	draw_rect(Rect2(-half, size), Color(color, 0.12))
	for i in 7:
		var x := -half.x + (i + 0.5) * size.x / 7.0
		var y := fmod(_t * 220.0 + i * 67.0, size.y)
		var top := half.y - y
		draw_line(Vector2(x, top), Vector2(x, top + 26.0), Color(color, 0.7), 2.0)
