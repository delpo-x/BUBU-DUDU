class_name UiTheme
extends RefCounted
## Builds the shared UI theme in code: flat rounded panels, warm palette, gamepad-first focus.
##
## Color tokens (contrast measured on PANEL, WCAG 2.x):
##   INK 12:1 body text · MUTED 6.3:1 secondary text · ACCENT_INK 5.4:1 headings, labels,
##   focus ring · BUBU 6.3:1 / DUDU 6.5:1 speaker names. ACCENT (2.6:1) and ACCENT_SOFT are
##   for fills, borders and hearts only, never for text on PANEL.

const BG := Color(0.16, 0.13, 0.17, 0.94)
const PANEL := Color(0.99, 0.96, 0.9)
const INK := Color(0.22, 0.18, 0.2)
const MUTED := Color(0.4, 0.34, 0.36)
const ACCENT := Color(0.95, 0.45, 0.5)
const ACCENT_INK := Color(0.7, 0.22, 0.33)
const ACCENT_SOFT := Color(1.0, 0.8, 0.72)
const BUBU := Color(0.35, 0.35, 0.4)
const DUDU := Color(0.5, 0.3, 0.15)
## Smallest text size used anywhere (couch distance, 720p base resolution).
const MIN_TEXT := 18
## Rounded, friendly type (both OFL, art/fonts/): Nunito Bold for reading, Fredoka for
## headings. Labels from label() at TITLE_SIZE or above get the heading font.
const BODY_FONT := preload("res://art/fonts/body.tres")
const BODY_ITALIC := preload("res://art/fonts/body_italic.tres")
const TITLE_FONT := preload("res://art/fonts/title.tres")
const TITLE_SIZE := 30

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func box(color: Color, radius: int = 14, border: int = 0, border_color: Color = Color.TRANSPARENT, pad: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = border_color
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	return sb


## Soft drop shadow under floating panels (depth without borders).
static func lift(sb: StyleBoxFlat, size: int = 12) -> StyleBoxFlat:
	sb.shadow_size = size
	sb.shadow_color = Color(0.25, 0.1, 0.15, 0.25)
	sb.shadow_offset = Vector2(0, 5)
	return sb


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = BODY_FONT
	t.default_font_size = 22
	t.set_font(&"normal_font", &"RichTextLabel", BODY_FONT)
	t.set_font(&"italics_font", &"RichTextLabel", BODY_ITALIC)
	t.set_color(&"font_color", &"Label", INK)
	t.set_stylebox(&"panel", &"PanelContainer", lift(box(PANEL, 18, 0, Color.TRANSPARENT, 22)))
	t.set_stylebox(&"panel", &"Panel", box(PANEL, 18))

	# Focus (pad/keyboard) = filled + dark ring; hover (mouse) = ring only, so the two never
	# look alike when both happen at once; pressed = solid dark rose with white text.
	t.set_stylebox(&"normal", &"Button", box(Color(1, 1, 1, 0.0), 12, 2, Color(INK, 0.15)))
	t.set_stylebox(&"hover", &"Button", box(Color(ACCENT_SOFT, 0.3), 12, 2, ACCENT))
	t.set_stylebox(&"pressed", &"Button", box(ACCENT_INK, 12, 2, ACCENT_INK))
	t.set_stylebox(&"focus", &"Button", box(ACCENT_SOFT, 12, 3, ACCENT_INK))
	t.set_stylebox(&"disabled", &"Button", box(Color(0, 0, 0, 0.04), 12))
	t.set_color(&"font_color", &"Button", INK)
	t.set_color(&"font_hover_color", &"Button", INK)
	t.set_color(&"font_focus_color", &"Button", INK)
	t.set_color(&"font_pressed_color", &"Button", Color.WHITE)
	t.set_color(&"font_disabled_color", &"Button", Color(INK, 0.35))
	t.set_font_size(&"font_size", &"Button", 24)

	var slider_bg := box(Color(INK, 0.15), 6, 0, Color.TRANSPARENT, 0)
	slider_bg.content_margin_top = 4
	slider_bg.content_margin_bottom = 4
	t.set_stylebox(&"slider", &"HSlider", slider_bg)
	t.set_stylebox(&"grabber_area", &"HSlider", box(ACCENT, 6, 0, Color.TRANSPARENT, 0))
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", box(ACCENT, 6, 0, Color.TRANSPARENT, 0))
	var grabber: Texture2D = load("res://art/ui/grabber.svg")
	t.set_icon(&"grabber", &"HSlider", grabber)
	t.set_icon(&"grabber_highlight", &"HSlider", grabber)
	var slider_focus := box(Color(ACCENT_SOFT, 0.6), 10, 3, ACCENT_INK, 0)
	slider_focus.set_expand_margin_all(8.0)
	t.set_stylebox(&"focus", &"HSlider", slider_focus)

	t.set_stylebox(&"normal", &"CheckButton", box(Color(1, 1, 1, 0.0), 12, 2, Color(INK, 0.15)))
	t.set_stylebox(&"focus", &"CheckButton", box(ACCENT_SOFT, 12, 3, ACCENT_INK))
	t.set_stylebox(&"hover", &"CheckButton", box(Color(1, 1, 1, 0.0), 12, 2, ACCENT))
	t.set_stylebox(&"pressed", &"CheckButton", box(Color(1, 1, 1, 0.0), 12, 2, Color(INK, 0.15)))
	t.set_stylebox(&"hover_pressed", &"CheckButton", box(Color(1, 1, 1, 0.0), 12, 2, ACCENT))
	var on: Texture2D = load("res://art/ui/toggle_on.svg")
	var off: Texture2D = load("res://art/ui/toggle_off.svg")
	for suffix in ["", "_mirrored", "_disabled"]:
		t.set_icon(StringName("checked" + suffix), &"CheckButton", on)
		t.set_icon(StringName("unchecked" + suffix), &"CheckButton", off)
	t.set_color(&"font_color", &"CheckButton", INK)
	t.set_color(&"font_focus_color", &"CheckButton", INK)
	t.set_color(&"font_hover_color", &"CheckButton", INK)
	t.set_color(&"font_pressed_color", &"CheckButton", INK)

	t.set_stylebox(&"panel", &"ScrollContainer", StyleBoxEmpty.new())
	return t


## A label with common settings.
static func label(text: String, size: int = 22, color: Color = INK, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", maxi(size, MIN_TEXT))
	if size >= TITLE_SIZE:
		l.add_theme_font_override(&"font", TITLE_FONT)
	l.add_theme_color_override(&"font_color", color)
	l.horizontal_alignment = align
	return l


static func button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 52)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func() -> void:
		Sfx.play("ui_accept", 0.0, -4.0)
		on_pressed.call())
	b.focus_entered.connect(func() -> void:
		Sfx.play("ui_move", 0.0, -10.0)
		_pop(b, 1.04))
	b.focus_exited.connect(func() -> void: _pop(b, 1.0))
	return b


## Small springy scale on the focused button; skipped with "reduce motion".
static func _pop(c: Control, target: float) -> void:
	if not c.is_inside_tree():
		return
	if c.has_meta(&"pop_tween"):
		var prev: Variant = c.get_meta(&"pop_tween")
		if prev is Tween:
			(prev as Tween).kill()
	c.pivot_offset = c.size * 0.5
	var to := Vector2.ONE * (target if motion() > 0.0 else 1.0)
	var tw := c.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(c, "scale", to, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	c.set_meta(&"pop_tween", tw)


## Fade + slight grow when a panel appears. Call right after making it visible.
static func pop_in(c: Control) -> void:
	c.modulate.a = 1.0
	c.scale = Vector2.ONE
	if motion() <= 0.0 or not c.is_inside_tree():
		return
	c.modulate.a = 0.0
	c.scale = Vector2.ONE * 0.95
	await c.get_tree().process_frame
	if not is_instance_valid(c):
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(c, "modulate:a", 1.0, 0.18)
	tw.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Wires a vertical list of controls for gamepad/keyboard focus (wraps around).
static func chain_focus(controls: Array[Control]) -> void:
	var n := controls.size()
	for i in n:
		var c := controls[i]
		c.focus_mode = Control.FOCUS_ALL
		c.focus_neighbor_top = c.get_path_to(controls[(i - 1 + n) % n])
		c.focus_neighbor_bottom = c.get_path_to(controls[(i + 1) % n])
		c.focus_previous = c.focus_neighbor_top
		c.focus_next = c.focus_neighbor_bottom


## Gentle looping motion (bobbing, drifting) scaled to the "reduce motion" option.
static func motion() -> float:
	return 0.0 if GameState.reduce_motion else 1.0


## Font size for reading text (dialogue, popups) with the "large text" option.
static func read_size(base: int) -> int:
	return int(round(base * (1.28 if GameState.large_text else 1.0)))


## True for any "confirm/advance" press from either player (pads or keyboard).
static func is_advance(event: InputEvent) -> bool:
	for a: StringName in [&"ui_accept", &"p1_jump", &"p2_jump", &"p1_interact", &"p2_interact"]:
		if event.is_action_pressed(a, false, true):
			return true
	return false


static func is_back(event: InputEvent) -> bool:
	return event.is_action_pressed(&"ui_cancel", false, true)


static func is_pause(event: InputEvent) -> bool:
	return event.is_action_pressed(&"p1_pause", false, true) or event.is_action_pressed(&"p2_pause", false, true)
