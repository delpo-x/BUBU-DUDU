class_name OptionsPanel
extends PanelContainer
## Options: volumes, text speed, character lines, large text, reduced motion, fullscreen. Changes apply and save immediately.
## Navigable with either pad (D-pad/stick + A, B to go back).

signal closed

var _first: Control


func _ready() -> void:
	theme = UiTheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(820, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	add_child(v)
	v.add_child(UiTheme.label("Opzioni", 36, UiTheme.ACCENT_INK, HORIZONTAL_ALIGNMENT_CENTER))

	var focusables: Array[Control] = []
	focusables.append(_slider_row(v, "Volume generale", GameState.master_volume, func(x: float) -> void: GameState.master_volume = x))
	focusables.append(_slider_row(v, "Musica", GameState.music_volume, func(x: float) -> void: GameState.music_volume = x))
	focusables.append(_slider_row(v, "Effetti", GameState.sfx_volume, func(x: float) -> void: GameState.sfx_volume = x))
	# Text speed: right = faster; the far right is "instant" (0).
	var speed_value := 1.0 if GameState.text_speed <= 0.0 else clampf((GameState.text_speed - 15.0) / 90.0, 0.0, 0.95)
	focusables.append(_slider_row(v, "Velocità del testo", speed_value, func(x: float) -> void:
		GameState.text_speed = 0.0 if x >= 0.99 else 15.0 + x * 90.0))

	# Switches in two columns so the panel fits a 720 px screen.
	var switches := GridContainer.new()
	switches.columns = 2
	switches.add_theme_constant_override(&"h_separation", 12)
	switches.add_theme_constant_override(&"v_separation", 8)
	v.add_child(switches)
	focusables.append(_toggle(switches, "Voci dei personaggi", GameState.voices_enabled, func(on: bool) -> void: GameState.voices_enabled = on))
	focusables.append(_toggle(switches, "Battute dei personaggi", GameState.barks_enabled, func(on: bool) -> void: GameState.barks_enabled = on))
	focusables.append(_toggle(switches, "Testo grande", GameState.large_text, func(on: bool) -> void: GameState.large_text = on))
	focusables.append(_toggle(switches, "Riduci movimento", GameState.reduce_motion, func(on: bool) -> void: GameState.reduce_motion = on))

	if not OS.has_feature("web"):
		focusables.append(_toggle(switches, "Schermo intero", GameState.fullscreen, func(on: bool) -> void: GameState.fullscreen = on))

	var keys := UiTheme.button("Assegna i tasti…", _open_controls)
	v.add_child(keys)
	focusables.append(keys)

	var back := UiTheme.button("Indietro", _close)
	v.add_child(back)
	focusables.append(back)
	UiTheme.chain_focus(focusables)
	_first = focusables[0]


func open() -> void:
	visible = true
	_first.grab_focus()


func _toggle(parent: Control, text: String, on: bool, setter: Callable) -> CheckButton:
	var b := CheckButton.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.button_pressed = on
	b.toggled.connect(func(value: bool) -> void:
		setter.call(value)
		GameState.save_settings()
		Sfx.play("ui_move", 0.0, -6.0))
	parent.add_child(b)
	return b


func _slider_row(parent: Control, text: String, value: float, setter: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 18)
	parent.add_child(row)
	var l := UiTheme.label(text, 22)
	l.custom_minimum_size = Vector2(240, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(300, 32)
	s.value_changed.connect(func(x: float) -> void:
		setter.call(x)
		GameState.save_settings()
		Sfx.play("ui_move", 0.0, -6.0))
	row.add_child(s)
	return s


var _controls: ControlsPanel


## The remapping screen opens in place of this panel and comes back to it.
func _open_controls() -> void:
	if _controls == null:
		_controls = ControlsPanel.new()
		_controls.visible = false
		get_parent().add_child(_controls)
		_controls.closed.connect(func() -> void:
			visible = true
			_first.grab_focus())
	visible = false
	_controls.open()


func _close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and UiTheme.is_back(event):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_back", 0.0, -4.0)
		_close()
