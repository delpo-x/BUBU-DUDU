extends "res://tests/TestBase.gd"
## Component behaviour that the room bot does not cover directly: save robustness,
## hazards and the heart balloon, heavy items, call rules, dialogue locking.

const GAME_SCENE := "res://scenes/core/Game.tscn"
const SAVE := "user://test_components_save.json"

var _old_save := ""


func run() -> void:
	_old_save = GameState.save_path
	GameState.save_path = SAVE
	GameState.delete_progress()
	_test_save()

	var game := await _game("res://scenes/rooms/dev/Room_steps.tscn")
	if game != null:
		await _test_hazard(game)
		await _test_dialogue(game)
		await _test_barks(game)
		game.queue_free()
		await frames(2)
	game = await _game("res://scenes/rooms/dev/Room_hcrate.tscn")
	if game != null:
		await _test_heavy(game)
		await _test_call(game, false)
		game.queue_free()
		await frames(2)
	await _test_room_state("res://scenes/rooms/ch1/Room_03.tscn")
	await _test_room_state("res://scenes/rooms/dev/Room_fragile.tscn")
	game = await _game("res://scenes/rooms/dev/Room_call.tscn")
	if game != null:
		await _test_call(game, true)
		game.queue_free()
		await frames(2)

	GameState.delete_progress()
	GameState.save_path = _old_save
	GameState.load_progress()


func _test_save() -> void:
	GameState.collect_memory("m1_a")
	GameState.set_flag("test_flag", 3)
	GameState.set_position(1, 4)
	var snap := GameState.capture()
	GameState.memories = {}
	GameState.flags = {}
	check(GameState.load_progress(), "save loads back")
	check(GameState.has_memory("m1_a") and int(GameState.get_flag("test_flag")) == 3 \
		and GameState.chapter_index == 1 and GameState.room_index == 4, "save round-trip keeps progress")
	# A corrupted main file falls back to the backup.
	GameState.save_progress()
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	GameState.memories = {}
	var logger: Object = get_tree().root.get_meta(&"error_logger", null)
	if logger != null:
		logger.call(&"expect_errors", 1)  # the JSON parser reports the corrupted file
	var ok := GameState.load_progress()
	check(ok and GameState.has_memory("m1_a"), "corrupted save recovers from backup")
	check(snap.has("version"), "save carries a format version")
	GameState.delete_progress()
	check(not GameState.has_save(), "delete removes every save file")


## Mid-room save round trip: change what a room remembers (crates moved, levers flipped,
## floors broken), capture it, load the room fresh and restore: same state again.
func _test_room_state(path: String) -> void:
	var game := await _game(path)
	if game == null:
		return
	var changed := 0
	for n in get_tree().get_nodes_in_group(Room.STATE_GROUP):
		if not game.room.is_ancestor_of(n):
			continue
		if n is CarryableItem:
			n.call(&"restore", {"x": (n as Node2D).global_position.x + 48.0, "y": (n as Node2D).global_position.y - 4.0})
			changed += 1
		elif n is WallButton and (n as WallButton).mode == WallButton.Mode.LEVER:
			(n as WallButton).interact(game.bubu)
			changed += 1
		elif n is FragileFloor:
			n.call(&"restore", {"broken": true})
			changed += 1
	await frames(40)
	var saved := game.room.capture_state()
	game.queue_free()
	await frames(2)
	game = await _game(path)
	if game == null:
		return
	game.room.restore_state(saved)
	await frames(2)
	var again := game.room.capture_state()
	var same := true
	for k: String in (saved["nodes"] as Dictionary).keys():
		var a: Variant = saved["nodes"][k]
		var b: Variant = (again["nodes"] as Dictionary).get(k)
		if a is Dictionary and a.has("x"):
			same = same and b is Dictionary and Vector2(a["x"], a["y"]).distance_to(Vector2(b["x"], b["y"])) < 6.0
		else:
			same = same and JSON.stringify(a) == JSON.stringify(b)
	check(changed > 0 and same, "mid-room save restores the puzzle (%s)" % path.get_file())
	game.queue_free()
	await frames(2)


func _game(path: String) -> Game:
	if not ResourceLoader.exists(path):
		check(false, "dev room exists: " + path.get_file())
		return null
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	game.autostart = false
	game.fast_transitions = true
	game.auto_advance = false
	get_tree().root.add_child(game)
	game.enter_room(0, 0, path)
	# Intro dialogues play on entry: skip through them.
	for i in 3000:
		await get_tree().process_frame
		if game.dialogue.is_busy():
			if i % 6 == 0:
				game.dialogue.advance()
		elif not game.is_transitioning():
			break
	await frames(30)
	return game


func _test_hazard(game: Game) -> void:
	var hazard: Node2D = null
	for n in game.room.get_node("Things").get_children():
		if n is Hazard:
			hazard = n
	check(hazard != null, "room has a hazard")
	if hazard == null:
		return
	var lost := [false]
	game.bubu.balance_lost.connect(func(_p: BasePlayer) -> void: lost[0] = true, CONNECT_ONE_SHOT)
	game.bubu.teleport_to(hazard.global_position + Vector2(0, -24))
	var back := false
	for i in 600:
		await get_tree().physics_frame
		if lost[0] and not game.bubu.is_in_balloon() and game.bubu.is_on_floor():
			back = true
			break
	check(lost[0], "hazard knocks the player into a heart balloon")
	check(back and game.bubu.global_position.distance_to(game.dudu.global_position) < 120.0,
		"balloon brings the player back next to the partner")
	check(game.room != null and not game.room.is_completed(), "no game over, room still loaded")


func _test_dialogue(game: Game) -> void:
	game.dialogue.play_dialogue(&"c1_r02_talk")
	await frames(3)
	check(game.dialogue.is_busy() and not game.bubu.controls_enabled and not game.dudu.controls_enabled,
		"dialogue locks both players")
	for i in 600:
		await get_tree().process_frame
		if not game.dialogue.is_busy():
			break
		if i % 6 == 0:
			game.dialogue.advance()
	await frames(3)
	check(not game.dialogue.is_busy() and game.bubu.controls_enabled and game.dudu.controls_enabled,
		"dialogue ends and unlocks both players")


func _test_heavy(game: Game) -> void:
	var crate: CarryableItem = null
	for n in game.room.get_node("Things").get_children():
		if n is CarryableItem and n.weight >= 2:
			crate = n
	check(crate != null, "room has a heavy crate")
	if crate == null:
		return
	crate.interact(game.bubu)
	check(game.bubu.carried_item == null, "Bubu cannot lift a heavy crate")
	crate.interact(game.dudu)
	await frames(2)
	check(game.dudu.carried_item == crate, "Dudu lifts the heavy crate")
	check(game.dudu.get_weight() >= 4, "carried weight adds to the carrier")
	crate.force_drop(game.dudu)
	game.dudu.release_item()
	await frames(10)


func _test_call(game: Game, allowed: bool) -> void:
	var start := game.room.get_spawn(1)
	game.bubu.teleport_to(start + Vector2(400, 0))
	game.dudu.teleport_to(start)
	await frames(30)
	game.bubu.call(&"_try_call")
	var arrived := false
	for i in 300:
		await get_tree().physics_frame
		if not game.dudu.is_in_balloon() and game.dudu.global_position.distance_to(game.bubu.global_position) < 120.0:
			arrived = true
			break
	if allowed:
		check(arrived, "call brings the partner over where allowed")
	else:
		check(not arrived, "call is refused in puzzle rooms")


func _test_barks(game: Game) -> void:
	var d := game.barks
	check(d != null and d.has_pool("progress") and d.has_pool("ambient_c1"), "contextual lines loaded")
	if d == null:
		return
	# After the previous dialogue's quiet time, a request plays at the next calm moment.
	var old_cd := d.cooldown
	d.cooldown = 0.0
	await _play_secs(d.after_dialogue + 0.5)
	d.request("progress", 1.0)
	check(d.is_pending() or game.dialogue.is_busy(), "request queued")
	var played := await _wait_dialogue(game, 3.0)
	check(played, "contextual line plays in the dialogue box when calm")
	await _finish_dialogue(game)
	# Cooldown blocks a second line right away.
	d.cooldown = 60.0
	d.request("progress", 1.0)
	played = await _wait_dialogue(game, 2.0)
	check(not played, "cooldown keeps contextual lines rare")
	d.cooldown = old_cd
	# Not calm while someone is in the air.
	game.bubu.teleport_to(game.bubu.global_position + Vector2(0, -200))
	await frames(2)
	check(not d.is_calm(), "no lines while a player is airborne")
	await _play_secs(1.5)
	check(d.is_calm(), "calm again once both stand still")
	# Not during a piggyback (locking the rider mid-dismount would eat the jump).
	game.dudu.teleport_to(game.bubu.global_position + Vector2(30, 0))
	await _play_secs(0.5)
	if game.dudu.can_hop_on(game.bubu):
		game.dudu.hop_on(game.bubu)
		await frames(2)
		check(not d.is_calm(), "no lines during a piggyback")
		game.dudu.dismount(false)
	else:
		check(false, "piggyback possible for the calm check")
	await _play_secs(1.5)
	# No repeats until the pool is exhausted.
	var seen := {}
	var n: int = (GameState.barks["progress"] as Array).size()
	for i in n:
		seen[JSON.stringify(d.pick("progress"))] = true
	check(seen.size() == n, "a pool plays every entry before repeating")
	# Option off: requests are ignored.
	GameState.barks_enabled = false
	d.request("progress", 1.0)
	check(not d.is_pending(), "option off silences contextual lines")
	GameState.barks_enabled = true


func _play_secs(s: float) -> void:
	for i in int(s * 60.0):
		await get_tree().physics_frame


func _wait_dialogue(game: Game, s: float) -> bool:
	for i in int(s * 60.0):
		await get_tree().physics_frame
		if game.dialogue.is_busy():
			return true
	return false


func _finish_dialogue(game: Game) -> void:
	for i in 900:
		await get_tree().process_frame
		if not game.dialogue.is_busy():
			break
		if i % 6 == 0:
			game.dialogue.advance()
	await frames(3)
