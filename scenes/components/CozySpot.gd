class_name CozySpot
extends Area2D
## A warm little place (bench, blanket, campfire). When both players stand inside and
## each taps Assist (Y) within `press_window`, they hug: controls lock, hearts fly, an
## optional dialogue plays, an optional memory is unlocked, the checkpoint moves here
## and `channel` turns on (it can open the way forward). Origin = floor center.

signal hugged

@export var size: Vector2 = Vector2(200, 120)
@export var dialogue: StringName = &""
@export var memory_id: String = ""
@export var channel: StringName = &""
## Seconds allowed between the two players' taps.
@export var press_window: float = 1.6
## Must hug again after a room restart only if false (default: remembered per save).
@export var remember: bool = true
## "bench", "blanket", "campfire" (visual only).
@export var kind: String = "bench"
@export var color: Color = Color(0.95, 0.6, 0.55)

var _room: Room
var _done: bool = false
var _busy: bool = false
var _pressed_at: Array[float] = [-100.0, -100.0]
var _clock: float = 0.0
var _glow: float = 0.0


func _ready() -> void:
	add_to_group(&"cozy_spots")
	CompUtil.setup_trigger(self)
	collision_mask = CompUtil.LAYER_PLAYERS
	CompUtil.add_rect_shape(self, size, Vector2(0, -size.y * 0.5))
	_room = Room.find_for(self)
	if remember and _flag_key() != "" and bool(GameState.get_flag(_flag_key())):
		_done = true
		_publish()


func _flag_key() -> String:
	if _room == null or _room.room_id == &"":
		return ""
	return "cozy_%s_%s" % [_room.room_id, name]


func is_done() -> bool:
	return _done


func _contains(p: BasePlayer) -> bool:
	if p == null or p.state == BasePlayer.State.BALLOON:
		return false
	if overlaps_body(p):
		return true
	return p.carrier != null and overlaps_body(p.carrier)


## Called by BasePlayer on an Assist tap. Returns true when the tap was used here.
func try_hug(player: BasePlayer) -> bool:
	if _done or _busy or not _contains(player):
		return false
	var partner := player.get_partner()
	if partner == null or not _contains(partner):
		# Alone in the spot: a gentle nudge, the tap is still consumed so it does not
		# turn into a piggyback by accident.
		CompUtil.toast(self, "Serve qualcuno da abbracciare...")
		return true
	var i := clampi(player.player_index - 1, 0, 1)
	_pressed_at[i] = _clock
	Sfx.play("ui_move", 0.0, -6.0)
	if absf(_pressed_at[0] - _pressed_at[1]) <= press_window:
		_hug(player, partner)
	return true


func _hug(a: BasePlayer, b: BasePlayer) -> void:
	_busy = true
	for p: BasePlayer in [a, b]:
		if p.is_riding():
			p.dismount(false)
	for p: BasePlayer in [a, b]:
		p.set_controls_enabled(false)
		p.velocity.x = 0.0
	a.face_towards(b.global_position.x)
	b.face_towards(a.global_position.x)
	a.show_hearts(2.2)
	b.show_hearts(2.2)
	Sfx.play("hug", 0.0)
	Voices.action("bubu", "hug")
	Voices.action("dudu", "hug")
	Stickers.pop(get_parent(), "both_hug", global_position - Vector2(0, size.y + 20.0), 150.0)
	_glow = 1.0
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	await CompUtil.play_dialogue(self, dialogue)
	if not is_inside_tree():
		return
	if memory_id != "" and GameState.collect_memory(memory_id):
		get_tree().call_group(&"memory_popup", &"show_memory", memory_id)
	if _room != null:
		_room.set_checkpoint(a.global_position if a.player_index == 1 else b.global_position,
			b.global_position if b.player_index == 2 else a.global_position)
		_room.checkpoint_reached.emit()
	_done = true
	_busy = false
	if remember and _flag_key() != "":
		GameState.set_flag(_flag_key())
	_publish()
	for p: BasePlayer in [a, b]:
		if is_instance_valid(p):
			p.set_controls_enabled(true)
	hugged.emit()


func _publish() -> void:
	if _room != null and channel != &"":
		_room.set_source(channel, CompUtil.source_id(self), true)


func _physics_process(delta: float) -> void:
	_clock += delta
	_glow = maxf(_glow - delta * 0.4, 0.0)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var c := color
	# Soft warm glow on the ground marks the spot.
	draw_rect(Rect2(-w * 0.5, -size.y, w, size.y), Color(1.0, 0.85, 0.6, 0.08 + 0.2 * _glow))
	match kind:
		"campfire":
			draw_rect(Rect2(-30, -10, 60, 10), Color(0.45, 0.3, 0.2))
			var flick := sin(_clock * 9.0) * 4.0
			draw_colored_polygon(PackedVector2Array([Vector2(-18, -10), Vector2(18, -10), Vector2(flick, -48)]), Color(1.0, 0.6, 0.2))
			draw_colored_polygon(PackedVector2Array([Vector2(-9, -10), Vector2(9, -10), Vector2(-flick * 0.5, -32)]), Color(1.0, 0.9, 0.4))
		"blanket":
			draw_rect(Rect2(-w * 0.35, -8, w * 0.7, 8), c)
			var x := -w * 0.35
			while x < w * 0.35:
				draw_rect(Rect2(x, -8, 10, 8), c.lightened(0.3))
				x += 20.0
		_:
			draw_rect(Rect2(-56, -30, 112, 8), c.darkened(0.2))
			draw_rect(Rect2(-56, -58, 112, 8), c.darkened(0.2))
			draw_rect(Rect2(-50, -30, 8, 30), c.darkened(0.45))
			draw_rect(Rect2(42, -30, 8, 30), c.darkened(0.45))
	if _done:
		HeartBalloon.draw_heart(self, Vector2(0, -size.y + 10.0 + sin(_clock * 2.0) * 3.0), 14.0, Color(1.0, 0.45, 0.55, 0.8))
		return
	# Prompt: a Y bubble per player, filled once that player has tapped.
	var players := CompUtil.players(get_tree())
	var font := ThemeDB.fallback_font
	for i in 2:
		var p := Vector2((i - 0.5) * 46.0, -size.y - 6.0 + sin(_clock * 3.0 + i) * 2.0)
		var inside := i < players.size() and _contains(players[i])
		var pressed := _clock - _pressed_at[i] <= press_window
		var col := Color(1.0, 0.8, 0.3) if pressed else Color(1, 1, 1, 0.85 if inside else 0.35)
		draw_circle(p, 14.0, col)
		draw_string(font, p + Vector2(-5, 6), "Y", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.25, 0.2, 0.2))
