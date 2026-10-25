class_name Gate
extends StaticBody2D
## A door/wall driven by room channels. Origin = center of the closed gate.
## invert = false: solid while closed, opens when the condition is true (door).
## invert = true: solid only while the condition is true (appearing bridge).

@export var size: Vector2 = Vector2(32, 160)
@export var channels: Array[StringName] = []
@export var require_all: bool = true
@export var invert: bool = false
## Once opened (or once solid, for bridges) it stays that way.
@export var latch: bool = false
## Where the door slides when it opens.
@export var slide: Vector2 = Vector2.UP
@export var color: Color = Color(0.45, 0.42, 0.55)

var _room: Room
var _shape: CollisionShape2D
var _amount: float = 0.0   # 0 = solid/closed, 1 = gone/open
var _want_open: bool = false
var _latched: bool = false
var _solid: bool = true


func _ready() -> void:
	collision_layer = CompUtil.LAYER_WORLD
	collision_mask = 0
	_shape = CompUtil.add_rect_shape(self, size)
	_room = Room.find_for(self)
	_want_open = _compute_open()
	_amount = 1.0 if _want_open else 0.0
	_apply_solid(not _want_open)


func is_open() -> bool:
	return _want_open


func _compute_open() -> bool:
	if _latched:
		return not invert
	var cond := _room.evaluate(channels, require_all) if _room != null else false
	if cond and latch:
		_latched = true
	return cond != invert


func _physics_process(delta: float) -> void:
	var want := _compute_open()
	if want != _want_open:
		_want_open = want
		Sfx.play("gate_open" if want else "gate_close")
	_amount = move_toward(_amount, 1.0 if _want_open else 0.0, delta * 3.0)
	if _want_open and _amount > 0.4:
		if _solid:
			_apply_solid(false)
	elif not _want_open and _amount < 0.6 and not _solid:
		# Never close on top of someone: wait until the space is clear.
		if _space_is_clear():
			_apply_solid(true)
		else:
			_amount = maxf(_amount, 0.6)
	queue_redraw()


func _apply_solid(solid: bool) -> void:
	_solid = solid
	_shape.set_deferred(&"disabled", not solid)


func _space_is_clear() -> bool:
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _shape.shape
	params.transform = global_transform
	params.collision_mask = CompUtil.LAYER_PLAYERS | CompUtil.LAYER_PROPS
	return get_world_2d().direct_space_state.intersect_shape(params, 1).is_empty()


func _draw() -> void:
	var half := size * 0.5
	if invert:
		# Bridge: fades in when solid, dashed outline when absent.
		var a := 1.0 - _amount
		if a > 0.02:
			draw_rect(Rect2(-half, size), Color(color, a))
		var outline := Color(color, 0.45)
		var x := -half.x
		while x < half.x:
			draw_line(Vector2(x, -half.y), Vector2(minf(x + 10.0, half.x), -half.y), outline, 2.0)
			draw_line(Vector2(x, half.y), Vector2(minf(x + 10.0, half.x), half.y), outline, 2.0)
			x += 20.0
		return
	var dir := slide.normalized()
	var extent := absf(dir.x) * size.x + absf(dir.y) * size.y
	var r := Rect2(-half + dir * extent * _amount, size)
	draw_rect(r, color)
	# Stripes so doors read differently from plain walls.
	var stripe := color.darkened(0.2)
	var s := 0.0
	while s < size.y:
		draw_rect(Rect2(r.position + Vector2(0, s), Vector2(size.x, minf(6.0, size.y - s))), stripe)
		s += 22.0
	draw_rect(Rect2(-half, size), Color(color.darkened(0.4), 0.35), false, 2.0)
