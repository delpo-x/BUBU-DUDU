class_name PressurePlate
extends Area2D
## Floor plate. Active while the weight standing on it reaches required_weight.
## Weights: Bubu 1, Dudu 2, small crate 1, heavy crate 2, a piggyback pair adds up.
## The node origin is the floor surface at the plate's center.

@export var size: Vector2 = Vector2(96, 10)
@export var channel: StringName = &""
@export var required_weight: int = 1
## Seconds the plate stays active after the weight leaves (0 = only while pressed).
@export var hold_time: float = 0.0
## Once activated it stays active.
@export var latch: bool = false
@export var color: Color = Color(0.85, 0.55, 0.3)

var _room: Room
var _weight: int = 0
var _active: bool = false
var _timer: float = 0.0


func _ready() -> void:
	CompUtil.setup_trigger(self)
	CompUtil.add_rect_shape(self, Vector2(size.x - 6.0, 26.0), Vector2(0, -15.0))
	_room = Room.find_for(self)
	add_to_group(Room.STATE_GROUP)


func is_active() -> bool:
	return _active


func current_weight() -> int:
	return _weight


func _physics_process(delta: float) -> void:
	var w := 0
	for b in get_overlapping_bodies():
		w += CompUtil.body_weight(b)
	_weight = w
	var pressed := w >= required_weight
	if pressed:
		_timer = hold_time
	elif _timer > 0.0:
		_timer = maxf(_timer - delta, 0.0)
		if int(_timer * 4.0) != int((_timer + delta) * 4.0):
			Sfx.play("timer_tick", 0.0, -6.0)
	var on := pressed or _timer > 0.0 or (latch and _active)
	if on != _active:
		_active = on
		if _room != null:
			_room.set_source(channel, CompUtil.source_id(self), on)
		Sfx.play("plate_on" if on else "plate_off")
	queue_redraw()


func _draw() -> void:
	var w := size.x
	draw_rect(Rect2(-w * 0.5 - 4.0, -4.0, w + 8.0, 4.0), color.darkened(0.45))
	var pressed := _weight >= required_weight
	var top_h := 3.0 if pressed else size.y
	var c := color.lightened(0.15) if _active else color
	draw_rect(Rect2(-w * 0.5, -4.0 - top_h, w, top_h), c)
	# Weight pips: how much weight this plate needs, filled by what stands on it.
	var spacing := 12.0
	var start := -spacing * (required_weight - 1) * 0.5
	for i in required_weight:
		var p := Vector2(start + i * spacing, -top_h - 16.0)
		if i < _weight:
			draw_circle(p, 4.0, c.darkened(0.35))
		else:
			draw_arc(p, 4.0, 0.0, TAU, 12, c.darkened(0.35), 1.5)
	if hold_time > 0.0 and _timer > 0.0 and not pressed:
		draw_arc(Vector2(0, -top_h - 34.0), 9.0, -PI / 2.0, -PI / 2.0 + TAU * (_timer / hold_time), 24, c.darkened(0.3), 3.0)


# --- Checkpoint save (see Room.capture_state) ---------------------------------------

func snapshot() -> Variant:
	return {"on": true} if latch and _active else null


func restore(d: Dictionary) -> void:
	if bool(d.get("on", false)) and not _active:
		_active = true
		if _room != null:
			_room.set_source(channel, CompUtil.source_id(self), true)
