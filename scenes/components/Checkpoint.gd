class_name Checkpoint
extends Area2D
## A little lantern. When any player touches it, it lights up and both players' respawn
## points (used when both are on balloons) move here. Origin = floor center.

@export var size: Vector2 = Vector2(80, 140)
@export var color: Color = Color(1.0, 0.82, 0.4)

var _room: Room
var _lit: bool = false
var _t: float = 0.0


func _ready() -> void:
	CompUtil.setup_trigger(self)
	collision_mask = CompUtil.LAYER_PLAYERS
	CompUtil.add_rect_shape(self, size, Vector2(0, -size.y * 0.5))
	_room = Room.find_for(self)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _lit or not body is BasePlayer or _room == null:
		return
	_lit = true
	# Feet on the floor: body centers sit half a body above the origin.
	_room.set_checkpoint(global_position + Vector2(-26, -32), global_position + Vector2(26, -34))
	Sfx.play("plate_on", 0.0, -6.0)


func is_lit() -> bool:
	return _lit


func _physics_process(delta: float) -> void:
	_t += delta
	if _lit:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-3, -70, 6, 70), Color(0.35, 0.3, 0.3))
	draw_rect(Rect2(-12, -92, 24, 24), Color(0.3, 0.27, 0.27))
	var glow := Color(color, 0.9) if _lit else Color(0.6, 0.6, 0.6, 0.6)
	draw_rect(Rect2(-8, -88, 16, 16), glow)
	if _lit:
		draw_circle(Vector2(0, -80), 28.0 + sin(_t * 3.0) * 2.0, Color(color, 0.15))
