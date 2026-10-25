extends "res://tests/TestBase.gd"
## Mashes random pad input in every room (seeded per room, so failures replay) and checks
## that nothing breaks: no engine errors, nobody leaves the room without a balloon,
## nobody ends up stuck inside solid geometry, no NaN positions.
## Arguments after "--": "chaos" plus optional room ids, "-s=<seconds>" per room.

const GAME_SCENE := "res://scenes/core/Game.tscn"
const VERBS: Array[String] = ["left", "right", "up", "down", "jump", "interact", "assist"]
## Continuous seconds inside solid geometry that count as "stuck".
const STUCK_LIMIT := 1.0

var seconds := 20.0


func run() -> void:
	quiet = true
	var filters: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("-s="):
			seconds = float(a.substr(3))
		elif not a.begins_with("-") and not ResourceLoader.exists("res://tests/test_%s.gd" % a):
			filters.append(a)
	GameState.save_path = "user://test_chaos_save.json"
	var rooms := 0
	for ch in GameState.chapter_count():
		for i in GameState.room_count(ch):
			var path := GameState.get_room_path(ch, i)
			var rid := path.get_base_dir().get_file().replace("ch", "c") + "_r" + path.get_file().get_basename().trim_prefix("Room_")
			if filters.is_empty() or filters.has(rid):
				rooms += 1
				await _mash(ch, i, path, rid)
	quiet = false
	check(rooms > 0, "chaos: %d rooms mashed for %.0fs each" % [rooms, seconds])
	GameState.delete_progress()


func _mash(ch: int, idx: int, path: String, rid: String) -> void:
	GameState.delete_progress()
	var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
	game.autostart = false
	game.fast_transitions = true
	game.auto_advance = false
	get_tree().root.add_child(game)
	await get_tree().process_frame
	game.enter_room(ch, idx, path)
	for i in 600:
		await get_tree().physics_frame
		if game.dialogue.is_busy():
			game.dialogue.advance()
		if game.room != null and not game.is_transitioning():
			break
	var room := game.room
	if not check(room != null, "%s loads" % rid):
		game.queue_free()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(rid)
	var held: Array[Dictionary] = [{}, {}]
	var change := [0.0, 0.0]
	var inside := [0.0, 0.0]
	var problems: Array[String] = []
	var dlg_timer := 0.0
	var total := int(seconds * 60.0)
	for f in total:
		var dt := 1.0 / 60.0
		# Dialogue (story, signs, lines) is read and skipped like a player would.
		if game.dialogue.is_busy():
			dlg_timer += dt
			if dlg_timer > 0.3:
				dlg_timer = 0.0
				game.dialogue.advance()
		for p in 2:
			change[p] -= dt
			if change[p] <= 0.0:
				change[p] = rng.randf_range(0.1, 0.7)
				held[p] = _random_verbs(rng)
			for v in VERBS:
				var a := StringName("p%d_%s" % [p + 1, v])
				if held[p].has(v) and not Input.is_action_pressed(a):
					Input.action_press(a)
				elif not held[p].has(v) and Input.is_action_pressed(a):
					Input.action_release(a)
		await get_tree().physics_frame
		if game.room != room:
			break  # mashed through the exit: fine
		for p in 2:
			var pl: BasePlayer = game.bubu if p == 0 else game.dudu
			var pos := pl.global_position
			if is_nan(pos.x) or is_nan(pos.y):
				problems.append("p%d NaN position" % (p + 1))
			elif not pl.is_in_balloon():
				var b := room.bounds.grow(64.0)
				if pos.x < b.position.x or pos.x > b.end.x or pos.y > room.get_kill_y() + 64.0:
					problems.append("p%d out of bounds at %s" % [p + 1, pos.round()])
			var hit := _overlaps_world(pl) if pl.state == BasePlayer.State.NORMAL else ""
			if hit != "":
				inside[p] += dt
				if inside[p] > STUCK_LIMIT:
					problems.append("p%d stuck in %s at %s" % [p + 1, hit, pos.round()])
			else:
				inside[p] = 0.0
		if not problems.is_empty():
			break
	_release_all()
	check(problems.is_empty(), "%s survives %.0fs of random input%s" % [rid, seconds, "" if problems.is_empty() else " - " + problems[0]])
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _random_verbs(rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	var r := rng.randf()
	if r < 0.4:
		out["right"] = true
	elif r < 0.7:
		out["left"] = true
	for v in ["jump", "interact", "assist", "up", "down"]:
		var chance: float = {"jump": 0.35, "interact": 0.12, "assist": 0.1, "up": 0.15, "down": 0.1}[v]
		if rng.randf() < chance:
			out[v] = true
	return out


func _release_all() -> void:
	for p in 2:
		for v in VERBS:
			var a := StringName("p%d_%s" % [p + 1, v])
			if Input.is_action_pressed(a):
				Input.action_release(a)


## Name of the solid world body (layer 1) the player's body overlaps, or "". Checked solid world geometry (layer 1) at rest position,
## shrunk a little so standing flush against a wall doesn't count.
func _overlaps_world(pl: BasePlayer) -> String:
	var col := pl.get_node("CollisionShape2D") as CollisionShape2D
	if col == null or col.disabled or not (col.shape is RectangleShape2D):
		return ""
	var shape := RectangleShape2D.new()
	shape.size = (col.shape as RectangleShape2D).size - Vector2(8, 8)
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = col.global_transform
	params.collision_mask = 1
	params.exclude = [pl.get_rid()]
	var hits := pl.get_world_2d().direct_space_state.intersect_shape(params, 4)
	for h: Dictionary in hits:
		var c: Object = h.get("collider")
		# One-way platforms can be passed through from below: not solid.
		if c is CollisionObject2D:
			var owner_id: int = h.get("shape", 0)
			var co := c as CollisionObject2D
			var sh_owner := co.shape_find_owner(owner_id)
			if co.is_shape_owner_one_way_collision_enabled(sh_owner):
				continue
		return (c as Node).get_script().resource_path.get_file().get_basename() if c is Node and (c as Node).get_script() != null else str(c)
	return ""
