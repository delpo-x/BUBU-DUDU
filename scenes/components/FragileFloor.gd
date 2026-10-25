class_name FragileFloor
extends StaticBody2D
## Cracked planks. They hold light weights but give way under break_weight or more
## (Dudu, a heavy crate, or a piggyback pair). Origin = center of the planks.
## reform_time > 0 rebuilds them after a while (once nobody is in the way).

@export var size: Vector2 = Vector2(128, 20)
@export var break_weight: int = 2
@export var reform_time: float = 0.0
@export var color: Color = Color(0.7, 0.58, 0.42)

var _shape: CollisionShape2D
var _sensor: Area2D
var _load_time: float = 0.0
var _crack: float = 0.0
var _broken: bool = false
var _reform: float = 0.0
var _fall: float = 0.0


func _ready() -> void:
	collision_layer = CompUtil.LAYER_WORLD
	collision_mask = 0
	_shape = CompUtil.add_rect_shape(self, size)
	_sensor = Area2D.new()
	CompUtil.setup_trigger(_sensor)
	add_child(_sensor)
	CompUtil.add_rect_shape(_sensor, Vector2(size.x - 4.0, 26.0), Vector2(0, -size.y * 0.5 - 13.0))


func is_broken() -> bool:
	return _broken


func on_landed(body: Node, impact: float) -> void:
	if not _broken and impact > 200.0 and CompUtil.body_weight(body) >= break_weight:
		_crack = maxf(_crack, 0.5)


func _physics_process(delta: float) -> void:
	if _broken:
		_fall += delta
		if reform_time > 0.0:
			_reform -= delta
			if _reform <= 0.0 and _sensor.get_overlapping_bodies().is_empty():
				_broken = false
				_crack = 0.0
				_shape.set_deferred(&"disabled", false)
				Sfx.play("pop")
		queue_redraw()
		return
	var w := 0
	for b in _sensor.get_overlapping_bodies():
		w += CompUtil.body_weight(b)
	if w >= break_weight:
		_load_time += delta
		_crack = minf(_crack + delta * 2.2, 1.0)
	else:
		_load_time = 0.0
	if _crack >= 1.0:
		_broken = true
		_fall = 0.0
		_reform = reform_time
		_shape.set_deferred(&"disabled", true)
		Sfx.play("break")
	queue_redraw()


func _draw() -> void:
	var half := size * 0.5
	if _broken:
		var a := clampf(1.0 - _fall * 1.5, 0.0, 1.0)
		if a > 0.0:
			for i in 4:
				var x := -half.x + (i + 0.5) * size.x / 4.0
				draw_rect(Rect2(Vector2(x - size.x / 10.0, -half.y + _fall * 400.0 * (0.8 + i * 0.1)), Vector2(size.x / 5.0, size.y)), Color(color, a))
		draw_rect(Rect2(-half, size), Color(color, 0.12), false, 1.0)
		return
	var shake := sin(_crack * 80.0) * 2.0 * _crack
	draw_rect(Rect2(-half + Vector2(shake, 0), size), color)
	var dark := color.darkened(0.4)
	var plank := size.x / 4.0
	for i in range(1, 4):
		draw_line(Vector2(-half.x + i * plank + shake, -half.y), Vector2(-half.x + i * plank + shake, half.y), dark, 2.0)
	# Visible cracks so players learn to read them.
	draw_polyline(PackedVector2Array([Vector2(-half.x * 0.6, -half.y), Vector2(-half.x * 0.4, 0), Vector2(-half.x * 0.55, half.y)]), dark, 2.0)
	draw_polyline(PackedVector2Array([Vector2(half.x * 0.3, -half.y), Vector2(half.x * 0.45, -2), Vector2(half.x * 0.25, half.y)]), dark, 2.0)
	for i in break_weight:
		draw_circle(Vector2((i - (break_weight - 1) * 0.5) * 10.0, 0), 3.0, dark)
