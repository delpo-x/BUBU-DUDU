class_name AlbumPanel
extends PanelContainer
## Memory album: every keepsake found so far, grouped by chapter. Focus a title to read
## it on the right. Locked entries show as "???".

const HEART_ICON := preload("res://art/ui/heart.svg")

signal closed

var _list: VBoxContainer
var _detail_title: Label
var _detail_text: Label
var _count: Label
var _back: Button


func _ready() -> void:
	theme = UiTheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(1000, 560)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	add_child(v)
	v.add_child(UiTheme.label("Album dei ricordi", 36, UiTheme.ACCENT_INK, HORIZONTAL_ALIGNMENT_CENTER))
	_count = UiTheme.label("", 18, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_count)
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override(&"separation", 24)
	v.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	h.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(detail)
	_detail_title = UiTheme.label("", 28)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_detail_title)
	_detail_text = UiTheme.label("", 21, UiTheme.INK)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.custom_minimum_size = Vector2(520, 0)
	detail.add_child(_detail_text)
	_back = UiTheme.button("Indietro", _close)
	v.add_child(_back)


func open() -> void:
	visible = true
	for c in _list.get_children():
		c.queue_free()
	await get_tree().process_frame
	var focusables: Array[Control] = []
	var total := 0
	var found := 0
	for ch in GameState.chapter_count():
		var chapter := GameState.get_chapter(ch)
		var ids := GameState.memories_in_chapter(ch)
		if ids.is_empty():
			continue
		var unlocked := ch <= GameState.unlocked_chapter
		_list.add_child(UiTheme.label(String(chapter.get("title", "")) if unlocked else "???", 20, UiTheme.ACCENT_INK))
		for id in ids:
			total += 1
			var def: Dictionary = GameState.memory_defs.get(id, {})
			var has := GameState.has_memory(id)
			if has:
				found += 1
			var b := Button.new()
			b.text = String(def.get("title", id)) if has else "???"
			# Found memories carry the vector heart; locked ones keep the same indent.
			b.icon = HEART_ICON if has else null
			b.expand_icon = false
			b.add_theme_constant_override(&"icon_max_width", 22)
			b.add_theme_constant_override(&"h_separation", 10)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(380, 40)
			b.add_theme_font_size_override(&"font_size", 20)
			b.focus_entered.connect(func() -> void:
				Sfx.play("ui_move", 0.0, -10.0)
				_detail_title.text = String(def.get("title", "")) if has else "???"
				_detail_text.text = String(def.get("text", "")) if has else "Un ricordo ancora da trovare.")
			_list.add_child(b)
			focusables.append(b)
	_count.text = "%d / %d ricordi" % [found, total]
	focusables.append(_back)
	UiTheme.chain_focus(focusables)
	focusables[0].grab_focus()


func _close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and UiTheme.is_back(event):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_back", 0.0, -4.0)
		_close()
