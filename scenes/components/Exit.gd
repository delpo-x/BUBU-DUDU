class_name Exit
extends Area2D
## Room exit. When both players are inside (a rider counts through the carrier) and the
## exit is unlocked, the room completes. Origin = floor point at the door's center.

@export var size: Vector2 = Vector2(96, 140)
@export var channels: Array[StringName] = []
@export var require_all: bool = true
@export var color: Color = Color(0.95, 0.78, 0.45)

var _room: Room
var _unlocked: bool = true
var _inside_time: float = 0.0
var _waiting: Array[bool] = [false, false]
var _pulse: float = 0.0


func _ready() -> void:
	CompUtil.setup_trigger(self)
	collision_mask = CompUtil.LAYER_PLAYERS
	CompUtil.add_rect_shape(self, size, Vector2(0, -size.y * 0.5))
	_room = Room.find_for(self)
	_refresh_lock()


func _refresh_lock() -> void:
	var was := _unlocked
	_unlocked = _room.evaluate(channels, require_all) if _room != null else true
	if _room != null and not channels.is_empty():
		_room.exit_unlocked = _unlocked
	if _unlocked and not was:
		Sfx.play("exit_ready")


func is_unlocked() -> bool:
	return _unlocked


func _contains(p: BasePlayer) -> bool:
	if p.state == BasePlayer.State.BALLOON:
		return false
	if overlaps_body(p):
		return true
	return p.carrier != null and overlaps_body(p.carrier)


func _physics_process(delta: float) -> void:
	_refresh_lock()
	_pulse += delta
	var players := CompUtil.players(get_tree())
	var count := 0
	for i in players.size():
		var inside := _contains(players[i])
		if i < 2:
			_waiting[i] = inside
		if inside:
			count += 1
	if _unlocked and players.size() >= 2 and count >= players.size():
		_inside_time += delta
		if _inside_time > 0.35 and _room != null:
			_room.complete()
	else:
		_inside_time = 0.0
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var frame := color.darkened(0.35)
	draw_rect(Rect2(-w * 0.5, -h, w, h), Color(color, 0.25 if _unlocked else 0.12))
	draw_rect(Rect2(-w * 0.5 - 8, -h - 8, 8, h + 8), frame)
	draw_rect(Rect2(w * 0.5, -h - 8, 8, h + 8), frame)
	draw_rect(Rect2(-w * 0.5 - 8, -h - 8, w + 16, 8), frame)
	if not _unlocked:
		var x := -w * 0.5 + 10.0
		while x < w * 0.5:
			draw_rect(Rect2(x, -h, 6, h), frame.darkened(0.2))
			x += 18.0
		return
	# Two hearts above the door fill in as each player arrives: both are needed.
	for i in 2:
		var p := Vector2((i - 0.5) * 30.0, -h - 30.0 + sin(_pulse * 3.0 + i) * 2.0)
		if _waiting[i]:
			HeartBalloon.draw_heart(self, p, 16.0, Color(1.0, 0.45, 0.55))
		else:
			draw_arc(p + Vector2(0, 1), 8.0, 0.0, TAU, 16, Color(1.0, 0.45, 0.55, 0.6), 2.0)
