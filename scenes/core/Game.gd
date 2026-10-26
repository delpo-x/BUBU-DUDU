class_name Game
extends Node
## The in-game session. Players and the shared camera persist; rooms are loaded into
## RoomHolder one at a time. Handles transitions, auto-save on room entry, chapter title
## cards and intro/outro dialogues, contextual lines, pause menu, restart and the end of the game.

signal room_entered(chapter: int, room_index: int)

const BUBU_SCENE := preload("res://scenes/characters/Bubu.tscn")
const DUDU_SCENE := preload("res://scenes/characters/Dudu.tscn")
const MENU_SCENE := "res://scenes/ui/MainMenu.tscn"
const CREDITS_SCENE := "res://scenes/ui/Credits.tscn"

## Tests set this to false and drive the game themselves.
@export var autostart: bool = true
## Tests skip title cards and fades.
@export var fast_transitions: bool = false
## Tests keep the completed room loaded instead of moving on.
@export var auto_advance: bool = true

var world: Node2D
var room_holder: Node2D
var players_node: Node2D
var bubu: BasePlayer
var dudu: BasePlayer
var camera: CoopCamera2D
var hud: Hud
var dialogue: DialogueBox
var pause_menu: PauseMenu
var barks: BarkDirector

var room: Room = null
var chapter_index: int = 0
var room_index: int = 0
var room_time: float = 0.0
var _transitioning: bool = false
var _ending: bool = false


func _ready() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	room_holder = Node2D.new()
	room_holder.name = "RoomHolder"
	world.add_child(room_holder)
	players_node = Node2D.new()
	players_node.name = "Players"
	world.add_child(players_node)
	bubu = BUBU_SCENE.instantiate() as BasePlayer
	dudu = DUDU_SCENE.instantiate() as BasePlayer
	players_node.add_child(bubu)
	players_node.add_child(dudu)
	camera = CoopCamera2D.new()
	camera.name = "CoopCamera2D"
	world.add_child(camera)

	var ui := CanvasLayer.new()
	ui.name = "UI"
	ui.layer = 10
	add_child(ui)
	dialogue = DialogueBox.new()
	ui.add_child(dialogue)
	hud = Hud.new()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	ui.add_child(hud)
	pause_menu = PauseMenu.new()
	ui.add_child(pause_menu)
	pause_menu.resume_requested.connect(_resume)
	pause_menu.restart_requested.connect(_restart)
	pause_menu.skip_requested.connect(_skip)
	pause_menu.quit_requested.connect(_quit_to_menu)
	barks = BarkDirector.new()
	barks.name = "BarkDirector"
	add_child(barks)
	barks.setup(self)

	GameState.in_game = true
	if autostart:
		start(GameState.chapter_index, GameState.room_index)


func _exit_tree() -> void:
	GameState.in_game = false
	get_tree().paused = false


func _process(delta: float) -> void:
	if not get_tree().paused and not _transitioning:
		room_time += delta


func is_transitioning() -> bool:
	return _transitioning


func start(ch: int, idx: int) -> void:
	await enter_room(ch, idx, "", true)


## Loads room `idx` of chapter `ch` (fade out, swap, auto-save, title, fade in, intro).
## `path_override` loads another room file in that slot (tests, dev rooms). `resume` picks
## up a mid-room save of this room if there is one (players, puzzle state, time).
func enter_room(ch: int, idx: int, path_override: String = "", resume: bool = false) -> void:
	_transitioning = true
	_set_players_locked(true)
	if not fast_transitions:
		await hud.fade_to(1.0)
	else:
		hud.set_faded(1.0)
	_unload_room()

	var path := path_override if path_override != "" else GameState.get_room_path(ch, idx)
	var packed := load(path) as PackedScene if path != "" and ResourceLoader.exists(path) else null
	if packed == null:
		push_error("Game: cannot load room %d/%d" % [ch, idx])
		_transitioning = false
		_set_players_locked(false)
		return
	chapter_index = ch
	room_index = idx
	room = packed.instantiate() as Room
	room_holder.add_child(room)
	room.completed.connect(_on_room_completed, CONNECT_ONE_SHOT)
	room.checkpoint_reached.connect(save_checkpoint.bind(true))
	camera.level_bounds = room.bounds
	camera.min_zoom = room.camera_min_zoom
	camera.max_zoom = room.camera_max_zoom
	bubu.teleport_to(room.get_spawn(1))
	dudu.teleport_to(room.get_spawn(2))
	bubu.face_towards(dudu.global_position.x + 1.0)
	dudu.face_towards(bubu.global_position.x - 1.0)
	room_time = 0.0
	var snap := GameState.room_snapshot
	if resume and path_override == "" and int(snap.get("chapter", -1)) == ch and int(snap.get("room", -1)) == idx:
		_resume_snapshot(snap)
	camera.snap_to_targets()
	if path_override == "":
		GameState.set_position(ch, idx)

	var chapter := GameState.get_chapter(ch)
	Sfx.play_music(String(chapter.get("music", "ch%d" % (ch + 1))))
	if idx == 0 and not fast_transitions:
		await hud.show_title("Capitolo %d" % (ch + 1), String(chapter.get("title", "")), String(chapter.get("subtitle", "")))
	if not fast_transitions:
		await hud.fade_to(0.0)
	else:
		hud.set_faded(0.0)
	room_entered.emit(ch, idx)

	if idx == 0:
		await _play_once("chapter_intro_%s" % chapter.get("id", ch), StringName(String(chapter.get("intro", ""))))
	await _play_once("room_intro_%s" % room.room_id, room.intro_dialogue)
	_set_players_locked(false)
	_transitioning = false


# --- Mid-room saves ---------------------------------------------------------------------

## Saves where the players are and the state of the room's puzzle, so the next session
## continues from here. Players in the air or on a balloon are saved at the respawn point.
func save_checkpoint(announce: bool = false) -> void:
	if room == null or _transitioning or _ending or room.is_completed():
		return
	var players: Array = []
	for p: BasePlayer in [bubu, dudu]:
		var pos := p.global_position
		if p.state != BasePlayer.State.NORMAL or not p.is_on_floor():
			pos = room.get_checkpoint(p.player_index)
		players.append([pos.x, pos.y])
	GameState.room_snapshot = {
		"chapter": chapter_index, "room": room_index, "room_time": room_time,
		"players": players, "state": room.capture_state(),
	}
	GameState.save_progress()
	if announce:
		hud.show_toast("Partita salvata", 1.6)


func _resume_snapshot(snap: Dictionary) -> void:
	var st: Variant = snap.get("state", {})
	if st is Dictionary:
		room.restore_state(st)
	var ps: Array = snap.get("players", [])
	if ps.size() == 2:
		bubu.teleport_to(Vector2(float(ps[0][0]), float(ps[0][1])))
		dudu.teleport_to(Vector2(float(ps[1][0]), float(ps[1][1])))
	room_time = float(snap.get("room_time", 0.0))


func _play_once(flag: String, id: StringName) -> void:
	if id == &"" or bool(GameState.get_flag(flag)):
		return
	await dialogue.play_dialogue(id)
	GameState.set_flag(flag)


func _unload_room() -> void:
	if room != null and is_instance_valid(room):
		room.remove_from_group(Room.ROOMS_GROUP)
		room_holder.remove_child(room)
		room.queue_free()
	room = null
	# Loose balloons left from the previous room.
	for c in players_node.get_children():
		if c is HeartBalloon:
			c.queue_free()


func _set_players_locked(locked: bool) -> void:
	for p: BasePlayer in [bubu, dudu]:
		p.set_controls_enabled(not locked)
		if locked:
			p.velocity.x = 0.0


func _on_room_completed() -> void:
	if _transitioning or _ending or not auto_advance:
		return
	Sfx.play("exit_ready", 0.0)
	await _advance()


func _advance() -> void:
	var ch := chapter_index
	var next := room_index + 1
	if next < GameState.room_count(ch):
		await enter_room(ch, next)
		return
	# End of chapter.
	_transitioning = true
	_set_players_locked(true)
	var chapter := GameState.get_chapter(ch)
	await _play_once("chapter_outro_%s" % chapter.get("id", ch), StringName(String(chapter.get("outro", ""))))
	if not fast_transitions:
		Stickers.pop(world, "both_cheers", camera.get_screen_center_position() + Vector2(0, 90), 200.0, 2.4)
		await get_tree().create_timer(2.2).timeout
	GameState.complete_chapter(ch)
	if ch + 1 < GameState.chapter_count():
		GameState.set_position(ch + 1, 0)
		await enter_room(ch + 1, 0)
	else:
		_ending = true
		if not fast_transitions:
			await hud.fade_to(1.0, 1.2)
		GameState.in_game = false
		get_tree().change_scene_to_file(CREDITS_SCENE)


# --- Pause ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if UiTheme.is_pause(event) and not get_tree().paused and not _transitioning and room != null:
		get_viewport().set_input_as_handled()
		_pause()


func _notification(what: int) -> void:
	# Closing the window (or the browser tab) keeps the place in the room.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_checkpoint()
	# Losing focus (alt-tab, browser tab hidden) pauses so nobody falls meanwhile.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree() and not get_tree().paused \
			and not _transitioning and room != null and DisplayServer.get_name() != "headless":
		_pause()


func _pause() -> void:
	save_checkpoint()
	get_tree().paused = true
	pause_menu.hint_text = room.hint_text if room != null else ""
	pause_menu.room_time = room_time
	pause_menu.open()
	Sfx.play("ui_accept", 0.0, -4.0)


func _resume() -> void:
	pause_menu.close()
	get_tree().paused = false


func _restart() -> void:
	_resume()
	GameState.room_snapshot = {}
	await enter_room(chapter_index, room_index)


func _skip() -> void:
	_resume()
	if room != null and not room.is_completed():
		room.complete()


func _quit_to_menu() -> void:
	save_checkpoint()
	pause_menu.close()
	get_tree().paused = false
	GameState.in_game = false
	get_tree().change_scene_to_file(MENU_SCENE)
