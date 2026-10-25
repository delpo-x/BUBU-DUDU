extends "res://tests/TestBase.gd"
## Plays rooms with the bot. Arguments after "--": "rooms" plus optional filters:
##   all (default: every room in data/chapters.json), dev (tests/solutions/dev_*),
##   or room ids (c1_r03 ...). Example:
##   godot --headless --fixed-fps 60 --path . --script res://tests/run.gd -- rooms dev

const BotScript := preload("res://tests/Bot.gd")
const GAME_SCENE := "res://scenes/core/Game.tscn"
const SOLUTIONS := "res://tests/solutions"

var verbose := false


func run() -> void:
	var filters: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("-") and not ResourceLoader.exists("res://tests/test_%s.gd" % a):
			filters.append(a)
		if a == "-v":
			verbose = true
	GameState.save_path = "user://test_rooms_save.json"
	var targets := _targets(filters)
	check(not targets.is_empty(), "rooms to test: %d" % targets.size())
	for t: Dictionary in targets:
		await _play(t)
	GameState.delete_progress()


func _targets(filters: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in filters:
		if f.begins_with("dev_") and FileAccess.file_exists(SOLUTIONS.path_join(f + ".json")):
			out.append({"ch": 0, "idx": 0, "sol": SOLUTIONS.path_join(f + ".json")})
	if not out.is_empty():
		return out
	var dev := filters.has("dev")
	if dev:
		for f in DirAccess.get_files_at(SOLUTIONS):
			if f.begins_with("dev_") and f.ends_with(".json"):
				out.append({"ch": 0, "idx": 0, "sol": SOLUTIONS.path_join(f)})
		return out
	for ch in GameState.chapter_count():
		for i in GameState.room_count(ch):
			var path := GameState.get_room_path(ch, i)
			var packed := load(path) as PackedScene
			var rid := ""
			if packed != null:
				var st := packed.get_state()
				for k in st.get_node_property_count(0):
					if st.get_node_property_name(0, k) == &"room_id":
						rid = String(st.get_node_property_value(0, k))
			if filters.is_empty() or filters.has("all") or filters.has(rid):
				out.append({"ch": ch, "idx": i, "sol": SOLUTIONS.path_join(rid + ".json"), "path": path})
	return out


func _play(t: Dictionary) -> void:
	var sol: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(t["sol"]))) if FileAccess.file_exists(String(t["sol"])) else null
	if not sol is Dictionary:
		check(false, "solution readable: " + String(t["sol"]))
		return
	var data: Dictionary = sol
	var rid := String(data.get("room", "?"))
	GameState.delete_progress()
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	game.set(&"autostart", false)
	game.set(&"fast_transitions", true)
	game.set(&"auto_advance", false)
	get_tree().root.add_child(game)
	await get_tree().process_frame
	var bot: Node = BotScript.new()
	bot.set(&"log_steps", verbose)
	add_child(bot)
	# Dialogue may play on entry: the bot advances it, so start it right away.
	bot.call(&"setup", game.get(&"bubu"), game.get(&"dudu"), null)
	bot.set(&"running", false)
	var path := String(data.get("path", t.get("path", "")))
	var entering: Variant = game.call(&"enter_room", int(t["ch"]), int(t["idx"]), path)
	var room: Room = null
	for i in 600:
		await get_tree().physics_frame
		room = game.get(&"room") as Room
		var svc := get_tree().get_first_node_in_group(&"dialogue_service")
		if svc != null and bool(svc.call(&"is_busy")):
			svc.call(&"advance")
		if room != null and not bool(game.call(&"is_transitioning")):
			break
	if room == null:
		check(false, "%s loads" % rid)
		game.queue_free()
		bot.queue_free()
		return
	bot.set(&"room", room)
	var result := [false, "no result"]
	bot.connect(&"finished", func(ok: bool, msg: String) -> void:
		result[0] = ok
		result[1] = msg)
	var start_ms := Time.get_ticks_msec()
	bot.call(&"run", data.get("steps", []))
	var frames_run := 0
	while bool(bot.get(&"running")) and frames_run < 60 * 900:
		await get_tree().physics_frame
		frames_run += 1
	var sim_s := frames_run / 60.0
	var ok: bool = result[0] and room.is_completed()
	var balloons := int(bot.get(&"balloon_events"))
	check(ok, "%s solved by bot (%.0fs sim)%s" % [rid, sim_s, "" if ok else " - " + String(result[1])])
	if ok:
		check(balloons == int(data.get("expected_balloons", 0)), "%s clean run (%d balloon falls)" % [rid, balloons])
		for mid: String in data.get("memories", []):
			check(GameState.has_memory(mid), "%s memory collected" % rid)
	if verbose:
		print("  real time %d ms" % (Time.get_ticks_msec() - start_ms))
	bot.queue_free()
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
