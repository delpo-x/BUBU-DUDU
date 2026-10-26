class_name MainMenu
extends Control
## Title screen: continue, new game, chapter select, album, controls, options, quit.
## Fully navigable with either gamepad.

const GAME_SCENE := "res://scenes/core/Game.tscn"

var _main: PanelContainer
var _main_buttons: Array[Control] = []
var _chapters: PanelContainer
var _chapters_list: VBoxContainer
var _controls: PanelContainer
var _options: OptionsPanel
var _album: AlbumPanel
var _new_button: Button
var _confirm_new: bool = false
var _t: float = 0.0
var _art: Control


const LEFT_CARD := preload("res://art/illustrations/03_saluto.svg")
const RIGHT_CARD := preload("res://art/illustrations/02_cuoricini.svg")
const CARD_SIZE := 260.0


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	GameState.in_game = false
	Sfx.play_music("menu")

	_art = Control.new()
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_draw_art)
	add_child(_art)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = 120
	add_child(center)

	var title := UiTheme.label("Bubu & Dudu", 84, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 40
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.add_theme_color_override(&"font_outline_color", UiTheme.ACCENT_INK)
	title.add_theme_constant_override(&"outline_size", 14)
	add_child(title)

	_main = PanelContainer.new()
	center.add_child(_main)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	_main.add_child(v)
	if GameState.has_save():
		_main_buttons.append(UiTheme.button("Continua", _continue))
	_new_button = UiTheme.button("Nuova partita", _new_game)
	_main_buttons.append(_new_button)
	if GameState.unlocked_chapter > 0 or GameState.game_completed:
		_main_buttons.append(UiTheme.button("Capitoli", _open_chapters))
	_main_buttons.append(UiTheme.button("Album dei ricordi", _open_album))
	_main_buttons.append(UiTheme.button("Comandi", _open_controls))
	_main_buttons.append(UiTheme.button("Opzioni", _open_options))
	if not OS.has_feature("web"):
		_main_buttons.append(UiTheme.button("Esci", func() -> void: get_tree().quit()))
	for b in _main_buttons:
		v.add_child(b)
	if GameState.has_save():
		v.add_child(UiTheme.label("Tempo di gioco: %s" % GameState.format_time(GameState.play_time), 16, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))

	_chapters = PanelContainer.new()
	_chapters.visible = false
	center.add_child(_chapters)
	_chapters_list = VBoxContainer.new()
	_chapters_list.add_theme_constant_override(&"separation", 10)
	_chapters.add_child(_chapters_list)

	_controls = _build_controls()
	_controls.visible = false
	center.add_child(_controls)

	_options = OptionsPanel.new()
	_options.visible = false
	center.add_child(_options)
	_options.closed.connect(_show_main)
	_album = AlbumPanel.new()
	_album.visible = false
	center.add_child(_album)
	_album.closed.connect(_show_main)

	UiTheme.chain_focus(_main_buttons)
	_main_buttons[0].grab_focus()


func _process(delta: float) -> void:
	_t += delta
	_art.queue_redraw()


func _show_main() -> void:
	_chapters.visible = false
	_controls.visible = false
	_album.visible = false
	_options.visible = false
	_main.visible = true
	_main_buttons[0].grab_focus()


func _continue() -> void:
	GameState.load_progress()
	_go()


func _new_game() -> void:
	if GameState.has_save() and not _confirm_new:
		_confirm_new = true
		_new_button.text = "Ricominciare? (i ricordi restano)"
		return
	GameState.new_game()
	_go()


func _go() -> void:
	set_process_unhandled_input(false)
	get_tree().change_scene_to_file(GAME_SCENE)


func _open_chapters() -> void:
	for c in _chapters_list.get_children():
		c.queue_free()
	await get_tree().process_frame
	_chapters_list.add_child(UiTheme.label("Capitoli", 36, UiTheme.ACCENT_INK, HORIZONTAL_ALIGNMENT_CENTER))
	var buttons: Array[Control] = []
	for i in GameState.chapter_count():
		var ch := GameState.get_chapter(i)
		var unlocked := i <= GameState.unlocked_chapter
		var b := UiTheme.button("%d. %s" % [i + 1, String(ch.get("title", "")) if unlocked else "???"], func() -> void:
			GameState.start_chapter(i)
			_go())
		b.disabled = not unlocked
		_chapters_list.add_child(b)
		if unlocked:
			buttons.append(b)
	var back := UiTheme.button("Indietro", _show_main)
	_chapters_list.add_child(back)
	buttons.append(back)
	UiTheme.chain_focus(buttons)
	_main.visible = false
	_chapters.visible = true
	buttons[0].grab_focus()


func _open_album() -> void:
	_main.visible = false
	_album.open()


func _open_options() -> void:
	_main.visible = false
	_options.open()


func _open_controls() -> void:
	# Rebuilt each time: the keys may have been changed in Options meanwhile.
	var holder := _controls.get_parent()
	var at := _controls.get_index()
	_controls.queue_free()
	_controls = _build_controls()
	holder.add_child(_controls)
	holder.move_child(_controls, at)
	_main.visible = false
	_controls.visible = true
	(_controls.get_meta(&"back") as Button).grab_focus()


func _build_controls() -> PanelContainer:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	p.add_child(v)
	v.add_child(UiTheme.label("Comandi", 36, UiTheme.ACCENT_INK, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiTheme.label("Primo controller: Bubu  ·  Secondo controller: Dudu", 20, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	# Pad names from Bubu's current buttons (both start the same; Options can change them).
	var jump := Bindings.pad_label(&"p1_jump")
	var assist := Bindings.pad_label(&"p1_assist")
	var rows := [
		["Levetta sinistra", "Muoversi (su/giù per arrampicarsi)"],
		[jump, "Saltare (tienilo premuto per saltare più in alto)"],
		[Bindings.pad_label(&"p1_interact"), "Interagire: leve, pulsanti, cartelli, prendere e posare casse"],
		[assist + " (tocco)", "In spalla al partner / scendere / abbracciarsi"],
		[assist + " (tieni premuto)", "Chiamare il partner vicino a te"],
		[jump + " mentre sei in spalla", "Saltare giù con lo slancio"],
		[Bindings.pad_label(&"p1_pause"), "Pausa (aiuto, ricomincia stanza, opzioni)"],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 28)
	grid.add_theme_constant_override(&"v_separation", 6)
	for r: Array in rows:
		grid.add_child(UiTheme.label(String(r[0]), 21, UiTheme.ACCENT_INK))
		grid.add_child(UiTheme.label(String(r[1]), 21))
	v.add_child(grid)
	var kb := func(p: int) -> String:
		var names: Array[String] = []
		for s in ["left", "right", "up", "down", "jump", "interact", "assist", "pause"]:
			names.append(Bindings.key_label(StringName("p%d_%s" % [p, s])))
		return "%s/%s %s/%s, %s, %s, %s, %s" % names
	v.add_child(UiTheme.label("Tastiera — Bubu: %s  ·  Dudu: %s" % [kb.call(1), kb.call(2)], 16, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiTheme.label("Puoi cambiarli in Opzioni → Assegna i tasti.", 16, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiTheme.label("Non si perde mai: chi cade torna dal partner su un palloncino.", 18, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER))
	var back := UiTheme.button("Indietro", _show_main)
	v.add_child(back)
	p.set_meta(&"back", back)
	return p


func _unhandled_input(event: InputEvent) -> void:
	if UiTheme.is_back(event) and (_chapters.visible or _controls.visible):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_back", 0.0, -4.0)
		_show_main()


func _draw_art() -> void:
	var size := _art.size
	_art.draw_rect(Rect2(Vector2.ZERO, size), Color(0.98, 0.78, 0.7))
	_art.draw_rect(Rect2(Vector2(0, size.y * 0.55), Vector2(size.x, size.y * 0.45)), Color(0.93, 0.66, 0.62))
	for i in 9:
		var m := UiTheme.motion()
		var x := fmod(i * 173.0 + _t * m * (10.0 + i * 2.0), size.x + 200.0) - 100.0
		var y := 90.0 + float(i % 4) * 60.0 + sin(_t + i) * 6.0 * m
		_art.draw_circle(Vector2(x, y), 26.0 + i % 3 * 8.0, Color(1, 1, 1, 0.35))
	var ground := size.y - 70.0
	_art.draw_rect(Rect2(Vector2(0, ground), Vector2(size.x, 70)), Color(0.55, 0.72, 0.5))
	# Two illustrations from the vector pack as tilted cards on either side of the menu.
	var rope := Stickers.frame("dudu_rope", _t)
	_draw_card(rope if rope != null else LEFT_CARD, Vector2(size.x * 0.17, size.y * 0.62), CARD_SIZE, -0.07, 0.0)
	_draw_card(RIGHT_CARD, Vector2(size.x * 0.83, size.y * 0.6), CARD_SIZE, 0.06, 1.3)


func _draw_card(tex: Texture2D, center: Vector2, side: float, angle: float, phase: float) -> void:
	if tex == null:
		return
	var m := UiTheme.motion()
	var bob := sin(_t * 1.6 + phase) * 4.0 * m
	_art.draw_set_transform(center + Vector2(0, bob), angle + sin(_t * 0.9 + phase) * 0.01 * m, Vector2.ONE)
	var r := Rect2(Vector2(-side, -side) * 0.5, Vector2(side, side))
	_art.draw_rect(Rect2(r.position + Vector2(6, 8), r.size), Color(0.45, 0.25, 0.25, 0.18))
	_art.draw_rect(r.grow(8.0), Color(1, 1, 1))
	_art.draw_texture_rect(tex, Stickers.fit(tex, Vector2.ZERO, r.size), false)
	_art.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
