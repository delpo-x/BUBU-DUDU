class_name WallButton
extends Node2D
## Interact (B) to use. BUTTON: active for active_time seconds after a press
## (two buttons on an ALL channel list = press together). LEVER: toggles on/off.

enum Mode { BUTTON, LEVER }

@export var mode: Mode = Mode.BUTTON
@export var channel: StringName = &""
@export var active_time: float = 1.5
@export var start_on: bool = false
@export var interact_radius: float = 64.0
@export var color: Color = Color(0.35, 0.6, 0.85)

var _room: Room
var _active: bool = false
var _timer: float = 0.0


func _ready() -> void:
	add_to_group(&"interactables")
	_room = Room.find_for(self)
	if mode == Mode.LEVER and start_on:
		_set_active(true, false)


func get_interact_position() -> Vector2:
	return global_position


func can_interact(player: BasePlayer) -> bool:
	return player.state == BasePlayer.State.NORMAL


func interact(_player: BasePlayer) -> void:
	if mode == Mode.LEVER:
		_set_active(not _active, true)
	else:
		_timer = active_time
		_set_active(true, true)


func is_active() -> bool:
	return _active


func _set_active(on: bool, with_sound: bool) -> void:
	if on == _active:
		return
	_active = on
	if _room != null:
		_room.set_source(channel, CompUtil.source_id(self), on)
	if with_sound:
		Sfx.play("lever" if mode == Mode.LEVER else ("plate_on" if on else "plate_off"))
	queue_redraw()


func _physics_process(delta: float) -> void:
	if mode == Mode.BUTTON and _active:
		_timer -= delta
		if int(_timer * 4.0) != int((_timer + delta) * 4.0):
			Sfx.play("timer_tick", 0.0, -8.0)
		if _timer <= 0.0:
			_set_active(false, true)
		queue_redraw()


func _draw() -> void:
	var c := color.lightened(0.25) if _active else color
	if mode == Mode.LEVER:
		draw_rect(Rect2(-14, -10, 28, 10), c.darkened(0.5))
		var angle := 0.6 if _active else -0.6
		var tip := Vector2(sin(angle), -cos(angle)) * 34.0 + Vector2(0, -6)
		draw_line(Vector2(0, -6), tip, c.darkened(0.2), 5.0)
		draw_circle(tip, 7.0, c)
	else:
		draw_rect(Rect2(-18, -64, 36, 44), c.darkened(0.55))
		draw_circle(Vector2(0, -42), 12.0 if not _active else 9.0, c)
		if _active:
			draw_arc(Vector2(0, -42), 17.0, -PI / 2.0, -PI / 2.0 + TAU * clampf(_timer / active_time, 0.0, 1.0), 28, c.lightened(0.2), 3.0)
	# Small "B" prompt so the beginner knows this is usable.
	draw_string(ThemeDB.fallback_font, Vector2(-5, -76 if mode == Mode.BUTTON else -52), "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c.darkened(0.4))
