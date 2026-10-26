class_name PauseMenu
extends Control
## Pause menu (Start on either pad, Esc / Backspace on keyboard).
## Resume, restart room, gentle hint, options, memory album, back to title.
## "Skip room" appears only after a long time in the same room (safety net).

signal resume_requested
signal restart_requested
signal skip_requested
signal quit_requested

@export var skip_after_minutes: float = 12.0

var _nap: StickerView
var _main: PanelContainer
var _buttons: Array[Control] = []
var _hint_label: Label
var _skip_button: Button
var _hint_button: Button
var _options: OptionsPanel
var _album: AlbumPanel
var _confirm_quit: bool = false
var _quit_button: Button
var hint_text: String = ""
var room_time: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.get_theme()
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.06, 0.08, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_main = PanelContainer.new()
	center.add_child(_main)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	_main.add_child(v)
	v.add_child(UiTheme.label("Pausa", 40, UiTheme.ACCENT_INK, HORIZONTAL_ALIGNMENT_CENTER))

	_buttons.append(UiTheme.button("Riprendi", func() -> void: resume_requested.emit()))
	_buttons.append(UiTheme.button("Ricomincia la stanza", func() -> void: restart_requested.emit()))
	_hint_button = UiTheme.button("Un piccolo aiuto", _show_hint)
	_buttons.append(_hint_button)
	_skip_button = UiTheme.button("Salta questa stanza", func() -> void: skip_requested.emit())
	_buttons.append(_skip_button)
	_buttons.append(UiTheme.button("Opzioni", _open_options))
	_buttons.append(UiTheme.button("Album dei ricordi", _open_album))
	_quit_button = UiTheme.button("Torna al titolo", _quit)
	_buttons.append(_quit_button)
	for b in _buttons:
		v.add_child(b)
	_hint_label = UiTheme.label("", 20, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.custom_minimum_size = Vector2(520, 0)
	_hint_label.visible = false
	v.add_child(_hint_label)
	v.add_child(UiTheme.label("Si salva da solo a ogni stanza, alle lanterne e in pausa.", 16, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_nap = StickerView.new("bubu_bed", Vector2(0, 110))
	v.add_child(_nap)

	_options = OptionsPanel.new()
	_options.visible = false
	center.add_child(_options)
	_options.closed.connect(_back_to_main)
	_album = AlbumPanel.new()
	_album.visible = false
	center.add_child(_album)
	_album.closed.connect(_back_to_main)
	visible = false


func open() -> void:
	visible = true
	_confirm_quit = false
	_quit_button.text = "Torna al titolo"
	_hint_label.visible = false
	_nap.visible = true
	_hint_button.disabled = hint_text == ""
	_skip_button.visible = room_time >= skip_after_minutes * 60.0
	var shown: Array[Control] = []
	for b in _buttons:
		if b.visible and not (b as Button).disabled:
			shown.append(b)
	UiTheme.chain_focus(shown)
	_main.visible = true
	_options.visible = false
	_album.visible = false
	shown[0].grab_focus()


func close() -> void:
	visible = false


func _show_hint() -> void:
	_hint_label.text = hint_text
	_hint_label.visible = true
	_nap.visible = false


func _open_options() -> void:
	_main.visible = false
	_options.open()


func _open_album() -> void:
	_main.visible = false
	_album.open()


func _back_to_main() -> void:
	_main.visible = true
	_buttons[0].grab_focus()


func _quit() -> void:
	if not _confirm_quit:
		_confirm_quit = true
		_quit_button.text = "Sicuri? (premi di nuovo)"
		return
	quit_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _main.visible:
		return
	if UiTheme.is_back(event) or UiTheme.is_pause(event):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_back", 0.0, -4.0)
		resume_requested.emit()
