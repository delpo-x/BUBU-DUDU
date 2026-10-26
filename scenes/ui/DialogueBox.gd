class_name DialogueBox
extends Control
## Dialogue service (group "dialogue_service"). play_dialogue(id) is a coroutine:
## it locks both players, shows each line with a typewriter effect and returns when
## the last line is dismissed. Either player advances with Jump (A) or Interact (B):
## the first press completes the line, the second goes to the next one.
## Requests made while a dialogue is showing are queued.

signal line_shown(index: int)
signal finished(id: StringName)

const SPEAKERS := {
	"bubu": {"name": "Bubu", "color": UiTheme.BUBU, "side": 0},
	"dudu": {"name": "Dudu", "color": UiTheme.DUDU, "side": 1},
	"both": {"name": "Bubu & Dudu", "color": UiTheme.ACCENT_INK, "side": 2},
	"narr": {"name": "", "color": UiTheme.MUTED, "side": 2},
}

const PORTRAITS := {
	"bubu": {
		"open": preload("res://art/characters/bubu/portrait_open.svg"),
		"blink": preload("res://art/characters/bubu/portrait_blink.svg"),
		"happy": preload("res://art/characters/bubu/portrait_happy.svg"),
	},
	"dudu": {
		"open": preload("res://art/characters/dudu/portrait_open.svg"),
		"blink": preload("res://art/characters/dudu/portrait_blink.svg"),
		"happy": preload("res://art/characters/dudu/portrait_happy.svg"),
	},
}
const NEXT_ICON := preload("res://art/ui/next.svg")
const PORTRAIT_SIZE := 96.0
## Box height (normal / large text) and its gap from the screen edge.
const BOX_H := 172.0
const BOX_H_LARGE := 214.0
const EDGE := 24.0

## Seconds the first press of a line is ignored (prevents skipping by accident).
@export var min_line_time: float = 0.18

var _busy: bool = false
var _panel: PanelContainer
var _name_label: Label
var _text: RichTextLabel
var _arrow: TextureRect
var _portrait: Control
var _lines: Array = []
var _index: int = 0
var _visible_chars: float = 0.0
var _line_time: float = 0.0
var _advance_requested: bool = false
var _speaker_side: int = 2
var _speaker_color: Color = UiTheme.MUTED
var _t: float = 0.0
var _at_top: bool = false
var _blink: float = 2.5
var _drawn_face: String = ""
## Optional sticker mood of the current line ("m": "grudge" -> art/stickers/<speaker>_grudge).
var _mood: String = ""
var _speaker: String = "narr"
var _plain: String = ""
var _both_turn: int = 0


func _ready() -> void:
	add_to_group(&"dialogue_service")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override(&"panel", UiTheme.box(UiTheme.PANEL, 20, 4, UiTheme.ACCENT, 26))
	add_child(_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 6)
	_panel.add_child(v)
	_name_label = UiTheme.label("", 22, UiTheme.ACCENT_INK)
	v.add_child(_name_label)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.custom_minimum_size = Vector2(0, 96)
	_text.add_theme_color_override(&"default_color", UiTheme.INK)
	_text.add_theme_constant_override(&"line_separation", 6)
	v.add_child(_text)
	# "Press to continue" marker: a vector arrow, not a font glyph (web fonts may lack it).
	_arrow = TextureRect.new()
	_arrow.texture = NEXT_ICON
	_arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_arrow.custom_minimum_size = Vector2(22, 22)
	_arrow.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(_arrow)

	_portrait = Control.new()
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait.draw.connect(_draw_portrait)
	add_child(_portrait)
	_apply_layout()
	visible = false


func is_busy() -> bool:
	return _busy


func play_dialogue(id: StringName) -> void:
	var lines := GameState.get_dialogue(id)
	if lines.is_empty():
		if id != &"":
			push_warning("DialogueBox: unknown dialogue id")
		return
	await play_lines(lines, id)


## Plays raw lines ([{"s": speaker, "t": text}, ...]); used for contextual lines.
func play_lines(lines: Array, id: StringName = &"") -> void:
	while _busy:
		await finished
	if lines.is_empty():
		return
	_busy = true
	_lines = lines
	_index = 0
	_set_players_locked(true)
	_apply_layout()
	visible = true
	_show_line()
	while _index < _lines.size():
		await get_tree().process_frame
	visible = false
	# Unlock one frame later so the dismissing press does not also make a player jump.
	await get_tree().process_frame
	_set_players_locked(false)
	_busy = false
	finished.emit(id)


func _set_players_locked(locked: bool) -> void:
	for p in CompUtil.players(get_tree()):
		p.set_controls_enabled(not locked)
		if locked:
			p.velocity.x = 0.0


func _show_line() -> void:
	var line: Dictionary = _lines[_index] if _lines[_index] is Dictionary else {}
	var who := String(line.get("s", "narr"))
	var info: Dictionary = SPEAKERS.get(who, {"name": who.capitalize(), "color": UiTheme.MUTED, "side": 2})
	_name_label.text = String(info["name"])
	_name_label.visible = _name_label.text != ""
	_speaker_color = info["color"]
	_speaker_side = int(info["side"])
	_name_label.add_theme_color_override(&"font_color", _speaker_color)
	_mood = String(line.get("m", ""))
	var body := String(line.get("t", ""))
	_text.text = "[i]%s[/i]" % body if who == "narr" else body
	_visible_chars = 0.0
	_text.visible_characters = 0
	_line_time = 0.0
	_arrow.modulate.a = 0.0
	Sfx.play("text", 0.0, -10.0)
	_speaker = who
	_plain = _text.get_parsed_text()
	if _mood != "" and who != "narr":
		for w: String in (["bubu", "dudu"] if who == "both" else [who]):
			Voices.emote(w, _mood)
	_portrait.queue_redraw()
	line_shown.emit(_index)


func _process(delta: float) -> void:
	_t += delta
	if not _busy:
		return
	_line_time += delta
	var total := _text.get_total_character_count()
	var speed := GameState.text_speed
	if speed <= 0.0:
		_visible_chars = total
	else:
		var before := int(_visible_chars)
		_visible_chars = minf(_visible_chars + speed * delta, total)
		if int(_visible_chars) != before:
			_voice_tick(before, int(_visible_chars))
	_text.visible_characters = int(_visible_chars)
	_arrow.modulate.a = (0.0 if _visible_chars < total else 1.0) * (1.0 - 0.45 * UiTheme.motion() * (0.5 + 0.5 * sin(_t * 6.0)))
	# Portrait blink: a short closed-eyes frame every few seconds.
	_blink -= delta
	if _blink < -0.13:
		_blink = randf_range(2.2, 4.5)
	if _face() != _drawn_face or _face() == "happy" or _mood != "":
		_portrait.queue_redraw()
	if _advance_requested:
		_advance_requested = false
		if _visible_chars < total:
			_visible_chars = total
		else:
			_index += 1
			if _index < _lines.size():
				_show_line()


func _unhandled_input(event: InputEvent) -> void:
	if not _busy or not visible or get_tree().paused:
		return
	if UiTheme.is_advance(event) and _line_time >= min_line_time:
		_advance_requested = true
		get_viewport().set_input_as_handled()


## Test hook: advances as if a player pressed A.
func advance() -> void:
	_line_time = maxf(_line_time, min_line_time)
	_advance_requested = true


## Box size and side for this dialogue: text size option, and top or bottom of the screen,
## whichever hides less of the two characters (decided once, so the box never jumps).
func _apply_layout() -> void:
	var fs := UiTheme.read_size(25)
	_text.add_theme_font_size_override(&"normal_font_size", fs)
	_text.add_theme_font_size_override(&"italics_font_size", fs)
	_name_label.add_theme_font_size_override(&"font_size", UiTheme.read_size(22))
	var h := BOX_H_LARGE if GameState.large_text else BOX_H
	_at_top = _players_covered(false, h) > _players_covered(true, h)
	_panel.anchor_left = 0.12
	_panel.anchor_right = 0.88
	_panel.offset_left = 0.0
	_panel.offset_right = 0.0
	if _at_top:
		_panel.anchor_top = 0.0
		_panel.anchor_bottom = 0.0
		_panel.offset_top = EDGE
		_panel.offset_bottom = EDGE + h
	else:
		_panel.anchor_top = 1.0
		_panel.anchor_bottom = 1.0
		_panel.offset_top = -EDGE - h
		_panel.offset_bottom = -EDGE
	_portrait.queue_redraw()


## How many players the box (plus portrait strip) would cover at the top or bottom.
func _players_covered(top: bool, h: float) -> int:
	var vp := get_viewport_rect().size
	var reach := EDGE + h + PORTRAIT_SIZE * 0.8
	var n := 0
	for p in CompUtil.players(get_tree()):
		var y := p.get_global_transform_with_canvas().origin.y
		if top and y - 40.0 < reach:
			n += 1
		elif not top and y + 34.0 > vp.y - reach:
			n += 1
	return n


func _draw_portrait() -> void:
	if not visible:
		return
	# Speaker portrait (vector head from the character art) at the box's corner.
	var r := _panel.get_global_rect()
	var sz := Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	var y := r.end.y - 14.0 if _at_top else r.position.y - sz.y + 14.0
	var face := _face()
	_drawn_face = face
	var left := Vector2(r.position.x + 24.0, y)
	var right := Vector2(r.end.x - 24.0 - sz.x, y)
	match _speaker_side:
		0:
			_draw_head("bubu", left, sz, face)
		1:
			_draw_head("dudu", right, sz, face)
		_:
			var duo := Stickers.frame("both_" + _mood, _t) if _mood != "" else null
			if duo != null:
				var c := Vector2(r.get_center().x, y + sz.y * 0.5)
				_portrait.draw_texture_rect(duo, Stickers.fit(duo, c, Vector2(sz.x * 2.6, sz.y * 1.15)), false)
			elif _name_label.text != "":
				_draw_head("bubu", left, sz, face)
				_draw_head("dudu", right, sz, face)


## Babble for the letters just revealed: the speaker's voice (both take turns on shared
## lines), the old blip for the narrator or with voices off.
func _voice_tick(before: int, now: int) -> void:
	if _speaker == "narr" or not Voices.enabled():
		if now / 6 != before / 6:
			Sfx.play("text", 0.08, -16.0)
		return
	for i in range(before + 1, now + 1):
		var who := _speaker
		if who == "both":
			_both_turn += 1
			who = "bubu" if (_both_turn / 4) % 2 == 0 else "dudu"
		Voices.speak(who, _plain.substr(0, i), _plain, _mood)


## Face for the current portrait: shared lines smile, single speakers blink now and then.
func _face() -> String:
	if _speaker_side == 2:
		return "happy"
	return "blink" if _blink <= 0.0 else "open"


func _draw_head(who: String, pos: Vector2, sz: Vector2, face: String) -> void:
	_portrait.draw_circle(pos + sz * 0.5 + Vector2(0, 4), sz.x * 0.5, Color(0.3, 0.15, 0.2, 0.18))
	# A line's mood sticker, or the laugh on shared happy lines, replaces the still head.
	var anim: Texture2D = null
	if _mood != "":
		anim = Stickers.frame(who + "_" + _mood, _t)
	elif face == "happy":
		anim = Stickers.frame(who + "_laugh", _t)
	if anim != null:
		_portrait.draw_texture_rect(anim, Stickers.fit(anim, pos + sz * 0.5, sz * 1.15), false)
		return
	var tex: Texture2D = PORTRAITS[who][face]
	_portrait.draw_texture_rect(tex, Rect2(pos, sz), false)
