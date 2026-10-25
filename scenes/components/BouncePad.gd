class_name BouncePad
extends StaticBody2D
## A springy mushroom. Landing on it bounces players (and crates) high.
## Origin = center of the pad.

@export var size: Vector2 = Vector2(72, 18)
@export var bounce_speed: float = 1000.0
@export var color: Color = Color(0.9, 0.45, 0.55)

var _squash: float = 0.0
var _sensor: Area2D


func _ready() -> void:
	collision_layer = CompUtil.LAYER_WORLD
	collision_mask = 0
	CompUtil.add_rect_shape(self, size)
	_sensor = Area2D.new()
	_sensor.collision_layer = CompUtil.LAYER_TRIGGERS
	_sensor.collision_mask = CompUtil.LAYER_PROPS
	_sensor.monitorable = false
	add_child(_sensor)
	CompUtil.add_rect_shape(_sensor, Vector2(size.x - 4.0, 12.0), Vector2(0, -size.y * 0.5 - 6.0))
	_sensor.body_entered.connect(_on_prop_entered)


func on_landed(body: Node, _impact: float) -> void:
	if body.has_method(&"bounce"):
		body.call(&"bounce", bounce_speed)
		_squash = 1.0
		Sfx.play("bounce")


func _on_prop_entered(body: Node) -> void:
	if body is RigidBody2D and (body as RigidBody2D).linear_velocity.y > 100.0:
		(body as RigidBody2D).linear_velocity.y = -bounce_speed * 0.8
		_squash = 1.0
		Sfx.play("bounce")


func _physics_process(delta: float) -> void:
	if _squash > 0.0:
		_squash = maxf(_squash - delta * 4.0, 0.0)
		queue_redraw()


func _draw() -> void:
	var half := size * 0.5
	var sq := 1.0 - _squash * 0.35
	draw_rect(Rect2(Vector2(-half.x * 0.3, -half.y), Vector2(size.x * 0.3, size.y + 6.0)), Color(0.95, 0.9, 0.8))
	var cap := Rect2(Vector2(-half.x, half.y - size.y * 1.6 * sq), Vector2(size.x, size.y * 1.2 * sq))
	draw_rect(cap, color)
	draw_circle(cap.position + Vector2(cap.size.x * 0.25, cap.size.y * 0.4), 5.0, color.lightened(0.5))
	draw_circle(cap.position + Vector2(cap.size.x * 0.7, cap.size.y * 0.5), 4.0, color.lightened(0.5))
