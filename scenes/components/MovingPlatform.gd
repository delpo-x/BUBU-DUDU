class_name MovingPlatform
extends AnimatableBody2D
## A solid platform that carries whoever stands on it. Origin = center at the start point.
## LOOP: ping-pongs start <-> start+travel while the condition holds (always if no channels).
## TOGGLE: moves to the end while the condition holds, back to the start otherwise.

enum Mode { LOOP, TOGGLE }

@export var size: Vector2 = Vector2(128, 20)
@export var travel: Vector2 = Vector2(0, -192)
@export var speed: float = 90.0
@export var mode: Mode = Mode.LOOP
@export var channels: Array[StringName] = []
@export var require_all: bool = true
@export var pause_time: float = 0.6
@export var one_way: bool = false
@export var color: Color = Color(0.5, 0.62, 0.55)

var _room: Room
var _start: Vector2
var _progress: float = 0.0
var _dir: float = 1.0
var _pause: float = 0.0
var _shape: CollisionShape2D


func _ready() -> void:
	collision_layer = CompUtil.LAYER_WORLD
	collision_mask = 0
	sync_to_physics = true
	_shape = CompUtil.add_rect_shape(self, size)
	_shape.one_way_collision = one_way
	_start = position
	_room = Room.find_for(self)
	# LOOP platforms wait at the start first, so nobody steps on as it leaves.
	_pause = pause_time


func _physics_process(delta: float) -> void:
	var length := travel.length()
	if length <= 0.0 or CompUtil.dialogue_busy(self):
		return
	var cond := _room.evaluate(channels, require_all) if _room != null else true
	var step := speed * delta / length
	var before := _progress
	if mode == Mode.TOGGLE:
		_progress = move_toward(_progress, 1.0 if cond else 0.0, step)
	elif cond:
		if _pause > 0.0:
			_pause -= delta
		else:
			_progress += step * _dir
			if _progress >= 1.0 or _progress <= 0.0:
				_progress = clampf(_progress, 0.0, 1.0)
				_dir = -_dir
				_pause = pause_time
	var next := _start + travel * _smooth(_progress)
	# Never crush anyone: hold still while a body is in the way below.
	if next.y > position.y and _blocked(next):
		_progress = before
		return
	position = next
	queue_redraw()


func _blocked(next: Vector2) -> bool:
	var params := PhysicsShapeQueryParameters2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x - 4.0, size.y)
	params.shape = rect
	var parent_xf := (get_parent() as Node2D).global_transform if get_parent() is Node2D else Transform2D.IDENTITY
	params.transform = Transform2D(0.0, parent_xf * next + Vector2(0, 2))
	params.collision_mask = CompUtil.LAYER_PLAYERS | CompUtil.LAYER_PROPS
	params.exclude = [get_rid()]
	return not get_world_2d().direct_space_state.intersect_shape(params, 1).is_empty()


func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _draw() -> void:
	var half := size * 0.5
	draw_rect(Rect2(-half, size), color)
	draw_rect(Rect2(-half, Vector2(size.x, 4.0)), color.lightened(0.25))
	draw_circle(Vector2(-half.x + 10.0, 0), 4.0, color.darkened(0.3))
	draw_circle(Vector2(half.x - 10.0, 0), 4.0, color.darkened(0.3))
