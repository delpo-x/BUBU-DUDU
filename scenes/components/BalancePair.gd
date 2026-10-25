class_name BalancePair
extends Node2D
## Two linked pads.
## PULLEY (weight platform): the heavier side sinks, the other rises, proportionally.
## SEESAW: tilts fully towards the heavier side; landing hard on one side launches
## everything standing on the other side (heavier landers launch higher).
## pad_a / pad_b are the pads' rest centers relative to this node.

enum Mode { PULLEY, SEESAW }

@export var mode: Mode = Mode.PULLEY
@export var pad_size: Vector2 = Vector2(112, 20)
@export var pad_a: Vector2 = Vector2(-160, 0)
@export var pad_b: Vector2 = Vector2(160, 0)
## Max vertical displacement of each pad from rest.
@export var travel: float = 96.0
## PULLEY: displacement per unit of weight difference.
@export var px_per_weight: float = 48.0
@export var speed: float = 150.0
@export var launch_base: float = 380.0
@export var launch_per_weight: float = 520.0
@export var launch_max: float = 1450.0
## Optional channel active while pad A is fully down.
@export var channel_a_down: StringName = &""
## Optional channel active while pad B is fully down.
@export var channel_b_down: StringName = &""
## SEESAW: initial tilt, +1 = A down, -1 = B down, 0 = level.
@export var start_tilt: int = 0
@export var color: Color = Color(0.62, 0.5, 0.38)

var _room: Room
var _pads: Array[BalancePad] = []
var _sensors: Array[Area2D] = []
var _offset: float = 0.0   # + = A down / B up
var _boost_time: float = 0.0
var _a_down: bool = false
var _b_down: bool = false


func _ready() -> void:
	_room = Room.find_for(self)
	if mode == Mode.SEESAW:
		_offset = travel * clampi(start_tilt, -1, 1)
	for i in 2:
		var pad := BalancePad.new()
		pad.pair = self
		pad.side = i
		pad.collision_layer = CompUtil.LAYER_WORLD
		pad.collision_mask = 0
		pad.sync_to_physics = true
		pad.position = _pad_pos(i)
		add_child(pad)
		CompUtil.add_rect_shape(pad, pad_size)
		var sensor := Area2D.new()
		CompUtil.setup_trigger(sensor)
		pad.add_child(sensor)
		CompUtil.add_rect_shape(sensor, Vector2(pad_size.x - 6.0, 28.0), Vector2(0, -pad_size.y * 0.5 - 14.0))
		_pads.append(pad)
		_sensors.append(sensor)


func _pad_pos(side: int) -> Vector2:
	return pad_a + Vector2(0, _offset) if side == 0 else pad_b + Vector2(0, -_offset)


func weight_on(side: int) -> int:
	var w := 0
	for b in _sensors[side].get_overlapping_bodies():
		w += CompUtil.body_weight(b)
	return w


func bodies_on(side: int) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for b in _sensors[side].get_overlapping_bodies():
		if b is Node2D:
			out.append(b as Node2D)
	return out


func on_pad_landed(side: int, body: Node, impact: float) -> void:
	if mode != Mode.SEESAW or impact < 250.0:
		return
	var lander := CompUtil.body_weight(body)
	var other := 1 - side
	if lander <= 0 or lander < weight_on(other):
		return
	var speed_up := minf(launch_base + launch_per_weight * lander, launch_max)
	for b in bodies_on(other):
		if b == body:
			continue
		if b.has_method(&"launch"):
			b.call(&"launch", speed_up)
		elif b is RigidBody2D:
			(b as RigidBody2D).linear_velocity = Vector2(0, -speed_up * 0.8)
	_boost_time = 0.25


func _physics_process(delta: float) -> void:
	var wa := weight_on(0)
	var wb := weight_on(1)
	var target := _offset
	if mode == Mode.PULLEY:
		target = clampf((wa - wb) * px_per_weight, -travel, travel)
	elif wa != wb:
		target = travel * signf(wa - wb)
	var spd := speed * (6.0 if _boost_time > 0.0 else 1.0)
	_boost_time = maxf(_boost_time - delta, 0.0)
	var next_offset := move_toward(_offset, target, spd * delta)
	# The pad that goes down must not crush anyone underneath it.
	var sinking := 0 if next_offset > _offset else 1
	if next_offset != _offset and _pad_blocked(sinking, next_offset):
		next_offset = _offset
	_offset = next_offset
	_pads[0].position = _pad_pos(0)
	_pads[1].position = _pad_pos(1)
	_update_channels()
	queue_redraw()


func _pad_blocked(side: int, offset: float) -> bool:
	var saved := _offset
	_offset = offset
	var local := _pad_pos(side)
	_offset = saved
	var params := PhysicsShapeQueryParameters2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(pad_size.x - 4.0, pad_size.y)
	params.shape = rect
	params.transform = Transform2D(0.0, global_transform * local + Vector2(0, 2))
	params.collision_mask = CompUtil.LAYER_PLAYERS | CompUtil.LAYER_PROPS
	params.exclude = [_pads[0].get_rid(), _pads[1].get_rid()]
	return not get_world_2d().direct_space_state.intersect_shape(params, 1).is_empty()


func _update_channels() -> void:
	if _room == null:
		return
	var a_down := _offset >= travel - 2.0
	var b_down := _offset <= -travel + 2.0
	if a_down != _a_down:
		_a_down = a_down
		_room.set_source(channel_a_down, CompUtil.source_id(self) + "a", a_down)
	if b_down != _b_down:
		_b_down = b_down
		_room.set_source(channel_b_down, CompUtil.source_id(self) + "b", b_down)


func _draw() -> void:
	var pa := _pad_pos(0)
	var pb := _pad_pos(1)
	var rope := color.darkened(0.45)
	if mode == Mode.PULLEY:
		var top_y := minf(pad_a.y, pad_b.y) - travel - 140.0
		var wa := Vector2(pad_a.x, top_y)
		var wb := Vector2(pad_b.x, top_y)
		draw_line(wa, wb, rope, 3.0)
		draw_circle(wa, 12.0, rope)
		draw_circle(wb, 12.0, rope)
		draw_line(wa, pa + Vector2(0, -pad_size.y * 0.5), rope, 2.0)
		draw_line(wb, pb + Vector2(0, -pad_size.y * 0.5), rope, 2.0)
	else:
		var mid := (pad_a + pad_b) * 0.5
		draw_colored_polygon(PackedVector2Array([mid + Vector2(-26, travel + 30), mid + Vector2(26, travel + 30), mid + Vector2(0, 8)]), rope)
		draw_line(pa, pb, color.darkened(0.2), 8.0)
	for p: Vector2 in [pa, pb]:
		draw_rect(Rect2(p - pad_size * 0.5, pad_size), color)
		draw_rect(Rect2(p - pad_size * 0.5, Vector2(pad_size.x, 4.0)), color.lightened(0.3))
