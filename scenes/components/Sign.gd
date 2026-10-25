class_name Sign
extends Node2D
## A wooden sign or a note. Interact (B) to read it (plays a dialogue).
## Origin = floor point under the post.

@export var dialogue: StringName = &""
@export var interact_radius: float = 70.0
## "post" or "note" (visual only).
@export var kind: String = "post"
@export var color: Color = Color(0.72, 0.55, 0.38)

var _reading: bool = false
var _near: bool = false


func _ready() -> void:
	add_to_group(&"interactables")


func get_interact_position() -> Vector2:
	return global_position + Vector2(0, -30)


func can_interact(_player: BasePlayer) -> bool:
	return not _reading and dialogue != &""


func interact(_player: BasePlayer) -> void:
	_reading = true
	Sfx.play("ui_accept", 0.0, -4.0)
	await CompUtil.play_dialogue(self, dialogue)
	_reading = false


func _physics_process(_delta: float) -> void:
	var near := false
	for p in CompUtil.players(get_tree()):
		if p.visible and p.global_position.distance_to(get_interact_position()) <= maxf(interact_radius, p.interact_range):
			near = true
	if near != _near:
		_near = near
		queue_redraw()


func _draw() -> void:
	if kind == "note":
		draw_rect(Rect2(-14, -70, 28, 34), Color(0.98, 0.96, 0.88))
		draw_line(Vector2(-8, -60), Vector2(8, -60), Color(0.5, 0.5, 0.6), 2.0)
		draw_line(Vector2(-8, -52), Vector2(6, -52), Color(0.5, 0.5, 0.6), 2.0)
		draw_line(Vector2(-8, -44), Vector2(8, -44), Color(0.5, 0.5, 0.6), 2.0)
	else:
		draw_rect(Rect2(-4, -48, 8, 48), color.darkened(0.35))
		draw_rect(Rect2(-30, -72, 60, 30), color)
		draw_rect(Rect2(-30, -72, 60, 30), color.darkened(0.4), false, 2.0)
		draw_line(Vector2(-20, -62), Vector2(20, -62), color.darkened(0.45), 2.0)
		draw_line(Vector2(-20, -52), Vector2(12, -52), color.darkened(0.45), 2.0)
	if _near and not _reading:
		var font := ThemeDB.fallback_font
		draw_circle(Vector2(0, -96), 13.0, Color(1, 1, 1, 0.9))
		draw_string(font, Vector2(-5, -90), "B", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.2, 0.2, 0.25))
