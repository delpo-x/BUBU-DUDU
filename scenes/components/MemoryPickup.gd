class_name MemoryPickup
extends Area2D
## A floating keepsake (photo / polaroid). Touching it unlocks a memory in the album.
## Already-collected memories show as a faint outline. Origin = center.

@export var memory_id: String = ""
@export var color: Color = Color(1.0, 0.85, 0.45)

var _t: float = 0.0
var _collected: bool = false
var _flash: float = 0.0


func _ready() -> void:
	CompUtil.setup_trigger(self)
	collision_mask = CompUtil.LAYER_PLAYERS
	var circle := CircleShape2D.new()
	circle.radius = 26.0
	var cs := CollisionShape2D.new()
	cs.shape = circle
	add_child(cs)
	_collected = memory_id == "" or GameState.has_memory(memory_id)
	body_entered.connect(_on_body_entered)
	_t = randf() * TAU


func _on_body_entered(body: Node) -> void:
	if _collected or not body is BasePlayer:
		return
	if (body as BasePlayer).state == BasePlayer.State.BALLOON:
		return
	_collected = true
	_flash = 1.0
	Sfx.play("collect", 0.0)
	if GameState.collect_memory(memory_id):
		get_tree().call_group(&"memory_popup", &"show_memory", memory_id)


func is_collected() -> bool:
	return _collected


func _physics_process(delta: float) -> void:
	_t += delta
	_flash = maxf(_flash - delta * 1.5, 0.0)
	queue_redraw()


func _draw() -> void:
	var bob := Vector2(0, sin(_t * 2.2) * 5.0)
	var rot := sin(_t * 1.3) * 0.12
	draw_set_transform(bob, rot, Vector2.ONE)
	if _collected:
		draw_rect(Rect2(-16, -19, 32, 38), Color(1, 1, 1, 0.25), false, 2.0)
	else:
		draw_circle(Vector2.ZERO, 30.0, Color(color, 0.18 + 0.08 * sin(_t * 4.0)))
		draw_rect(Rect2(-16, -19, 32, 38), Color(0.98, 0.97, 0.93))
		draw_rect(Rect2(-12, -15, 24, 22), color.darkened(0.1))
		HeartBalloon.draw_heart(self, Vector2(0, -5), 9.0, Color(1.0, 0.45, 0.55))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _flash > 0.0:
		draw_arc(Vector2.ZERO, 30.0 + 50.0 * (1.0 - _flash), 0.0, TAU, 32, Color(color, _flash), 3.0)
