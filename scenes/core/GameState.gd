extends Node
## Autoload "GameState": progress, collected memories, flags and settings.
##
## Progress is plain data, versioned and written atomically (temp file + rename,
## previous save kept as .bak). Settings live in a separate ConfigFile so a corrupt
## save never resets the options. On web, user:// is backed by IndexedDB.

signal progress_changed
signal settings_changed
## A memory was collected for the first time.
signal memory_collected(id: String)

const SAVE_VERSION := 1
## Overridable so tests never touch the real save.
var save_path: String = "user://save.json"
const SETTINGS_PATH := "user://settings.cfg"
const CHAPTERS_PATH := "res://data/chapters.json"
const MEMORIES_PATH := "res://data/memories.json"
const BARKS_PATH := "res://data/dialogue/barks.json"
const COMMON_DIALOGUE_PATH := "res://data/dialogue/common.json"

## Chapter definitions loaded from data/chapters.json.
var chapters: Array = []
## Memory definitions loaded from data/memories.json (id -> {title, text, chapter}).
var memory_defs: Dictionary = {}
## Dialogue id -> Array of lines ({"s": speaker, "t": text}), from every chapter file.
var dialogues: Dictionary = {}
## Contextual line pools (pool name -> Array of short dialogues), see BarkDirector.
var barks: Dictionary = {}

# --- Progress (saved) ---
var chapter_index: int = 0
var room_index: int = 0
var unlocked_chapter: int = 0
var memories: Dictionary = {}      # memory id -> true
var flags: Dictionary = {}         # string -> Variant (dialogue seen, cozy spots, ...)
var play_time: float = 0.0
var game_completed: bool = false
## Mid-room save (lantern, cozy spot, pause, quit): {chapter, room, room_time, players,
## state}. Empty when the last save is a plain room entry. See Game.save_checkpoint().
var room_snapshot: Dictionary = {}

# --- Settings (saved separately) ---
var master_volume: float = 0.9
var music_volume: float = 0.7
var sfx_volume: float = 0.9
var fullscreen: bool = false
## Characters per second for dialogue text. 0 = instant.
var text_speed: float = 45.0
## Contextual character lines on/off (options menu).
var barks_enabled: bool = true
## Characters drawn with their animated stickers instead of the vector cut-out (options).
var sticker_characters: bool = true
## Babbling voices for Bubu and Dudu (options menu).
var voices_enabled: bool = true
## Accessibility: stops decorative looping motion (menu drift, bobbing, pulsing prompts)
## and softens squash & stretch.
var reduce_motion: bool = false
## Accessibility: bigger dialogue and popup text.
var large_text: bool = false

## True while a game session (not the menu) is running; counts play time.
var in_game: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# World labels drawn with ThemeDB.fallback_font (player tags, signs) use the UI font too.
	ThemeDB.fallback_font = UiTheme.BODY_FONT
	_load_data()
	load_settings()
	load_progress()


func _process(delta: float) -> void:
	if in_game and not get_tree().paused:
		play_time += delta


# --- Static data -------------------------------------------------------------

func _load_data() -> void:
	var ch: Variant = _read_json(CHAPTERS_PATH)
	chapters = ch if ch is Array else []
	var mem: Variant = _read_json(MEMORIES_PATH)
	memory_defs = mem if mem is Dictionary else {}
	dialogues = {}
	var files: Array[String] = [COMMON_DIALOGUE_PATH]
	for c: Variant in chapters:
		if c is Dictionary and (c as Dictionary).has("dialogue"):
			files.append(String((c as Dictionary)["dialogue"]))
	var bk: Variant = _read_json(BARKS_PATH)
	barks = bk if bk is Dictionary else {}
	for path in files:
		var d: Variant = _read_json(path)
		if d is Dictionary:
			dialogues.merge(d as Dictionary, true)


func has_dialogue(id: StringName) -> bool:
	return dialogues.has(String(id))


func get_dialogue(id: StringName) -> Array:
	var lines: Variant = dialogues.get(String(id), [])
	return lines if lines is Array else []


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("GameState: missing data file " + path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("GameState: invalid JSON in " + path)
	return parsed


func chapter_count() -> int:
	return chapters.size()


func get_chapter(index: int) -> Dictionary:
	if index < 0 or index >= chapters.size():
		return {}
	return chapters[index]


func get_room_path(ch: int, room: int) -> String:
	var rooms: Array = get_chapter(ch).get("rooms", [])
	if room < 0 or room >= rooms.size():
		return ""
	return String(rooms[room])


func room_count(ch: int) -> int:
	var rooms: Array = get_chapter(ch).get("rooms", [])
	return rooms.size()


func memories_in_chapter(ch: int) -> Array[String]:
	var ids: Array[String] = []
	var chapter_id := String(get_chapter(ch).get("id", ""))
	for id: String in memory_defs.keys():
		if String((memory_defs[id] as Dictionary).get("chapter", "")) == chapter_id:
			ids.append(id)
	ids.sort()
	return ids


# --- Progress API ------------------------------------------------------------

func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak")


func new_game() -> void:
	# Memories and unlocked chapters survive a new game: they are rewards, not progress.
	chapter_index = 0
	room_index = 0
	flags = {}
	play_time = 0.0
	room_snapshot = {}
	save_progress()


func start_chapter(index: int) -> void:
	chapter_index = clampi(index, 0, maxi(unlocked_chapter, 0))
	room_index = 0
	room_snapshot = {}
	save_progress()


## Called by the game on every room entry (auto-save).
func set_position(ch: int, room: int) -> void:
	if ch != chapter_index or room != room_index:
		room_snapshot = {}
	chapter_index = ch
	room_index = room
	unlocked_chapter = maxi(unlocked_chapter, ch)
	save_progress()


func complete_chapter(ch: int) -> void:
	unlocked_chapter = maxi(unlocked_chapter, mini(ch + 1, chapter_count() - 1))
	if ch >= chapter_count() - 1:
		game_completed = true
	save_progress()


func collect_memory(id: String) -> bool:
	if memories.get(id, false):
		return false
	memories[id] = true
	flags["stat_last_memory"] = id
	save_progress()
	memory_collected.emit(id)
	return true


func has_memory(id: String) -> bool:
	return bool(memories.get(id, false))


func set_flag(key: String, value: Variant = true) -> void:
	if flags.has(key) and typeof(flags[key]) == typeof(value) and flags[key] == value:
		return
	flags[key] = value
	save_progress()


## Counts something the players did ("falls_bubu", "hugs"...), for dialogue variations
## (see DialogueText). Kept in the save's flags, so a new game starts from zero.
func bump_stat(stat_name: String) -> void:
	set_flag("stat_" + stat_name, int(flags.get("stat_" + stat_name, 0)) + 1)


func get_flag(key: String, default: Variant = false) -> Variant:
	return flags.get(key, default)


func capture() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"chapter_index": chapter_index,
		"room_index": room_index,
		"unlocked_chapter": unlocked_chapter,
		"memories": memories,
		"flags": flags,
		"play_time": play_time,
		"game_completed": game_completed,
		"room_snapshot": room_snapshot,
	}


func apply(data: Dictionary) -> void:
	chapter_index = clampi(int(data.get("chapter_index", 0)), 0, maxi(chapter_count() - 1, 0))
	room_index = maxi(int(data.get("room_index", 0)), 0)
	if room_index >= room_count(chapter_index):
		room_index = 0
	unlocked_chapter = clampi(int(data.get("unlocked_chapter", 0)), 0, maxi(chapter_count() - 1, 0))
	var mem: Variant = data.get("memories", {})
	memories = mem if mem is Dictionary else {}
	var fl: Variant = data.get("flags", {})
	flags = fl if fl is Dictionary else {}
	play_time = float(data.get("play_time", 0.0))
	game_completed = bool(data.get("game_completed", false))
	var snap: Variant = data.get("room_snapshot", {})
	room_snapshot = snap if snap is Dictionary else {}


func save_progress() -> void:
	_write_atomic(save_path, JSON.stringify(capture(), "\t"))
	progress_changed.emit()


func load_progress() -> bool:
	for path in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		# JSON instance instead of JSON.parse_string: a damaged save is expected, not an engine error.
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary:
			apply(_migrate(json.data))
			return true
		push_warning("GameState: unreadable save at " + path)
	return false


func delete_progress() -> void:
	for path in [save_path, save_path + ".bak", save_path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	chapter_index = 0
	room_index = 0
	unlocked_chapter = 0
	memories = {}
	flags = {}
	play_time = 0.0
	game_completed = false
	room_snapshot = {}
	progress_changed.emit()


func _migrate(data: Dictionary) -> Dictionary:
	# Version 1 is the first schema; future versions upgrade here step by step.
	var version := int(data.get("version", 1))
	if version > SAVE_VERSION:
		push_warning("GameState: save from a newer version, loading what we can")
	return data


func _write_atomic(path: String, text: String) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("GameState: cannot write " + tmp)
		return
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	DirAccess.rename_absolute(tmp, path)


# --- Settings ----------------------------------------------------------------

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		master_volume = float(cfg.get_value("audio", "master", master_volume))
		music_volume = float(cfg.get_value("audio", "music", music_volume))
		sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
		fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
		text_speed = float(cfg.get_value("game", "text_speed", text_speed))
		barks_enabled = bool(cfg.get_value("game", "barks", barks_enabled))
		voices_enabled = bool(cfg.get_value("audio", "voices", voices_enabled))
		sticker_characters = bool(cfg.get_value("video", "sticker_characters", sticker_characters))
		reduce_motion = bool(cfg.get_value("access", "reduce_motion", reduce_motion))
		large_text = bool(cfg.get_value("access", "large_text", large_text))
	apply_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("game", "text_speed", text_speed)
	cfg.set_value("game", "barks", barks_enabled)
	cfg.set_value("audio", "voices", voices_enabled)
	cfg.set_value("video", "sticker_characters", sticker_characters)
	cfg.set_value("access", "reduce_motion", reduce_motion)
	cfg.set_value("access", "large_text", large_text)
	cfg.save(SETTINGS_PATH)
	apply_settings()


func apply_settings() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)
	if not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
	settings_changed.emit()


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 3600, (s / 60) % 60]
