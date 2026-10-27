class_name MysteryBox
extends StaticBody2D
## A "?" block floating above the ground. Jump and bump it from below: a keepsake pops out
## and goes into the album (see MemoryPickup). Once opened, or when the memory is already
## in the album, it stays empty. Origin = center of the block.

@export var memory_id: String = ""
@export var size: Vector2 = Vector2(64, 64)
@export var color: Color = Color(1.0, 0.82, 0.35)

## Upward speed (px/s) a player needs to open it: walking underneath never does.
const MIN_BUMP_SPEED := 40.0

var _sensor: Area2D
var _opened: bool = false
var _bump: float = 0.0
var _pop: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	collision_layer = CompUtil.LAYER_WORLD
	collision_mask = 0
	CompUtil.add_rect_shape(self, size)
	# A thin sensor just under the block sees the head coming up before it stops.
	_sensor = Area2D.new()
	CompUtil.setup_trigger(_sensor)
	add_child(_sensor)
	CompUtil.add_rect_shape(_sensor, Vector2(size.x - 8.0, 16.0), Vector2(0, size.y * 0.5 + 8.0))
	_opened = memory_id == "" or GameState.has_memory(memory_id)


func is_opened() -> bool:
	return _opened


## Opens the block as if a player had bumped it (also used by the tests).
func open() -> void:
	if _opened:
		return
	_opened = true
	_bump = 1.0
	_pop = 1.0
	Sfx.play("pop", 0.0)
	Sfx.play("collect", 0.0)
	if GameState.collect_memory(memory_id):
		get_tree().call_group(&"memory_popup", &"show_memory", memory_id)


func _physics_process(delta: float) -> void:
	_t += delta
	_bump = maxf(_bump - delta * 5.0, 0.0)
	_pop = maxf(_pop - delta * 1.2, 0.0)
	if not _opened:
		for body in _sensor.get_overlapping_bodies():
			var p := body as BasePlayer
			if p != null and p.state != BasePlayer.State.BALLOON and p.velocity.y < -MIN_BUMP_SPEED:
				open()
				break
	queue_redraw()


func _draw() -> void:
	# The block hops up a few pixels when hit.
	var hop := -sin(_bump * PI) * 10.0
	var r := Rect2(-size * 0.5 + Vector2(0, hop), size)
	var face := color if not _opened else Color(0.72, 0.64, 0.55)
	draw_rect(r.grow(2.0), face.darkened(0.45))
	draw_rect(r, face)
	draw_rect(Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 10)), face.lightened(0.18), false, 2.0)
	for corner in [Vector2(9, 9), Vector2(size.x - 9, 9), Vector2(9, size.y - 9), Vector2(size.x - 9, size.y - 9)]:
		draw_circle(r.position + corner, 2.5, face.darkened(0.45))
	# The heart that jumps out of the block.
	if _pop > 0.0:
		var k := 1.0 - _pop
		HeartBalloon.draw_heart(self, Vector2(0, -size.y * 0.5 - 10.0 - k * 46.0), 11.0, Color(1.0, 0.45, 0.55, _pop))
	if _opened:
		return
	var font := ThemeDB.fallback_font
	var glow := 0.5 + 0.5 * sin(_t * 3.0)
	draw_string(font, r.position + Vector2(0, size.y * 0.5 + 15.0), "?", HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, Color(0.45, 0.22, 0.1).lerp(Color.WHITE, glow * 0.35))
