extends "res://tests/TestBase.gd"
## Bootstrap smoke test: scripts parse, input map, test gym, camera, piggyback.

const VERBS: Array[String] = ["left", "right", "up", "down", "jump", "interact", "assist", "pause"]


func run() -> void:
	await get_tree().process_frame

	var scripts: Array[String] = []
	_collect("res://scenes", scripts)
	var bad := 0
	for path in scripts:
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			bad += 1
			print("[FAIL] script does not compile: " + path)
	check(scripts.size() > 30 and bad == 0, "all %d scripts compile" % scripts.size())

	var missing := 0
	for p in [1, 2]:
		for verb in VERBS:
			if not InputMap.has_action(StringName("p%d_%s" % [p, verb])):
				missing += 1
	check(missing == 0, "input actions registered (p1_*, p2_*)")

	var packed := load("res://scenes/rooms/test_gym.tscn") as PackedScene
	check(packed != null, "test_gym loads")
	if packed == null:
		return
	var gym := packed.instantiate()
	get_tree().root.add_child(gym)
	check(gym.is_inside_tree(), "test_gym instantiates")

	var bubu := gym.get_node_or_null("Players/Bubu") as BasePlayer
	var dudu := gym.get_node_or_null("Players/Dudu") as BasePlayer
	var cam := gym.get_node_or_null("CoopCamera2D") as CoopCamera2D
	check(bubu != null and dudu != null and cam != null, "players and camera present")
	if bubu == null or dudu == null or cam == null:
		return

	check(bubu.player_index == 1 and dudu.player_index == 2, "player indices 1/2")
	check((bubu.collision_mask & 2) == 0 and (dudu.collision_mask & 2) == 0, "players do not collide with each other")
	check((bubu.collision_mask & 1) != 0 and (dudu.collision_mask & 1) != 0, "players collide with world")

	for i in 45:
		await get_tree().physics_frame
	check(bubu.is_on_floor() and dudu.is_on_floor(), "both players land on the floor")
	check(cam.is_current(), "coop camera is current")

	var mid := (bubu.global_position + dudu.global_position) * 0.5
	var view_half := get_tree().root.get_visible_rect().size * 0.5 / cam.zoom.x
	var view := Rect2(cam.global_position - view_half, view_half * 2.0)
	check(view.has_point(bubu.global_position) and view.has_point(dudu.global_position), "both players in camera view")
	check(cam.level_bounds.grow(1.0).encloses(view), "camera view clamped to level bounds")
	check(absf(cam.global_position.x - mid.x) < 400.0, "camera near players' midpoint")

	bubu.teleport_to(dudu.global_position + Vector2(-40, 0))
	check(bubu.can_hop_on(dudu), "piggyback available in range")
	bubu.hop_on(dudu)
	for i in 5:
		await get_tree().physics_frame
	check(bubu.is_riding() and dudu.rider == bubu, "piggyback state set")
	check(bubu.global_position.y < dudu.global_position.y - 20.0, "rider sits on carrier's back")
	bubu.dismount(true)
	for i in 5:
		await get_tree().physics_frame
	check(not bubu.is_riding() and dudu.rider == null, "dismount clears piggyback")

	gym.queue_free()
	await get_tree().process_frame


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)
