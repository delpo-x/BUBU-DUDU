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
	_test_bindings()
	# One pad with a non-zero id (after a reconnect) must not drive both players.
	check(PadAssigner.device_for_slot(0, [1]) == 1 and PadAssigner.device_for_slot(1, [1]) != 1
		and PadAssigner.device_for_slot(1, [0, 3]) == 3 and PadAssigner.device_for_slot(1, []) == 1,
		"a player without a pad never shares the other player's pad")

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


## Remapping: a taken key swaps, pad buttons swap within one player, saved and restored.
func _test_bindings() -> void:
	var old_path := Bindings.path
	Bindings.path = "user://test_controls.cfg"
	Bindings.reset_defaults()
	var p1_jump_key := Bindings.key_of(&"p1_jump").physical_keycode
	var p1_left_key := Bindings.key_of(&"p1_left").physical_keycode
	Bindings.set_key(&"p1_jump", p1_left_key)
	check(Bindings.key_of(&"p1_jump").physical_keycode == p1_left_key
		and Bindings.key_of(&"p1_left").physical_keycode == p1_jump_key, "a taken key swaps with the action that had it")
	Bindings.set_pad(&"p2_jump", JOY_BUTTON_Y)
	check(Bindings.pad_of(&"p2_jump").button_index == JOY_BUTTON_Y and Bindings.pad_of(&"p2_assist").button_index == JOY_BUTTON_A
		and Bindings.pad_of(&"p1_jump").button_index == JOY_BUTTON_A, "pad buttons swap within the same player only")
	Bindings.reset_defaults()
	Bindings.set_key(&"p2_interact", KEY_K)
	# Forget it in memory only (reset would save), then read the file back.
	Bindings.call(&"_replace_key", &"p2_interact", KEY_PERIOD)
	Bindings.load_bindings()
	check(Bindings.key_of(&"p2_interact").physical_keycode == KEY_K, "remapped keys are saved and loaded")
	Bindings.reset_defaults()
	check(Bindings.key_of(&"p1_jump").physical_keycode == p1_jump_key and Bindings.key_label(&"p1_jump") == "Spazio", "reset restores the default keys")
	# A damaged controls file (bad values, a key used twice) must never leave an action unbound.
	var cfg := ConfigFile.new()
	cfg.set_value("keys", "p1_jump", "foo")
	cfg.set_value("keys", "p1_left", -5)
	cfg.set_value("keys", "p2_jump", int(p1_left_key))
	cfg.set_value("pad", "p1_jump", "x")
	cfg.save(Bindings.path)
	Bindings.load_bindings()
	var used := {}
	var unbound := 0
	for a in Bindings.all_actions():
		var k := Bindings.key_of(a)
		if k == null or used.has(k.physical_keycode):
			unbound += 1
		else:
			used[k.physical_keycode] = true
		if Bindings.can_rebind_pad(a) and Bindings.pad_of(a) == null:
			unbound += 1
	check(unbound == 0, "a damaged controls file leaves every action with its own key and button")
	Bindings.reset_defaults()
	DirAccess.remove_absolute(Bindings.path)
	Bindings.path = old_path
