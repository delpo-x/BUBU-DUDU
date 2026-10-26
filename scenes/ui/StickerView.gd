class_name StickerView
extends Control
## A Control that plays a sticker from art/stickers/ inside its rect, keeping the aspect
## ratio. Runs while the tree is paused (pause menu) and honours "Riduci movimento".

@export var sticker: String = ""

var _t: float = 0.0


func _init(name_: String = "", min_size: Vector2 = Vector2(240, 240)) -> void:
	sticker = name_
	custom_minimum_size = min_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


func _draw() -> void:
	var tex := Stickers.frame(sticker, _t)
	if tex != null:
		draw_texture_rect(tex, Stickers.fit(tex, size * 0.5, size), false)
