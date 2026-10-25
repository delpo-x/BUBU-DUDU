extends "res://tests/TestBase.gd"
## Visual check (not part of the default suite; needs a real window, not --headless):
##   godot --path . --script res://tests/run.gd -- shots c1_r01 c3_r05
## Saves user://shots/<room>.png after the room settles.

const GAME_SCENE := "res://scenes/core/Game.tscn"


func run() -> void:
	var wanted: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if a != "shots" and not a.begins_with("-"):
			wanted.append(a)
	DirAccess.make_dir_recursive_absolute("user://shots")
	var old_save := GameState.save_path
	GameState.save_path = "user://test_shots_save.json"
	if wanted.has("rig"):
		await _rig_shots()
	if wanted.has("menu"):
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
		await frames(90)
		_save("menu")
		get_tree().current_scene.queue_free()
		await frames(3)
	if wanted.has("screens"):
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
		await _secs(0.5)
		var m := get_tree().current_scene
		m.call(&"_open_album")
		await _secs(0.4)
		_save("album")
		m.call(&"_show_main")
		m.call(&"_open_controls")
		await _secs(0.4)
		_save("controls")
		m.call(&"_show_main")
		m.call(&"_open_options")
		await _secs(0.4)
		_save("options")
		get_tree().change_scene_to_file("res://scenes/ui/Credits.tscn")
		await _secs(3.0)
		_save("credits")
		get_tree().current_scene.queue_free()
		await frames(3)
	if wanted.has("title"):
		var tg := (load(GAME_SCENE) as PackedScene).instantiate() as Game
		tg.autostart = false
		get_tree().root.add_child(tg)
		tg.enter_room(2, 0)
		await _secs(1.8)
		_save("title")
		# The window is not vsynced here: wait on the clock, not on frame counts.
		var until := Time.get_ticks_msec() + 20000
		var next_adv := 0
		while Time.get_ticks_msec() < until:
			await get_tree().process_frame
			if tg.dialogue.is_busy():
				if Time.get_ticks_msec() > next_adv:
					tg.dialogue.advance()
					next_adv = Time.get_ticks_msec() + 120
			elif not tg.is_transitioning():
				break
		GameState.collect_memory("m1_a")
		tg.hud.show_memory("m1_a")
		await _secs(0.8)
		_save("memory_popup")
		tg.queue_free()
		await frames(3)
	if wanted.has("ui"):
		# First room with its intro dialogue on screen, then the pause menu.
		var g := (load(GAME_SCENE) as PackedScene).instantiate() as Game
		g.autostart = false
		g.fast_transitions = true
		g.auto_advance = false
		get_tree().root.add_child(g)
		g.enter_room(0, 0)
		for f in 300:
			await get_tree().process_frame
			if g.dialogue.is_busy() and f > 120:
				break
		_save("dialogue")
		for f in 600:
			await get_tree().process_frame
			if not g.dialogue.is_busy() and not g.is_transitioning():
				break
			if f % 4 == 0:
				g.dialogue.advance()
		g.call(&"_pause")
		await frames(20)
		_save("pause")
		g.call(&"_resume")
		# Portrait layouts with a placeholder line (not story text): each speaker, then a
		# shared line with the large-text option on.
		for who in ["bubu", "dudu", "both"]:
			GameState.large_text = who == "both"
			g.dialogue.play_lines([{"s": who, "t": "Riga di prova per il layout del riquadro."}])
			await frames(70)
			_save("dialogue_" + who)
			g.dialogue.advance()
			await frames(2)
			g.dialogue.advance()
			await frames(4)
		GameState.large_text = false
		g.queue_free()
		await frames(3)
	for ch in GameState.chapter_count():
		for i in GameState.room_count(ch):
			var rid := "c%d_r%02d" % [ch + 1, i + 1]
			if not wanted.has(rid) and not wanted.has("c%d" % (ch + 1)):
				continue
			var game := (load(GAME_SCENE) as PackedScene).instantiate() as Game
			game.autostart = false
			game.fast_transitions = true
			game.auto_advance = false
			get_tree().root.add_child(game)
			game.enter_room(ch, i)
			for f in 400:
				await get_tree().process_frame
				if game.dialogue.is_busy():
					if f % 4 == 0:
						game.dialogue.advance()
				elif not game.is_transitioning() and f > 60:
					break
			await frames(20)
			var img := get_viewport().get_texture().get_image()
			check(img != null and img.save_png("user://shots/%s.png" % rid) == OK, "shot saved: " + rid)
			game.queue_free()
			await frames(3)
	GameState.delete_progress()
	GameState.save_path = old_save
	GameState.load_progress()


## Both characters on a plain floor, zoomed in, in each animated pose.
func _rig_shots() -> void:
	var world := Node2D.new()
	get_tree().root.add_child(world)
	var bg := ColorRect.new()
	bg.color = Color(0.93, 0.95, 1.0)
	bg.position = Vector2(-2000, -2000)
	bg.size = Vector2(4000, 4000)
	world.add_child(bg)
	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(0, 40)
	world.add_child(floor_body)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4000, 20)
	shape.shape = rect
	floor_body.add_child(shape)
	var floor_vis := ColorRect.new()
	floor_vis.color = Color(0.55, 0.75, 0.5)
	floor_vis.position = Vector2(-2000, 30)
	floor_vis.size = Vector2(4000, 300)
	world.add_child(floor_vis)
	var cam := Camera2D.new()
	cam.zoom = Vector2(3.5, 3.5)
	cam.position = Vector2(0, -10)
	world.add_child(cam)
	cam.make_current()
	var bubu := (load("res://scenes/characters/Bubu.tscn") as PackedScene).instantiate() as BasePlayer
	var dudu := (load("res://scenes/characters/Dudu.tscn") as PackedScene).instantiate() as BasePlayer
	world.add_child(bubu)
	world.add_child(dudu)
	bubu.global_position = Vector2(-50, 0)
	dudu.global_position = Vector2(50, 0)
	await _secs(0.8)
	_save("rig_idle")
	Input.action_press(&"p1_right")
	Input.action_press(&"p2_left")
	await _secs(0.35)
	_save("rig_walk")
	Input.action_release(&"p1_right")
	Input.action_release(&"p2_left")
	await _secs(0.6)
	Input.action_press(&"p1_jump")
	Input.action_press(&"p2_jump")
	cam.zoom = Vector2(2.0, 2.0)
	cam.position = Vector2(0, -60)
	await _secs(0.18)
	_save("rig_jump")
	Input.action_release(&"p1_jump")
	Input.action_release(&"p2_jump")
	await _secs(0.45)
	_save("rig_fall")
	await _secs(1.0)
	cam.zoom = Vector2(3.5, 3.5)
	cam.position = Vector2(0, -10)
	bubu.global_position = Vector2(-20, 0)
	dudu.global_position = Vector2(20, 0)
	bubu.show_hearts()
	dudu.show_hearts()
	await _secs(0.4)
	_save("rig_hug")
	await _secs(1.5)
	if bubu.can_hop_on(dudu):
		bubu.hop_on(dudu)
	await _secs(0.5)
	_save("rig_piggyback")
	bubu.dismount(false)
	await _secs(0.8)
	bubu.teleport_to(Vector2(-50, 0))
	dudu.teleport_to(Vector2(50, 0))
	await _secs(0.3)
	Input.action_press(&"p1_assist")
	await _secs(0.5)
	_save("rig_call")
	Input.action_release(&"p1_assist")
	world.queue_free()
	await frames(3)


func _save(shot_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	check(img != null and img.save_png("user://shots/%s.png" % shot_name) == OK, "shot saved: " + shot_name)


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
