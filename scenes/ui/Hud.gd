class_name Hud
extends Control
## In-game overlay: toasts (group "toast"), memory popups (group "memory_popup"),
## chapter title cards and the screen fade used between rooms.

const HEART_ICON := preload("res://art/ui/heart.svg")

var _toast: PanelContainer
var _toast_label: Label
var _toast_time: float = 0.0

var _memory: PanelContainer
var _memory_title: Label
var _memory_text: Label
var _memory_time: float = 0.0

var _title_root: Control
var _title_label: Label
var _subtitle_label: Label
var _chapter_label: Label

var _fade: ColorRect


func _ready() -> void:
	add_to_group(&"toast")
	add_to_group(&"memory_popup")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()

	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override(&"panel", UiTheme.box(Color(UiTheme.INK, 0.85), 14, 0, Color.TRANSPARENT, 18))
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_top = 22
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_label = UiTheme.label("", 21, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.add_child(_toast_label)
	_toast.modulate.a = 0.0
	add_child(_toast)

	_memory = PanelContainer.new()
	_memory.add_theme_stylebox_override(&"panel", UiTheme.box(UiTheme.PANEL, 18, 4, UiTheme.ACCENT, 22))
	_memory.anchor_left = 1.0
	_memory.anchor_right = 1.0
	_memory.offset_left = -440
	_memory.offset_right = -24
	_memory.offset_top = 24
	var mv := VBoxContainer.new()
	_memory.add_child(mv)
	# Header: vector heart (font glyphs may render as emoji or tofu on web) + label.
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	var heart := TextureRect.new()
	heart.texture = HEART_ICON
	heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heart.custom_minimum_size = Vector2(24, 24)
	head.add_child(heart)
	head.add_child(UiTheme.label("Nuovo ricordo", 18, UiTheme.ACCENT_INK))
	mv.add_child(head)
	_memory_title = UiTheme.label("", 24)
	mv.add_child(_memory_title)
	_memory_text = UiTheme.label("", 18, UiTheme.MUTED)
	_memory_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_memory_text.custom_minimum_size = Vector2(380, 0)
	mv.add_child(_memory_text)
	_memory.modulate.a = 0.0
	add_child(_memory)

	_title_root = Control.new()
	_title_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tv := VBoxContainer.new()
	tv.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	tv.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tv.grow_vertical = Control.GROW_DIRECTION_BOTH
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_root.add_child(tv)
	_chapter_label = UiTheme.label("", 26, UiTheme.ACCENT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	_title_label = UiTheme.label("", 64, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle_label = UiTheme.label("", 24, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	tv.add_child(_chapter_label)
	tv.add_child(_title_label)
	tv.add_child(_subtitle_label)
	_title_root.modulate.a = 0.0
	_title_root.visible = false

	_fade = ColorRect.new()
	_fade.color = Color(0.1, 0.08, 0.1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 1.0
	add_child(_fade)
	add_child(_title_root)


func show_toast(text: String, duration: float = 2.4) -> void:
	_toast_label.text = text
	_toast_time = duration
	_toast.reset_size()
	_toast.offset_left = -_toast.size.x * 0.5
	_toast.offset_right = _toast.size.x * 0.5


func show_memory(id: String) -> void:
	var def: Dictionary = GameState.memory_defs.get(id, {})
	_memory_title.text = String(def.get("title", id))
	_memory_text.text = String(def.get("short", ""))
	_memory_title.add_theme_font_size_override(&"font_size", UiTheme.read_size(24))
	_memory_text.add_theme_font_size_override(&"font_size", UiTheme.read_size(18))
	_memory_time = 4.5
	Sfx.play("collect", 0.0)


func _process(delta: float) -> void:
	_toast_time = maxf(_toast_time - delta, 0.0)
	_toast.modulate.a = move_toward(_toast.modulate.a, 1.0 if _toast_time > 0.0 else 0.0, delta * 4.0)
	_memory_time = maxf(_memory_time - delta, 0.0)
	_memory.modulate.a = move_toward(_memory.modulate.a, 1.0 if _memory_time > 0.0 else 0.0, delta * 3.0)


## Fades the screen to black (amount 1) or back to the game (amount 0).
func fade_to(amount: float, duration: float = 0.45) -> void:
	var tw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_fade, "modulate:a", amount, duration)
	await tw.finished


func set_faded(amount: float) -> void:
	_fade.modulate.a = amount


## Big chapter card over a dark screen. Waits `hold` seconds (any advance press skips).
func show_title(chapter_text: String, title: String, subtitle: String, hold: float = 2.6) -> void:
	_chapter_label.text = chapter_text
	_title_label.text = title
	_subtitle_label.text = subtitle
	_title_root.visible = true
	Sfx.play("chapter", 0.0)
	var tw := create_tween()
	tw.tween_property(_title_root, "modulate:a", 1.0, 0.6)
	await tw.finished
	var t := 0.0
	while t < hold and is_inside_tree():
		await get_tree().process_frame
		t += get_process_delta_time()
	var tw2 := create_tween()
	tw2.tween_property(_title_root, "modulate:a", 0.0, 0.6)
	await tw2.finished
	_title_root.visible = false
