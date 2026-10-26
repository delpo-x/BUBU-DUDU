extends "res://tests/TestBase.gd"
## Records short looping clips of the two characters (StickerRig) for animated GIFs.
## Not part of the default suite; needs a real window, not --headless:
##   godot --fixed-fps 60 --path . --script res://tests/run.gd -- gifs [clip names]
##   python -I tools/make_gif.py
## Each clip is saved as raw RGB frames in user://gifs/<clip>.rgb; make_gif.py encodes them.

## Physics frames per recorded frame (60 fps / 3 = 20 fps, 5 cs per GIF frame).
const FRAME_STEP := 3
const OUT_SIZE := Vector2i(480, 360)
## Screen y of the ground line (the crop keeps the full height, so the GIF ground sits at 4/5).
const GROUND_Y := 576.0
## Ground decor repeats every this many pixels; walking clips move a whole number of periods.
const DECOR_PERIOD := 80.0
const WALK_SPEED := 200.0

const CLIPS: Array[String] = ["ciao", "abbraccio", "salto", "passeggiata", "cavalluccio"]

var _world: Node2D
var _cam: Camera2D
var _bubu: BasePlayer
var _dudu: BasePlayer


func run() -> void:
	var wanted: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if CLIPS.has(a):
			wanted.append(a)
	if wanted.is_empty():
		wanted = CLIPS.duplicate()
	DirAccess.make_dir_recursive_absolute("user://gifs")
	for clip in wanted:
		await _stage(clip)
		match clip:
			"ciao":
				await _clip_ciao()
			"abbraccio":
				await _clip_abbraccio()
			"salto":
				await _clip_salto()
			"passeggiata":
				await _clip_passeggiata()
			"cavalluccio":
				await _clip_cavalluccio()
		_world.queue_free()
		await frames(3)


## Fresh set: sky, ground with tufts and flowers, the two characters with UI markers off.
func _stage(_clip: String) -> void:
	_world = Node2D.new()
	get_tree().root.add_child(_world)
	var sky := CanvasLayer.new()
	sky.layer = -1
	_world.add_child(sky)
	var sky_draw := Control.new()
	sky_draw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sky_draw.draw.connect(func() -> void:
		var s := sky_draw.size
		sky_draw.draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 0.91, 0.86))
		for c in [Vector3(0.22, 0.2, 54.0), Vector3(0.3, 0.24, 38.0), Vector3(0.74, 0.14, 46.0), Vector3(0.82, 0.19, 34.0)]:
			sky_draw.draw_circle(Vector2(s.x * c.x, s.y * c.y), c.z, Color(1, 1, 1, 0.7)))
	sky.add_child(sky_draw)

	var floor_body := StaticBody2D.new()
	floor_body.position = Vector2(0, 10)
	_world.add_child(floor_body)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8000, 20)
	shape.shape = rect
	floor_body.add_child(shape)
	var ground := Node2D.new()
	ground.draw.connect(func() -> void:
		ground.draw_rect(Rect2(-4000, 0, 8000, 400), Color(0.64, 0.8, 0.54))
		ground.draw_rect(Rect2(-4000, 0, 8000, 3), Color(0.52, 0.7, 0.44))
		var x := -4000.0
		while x < 4000.0:
			ground.draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 3, -7), Vector2(x + 6, 0)]), Color(0.47, 0.66, 0.4))
			ground.draw_colored_polygon(PackedVector2Array([Vector2(x + 5, 0), Vector2(x + 9, -10), Vector2(x + 11, 0)]), Color(0.47, 0.66, 0.4))
			ground.draw_circle(Vector2(x + 44, 12), 3.0, Color(1.0, 0.7, 0.76))
			ground.draw_circle(Vector2(x + 44, 12), 1.2, Color(1.0, 0.92, 0.6))
			x += DECOR_PERIOD)
	_world.add_child(ground)

	_cam = Camera2D.new()
	_world.add_child(_cam)
	_cam.make_current()
	_bubu = _actor("res://scenes/characters/Bubu.tscn")
	_dudu = _actor("res://scenes/characters/Dudu.tscn")
	await frames(2)


func _actor(path: String) -> BasePlayer:
	var p := (load(path) as PackedScene).instantiate() as BasePlayer
	p.show_player_tag = false
	p.leash_enabled = false
	p.marker_color = Color(0, 0, 0, 0)
	p.call_hold_time = 99.0
	p.move_speed = WALK_SPEED
	_world.add_child(p)
	return p


## Frames the camera so the ground sits at GROUND_Y with this zoom, around world x.
func _frame(zoom: float, x: float = 0.0) -> void:
	_cam.zoom = Vector2(zoom, zoom)
	_cam.position = Vector2(x, -(GROUND_Y - 360.0) / zoom)


func _place(bx: float, dx: float) -> void:
	_bubu.teleport_to(Vector2(bx, -_bubu._body_size.y * 0.5))
	_dudu.teleport_to(Vector2(dx, -_dudu._body_size.y * 0.5))


## Runs `step(frame)` every physics frame and keeps every FRAME_STEP-th rendered frame.
func _record(clip: String, total: int, step: Callable) -> void:
	var buf := PackedByteArray()
	var count := 0
	for f in total:
		step.call(f)
		await get_tree().process_frame
		if f % FRAME_STEP != 0:
			continue
		var img := get_viewport().get_texture().get_image()
		var h := img.get_height()
		var w := int(h * float(OUT_SIZE.x) / OUT_SIZE.y)
		img = img.get_region(Rect2i((img.get_width() - w) / 2, 0, w, h))
		img.resize(OUT_SIZE.x, OUT_SIZE.y, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		buf.append_array(img.get_data())
		count += 1
	var file := FileAccess.open("user://gifs/%s.rgb" % clip, FileAccess.WRITE)
	file.store_32(OUT_SIZE.x)
	file.store_32(OUT_SIZE.y)
	file.store_32(count)
	file.store_32(int(round(FRAME_STEP * 100.0 / 60.0)))
	file.store_buffer(buf)
	file.close()
	check(count > 0, "clip recorded: %s (%d frames)" % [clip, count])


## Pre-roll: runs `step` without recording (e.g. so a following camera is already settled).
func _run(total: int, step: Callable) -> void:
	for f in total:
		step.call(f)
		await get_tree().process_frame


func _hold(action: StringName, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


# --- Clips -------------------------------------------------------------------------------

## Waving at each other: Bubu first, then Dudu.
func _clip_ciao() -> void:
	_frame(4.4)
	_place(-42, 42)
	_bubu.facing = 1
	_dudu.facing = -1
	await frames(40)
	await _record("ciao", 168, func(f: int) -> void:
		_hold(&"p1_assist", f >= 6 and f < 84)
		_hold(&"p2_assist", f >= 72 and f < 156))
	_hold(&"p1_assist", false)
	_hold(&"p2_assist", false)


## A hug with hearts, twice (wider shot so the hearts stay in frame).
func _clip_abbraccio() -> void:
	_frame(3.4)
	_place(-17, 17)
	_bubu.facing = 1
	_dudu.facing = -1
	await frames(40)
	await _record("abbraccio", 192, func(f: int) -> void:
		if f == 0 or f == 96:
			_bubu.show_hearts()
			_dudu.show_hearts())


## Jumping together, twice, landing back on the same spot.
func _clip_salto() -> void:
	_frame(2.4)
	_place(-40, 40)
	_bubu.facing = 1
	_dudu.facing = -1
	await frames(40)
	await _record("salto", 180, func(f: int) -> void:
		var down := (f >= 12 and f < 34) or (f >= 102 and f < 124)
		_hold(&"p1_jump", down)
		_hold(&"p2_jump", down))


## Walking side by side; the camera follows, so the clip loops on the ground decor.
func _clip_passeggiata() -> void:
	_frame(4.0)
	_place(-34, 34)
	_hold(&"p1_right", true)
	_hold(&"p2_right", true)
	var follow := func(_f: int) -> void:
		_cam.position.x = (_bubu.global_position.x + _dudu.global_position.x) * 0.5
	await _run(60, follow)
	await _record("passeggiata", _loop_frames(), follow)
	_hold(&"p1_right", false)
	_hold(&"p2_right", false)


## Piggyback ride: Bubu on Dudu's back, Dudu walking.
func _clip_cavalluccio() -> void:
	_frame(4.0)
	_place(-20, 20)
	await frames(20)
	if _bubu.can_hop_on(_dudu):
		_bubu.hop_on(_dudu)
	await frames(30)
	check(_bubu.is_riding(), "piggyback staged")
	_hold(&"p2_right", true)
	var follow := func(_f: int) -> void:
		_cam.position.x = _dudu.global_position.x
	await _run(60, follow)
	await _record("cavalluccio", _loop_frames(), follow)
	_hold(&"p2_right", false)


## Frames for a walking clip that moves exactly a whole number of decor periods (seamless).
func _loop_frames() -> int:
	var per_frame := WALK_SPEED / 60.0
	var periods := 6
	return int(round(periods * DECOR_PERIOD / per_frame))
