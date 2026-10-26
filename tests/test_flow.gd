extends "res://tests/TestBase.gd"
## Whole-game flow: main menu -> new game -> auto-save on room entry -> quit to menu ->
## continue -> pause / restart -> chapter change -> last room -> credits -> menu.
## Uses its own save file so the player's progress is never touched.

const MENU := "res://scenes/ui/MainMenu.tscn"
const SAVE := "user://test_flow_save.json"

var _old_save := ""


func run() -> void:
	_old_save = GameState.save_path
	GameState.save_path = SAVE
	GameState.delete_progress()

	get_tree().change_scene_to_file(MENU)
	var menu := await _wait_scene("MainMenu")
	check(menu != null, "main menu loads")
	if menu == null:
		return _cleanup()
	check(not GameState.has_save(), "fresh profile has no save")

	menu.call(&"_new_game")
	var game := await _wait_game()
	check(game != null, "new game starts the game scene")
	if game == null:
		return _cleanup()
	check(game.room != null and String(game.room.room_id) == "c1_r01", "first room loaded")
	check(GameState.has_save() and _saved_room() == Vector2i(0, 0), "auto-save on room entry (0/0)")
	check(game.bubu.controls_enabled and game.dudu.controls_enabled, "players unlocked after intro")

	# Finish two rooms: each entry is saved.
	for i in 2:
		game.room.complete()
		await _settle(game)
	check(game.room_index == 2 and _saved_room() == Vector2i(0, 2), "room completion advances and saves")

	# Pause, restart.
	game.call(&"_pause")
	await frames(2)
	check(get_tree().paused and game.pause_menu.visible, "pause menu opens and pauses the tree")
	game.call(&"_restart")
	await _settle(game)
	check(not get_tree().paused and game.room_index == 2, "restart reloads the same room")
	check(GameState.room_snapshot.is_empty(), "restart forgets the mid-room save")

	# Walk a bit into the room, quit to menu, continue: same spot, not the room start.
	var spawn_x := game.bubu.global_position.x
	Input.action_press(&"p1_right")
	await _play(0.8)
	Input.action_release(&"p1_right")
	await _play(0.8)
	var walked := game.bubu.global_position
	game.call(&"_quit_to_menu")
	menu = await _wait_scene("MainMenu")
	check(menu != null and not get_tree().paused, "quit returns to the main menu")
	if menu == null:
		return _cleanup()
	menu.call(&"_continue")
	game = await _wait_game()
	check(game != null and game.chapter_index == 0 and game.room_index == 2, "continue resumes the saved room")
	if game != null:
		await _settle(game)
		check(walked.x > spawn_x + 40.0 and game.bubu.global_position.distance_to(walked) < 24.0,
			"continue resumes mid-room where the players were")
	if game == null:
		return _cleanup()

	# Last room of chapter 1 -> chapter 2.
	game.fast_transitions = true
	var last1 := GameState.room_count(0) - 1
	game.enter_room(0, last1)
	await _settle(game)
	game.room.complete()
	await _settle(game)
	check(game.chapter_index == 1 and game.room_index == 0, "chapter end leads to the next chapter")
	check(GameState.unlocked_chapter >= 1, "next chapter unlocked")

	# Last room of the game -> credits.
	var last_ch := GameState.chapter_count() - 1
	game.enter_room(last_ch, GameState.room_count(last_ch) - 1)
	await _settle(game)
	game.room.complete()
	var credits := await _wait_scene("Credits", game)
	check(credits != null, "last room leads to the credits")
	check(GameState.game_completed, "game marked completed")
	if credits != null:
		credits.call(&"_finish")
		menu = await _wait_scene("MainMenu")
		check(menu != null, "credits return to the main menu")
	_cleanup()


func _cleanup() -> void:
	get_tree().paused = false
	GameState.delete_progress()
	GameState.save_path = _old_save
	GameState.load_progress()
	var cur := get_tree().current_scene
	if cur != null:
		cur.queue_free()
	await frames(2)


func _saved_room() -> Vector2i:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE)) if FileAccess.file_exists(SAVE) else null
	if not d is Dictionary:
		return Vector2i(-1, -1)
	return Vector2i(int(d.get("chapter_index", -1)), int(d.get("room_index", -1)))


func _wait_scene(script_name: String, game: Node = null) -> Node:
	for i in 1800:
		await get_tree().process_frame
		var cur := get_tree().current_scene
		if cur != null and cur.get_script() != null and (cur.get_script() as Script).resource_path.get_file().get_basename() == script_name:
			return cur
		if game != null and is_instance_valid(game):
			var dlg: Variant = game.get(&"dialogue")
			if dlg != null and dlg.is_busy():
				dlg.advance()
	return null


func _wait_game() -> Game:
	var node := await _wait_scene("Game")
	var game := node as Game
	if game != null:
		await _settle(game)
	return game


## Waits for transitions to end, skipping title cards and dialogues.
func _settle(game: Game) -> void:
	for i in 2400:
		await get_tree().process_frame
		if not is_instance_valid(game):
			return
		if game.dialogue.is_busy():
			if i % 6 == 0:
				game.dialogue.advance()
		elif not game.is_transitioning() and game.room != null:
			return


## Lets the game run for `seconds` of physics.
func _play(seconds: float) -> void:
	await frames(int(seconds * 60.0))
