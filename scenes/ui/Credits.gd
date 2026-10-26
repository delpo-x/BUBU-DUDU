class_name Credits
extends Control
## End credits: slow scroll over a warm backdrop, then back to the title screen.
## Any advance press speeds it up; Start/B skips to the end.

const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"
const CREDITS_PATH := "res://data/credits.json"
## Illustrations from the vector pack, spread evenly through the scrolling credits.
const PICTURES: Array[String] = [
	"res://art/illustrations/01_abbraccio.svg",
	"res://art/illustrations/05_regalo.svg",
	"res://art/illustrations/04_sotto_coperta.svg",
	"res://art/illustrations/06_bacio.svg",
	"sticker:bubu_helmet",
	"sticker:bubu_back",
]

@export var scroll_speed: float = 46.0

var _column: VBoxContainer
var _y: float = 0.0
var _done: bool = false
var _fast: bool = false


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	Sfx.play_music("credits")
	var bg := ColorRect.new()
	bg.color = Color(0.17, 0.13, 0.2)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override(&"separation", 18)
	_column.custom_minimum_size = Vector2(900, 0)
	add_child(_column)
	var data: Variant = null
	if FileAccess.file_exists(CREDITS_PATH):
		data = JSON.parse_string(FileAccess.get_file_as_string(CREDITS_PATH))
	var lines: Array = data if data is Array else []
	var every := maxi(floori(float(lines.size()) / PICTURES.size()), 1)
	var pic := 0
	for i in lines.size():
		var entry: Variant = lines[i]
		if i > 0 and i % every == 0 and pic < PICTURES.size():
			_column.add_child(_picture(PICTURES[pic]))
			pic += 1
		var d: Dictionary = entry if entry is Dictionary else {"t": str(entry)}
		var size := int(d.get("size", 26))
		var col := UiTheme.ACCENT_SOFT if d.get("accent", false) else Color(1, 1, 1, 0.9)
		var l := UiTheme.label(String(d.get("t", "")), size, col, HORIZONTAL_ALIGNMENT_CENTER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(900, 0)
		_column.add_child(l)
	while pic < PICTURES.size():
		_column.add_child(_picture(PICTURES[pic]))
		pic += 1
	var total := 0
	for ch in GameState.chapter_count():
		total += GameState.memories_in_chapter(ch).size()
	var stats := UiTheme.label("Ricordi trovati: %d / %d   ·   Tempo insieme: %s" % [GameState.memories.size(), total, GameState.format_time(GameState.play_time)], 22, UiTheme.ACCENT_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	stats.custom_minimum_size = Vector2(900, 0)
	_column.add_child(stats)
	_y = get_viewport_rect().size.y + 40.0


func _picture(path: String) -> Control:
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(900, 340)
	if path.begins_with("sticker:"):
		box.add_child(StickerView.new(path.trim_prefix("sticker:"), Vector2(300, 300)))
		return box
	var tex := TextureRect.new()
	tex.texture = load(path)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.custom_minimum_size = Vector2(300, 300)
	box.add_child(tex)
	return box


func _process(delta: float) -> void:
	if _done:
		return
	var vp := get_viewport_rect().size
	_y -= scroll_speed * delta * (5.0 if _fast else 1.0)
	_column.position = Vector2((vp.x - _column.size.x) * 0.5, _y)
	if _y + _column.size.y < vp.y * 0.5 - 40.0:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if UiTheme.is_pause(event) or UiTheme.is_back(event):
		_finish()
	elif UiTheme.is_advance(event):
		_fast = true
	elif event is InputEventJoypadButton or event is InputEventKey:
		if not event.is_pressed():
			_fast = false


func _finish() -> void:
	if _done:
		return
	_done = true
	await get_tree().create_timer(1.5).timeout
	get_tree().change_scene_to_file(MENU_SCENE)
