class_name BasePlayer
extends CharacterBody2D
## Shared controller for Bubu and Dudu.
##
## Input: reads "p<player_index>_<verb>" actions (left/right/up/down/jump/interact/assist).
## Movement: coyote time, jump buffer, apex hang, soft falls, optional wall jump.
## Co-op:
##   - Assist tap near the partner: piggyback (or hug inside a CozySpot).
##   - Assist hold: Call/Tether, the partner floats over on a heart balloon.
##   - Jump while riding: hop off the partner's back (a boosted jump when grounded).
## Never punishing: hazards and falls send the player back to the partner on a heart
## balloon (or to the room checkpoint if both fell), nothing else is lost.

signal piggyback_started(rider: BasePlayer, carrier: BasePlayer)
signal piggyback_ended(rider: BasePlayer, carrier: BasePlayer)
signal balance_lost(player: BasePlayer)
signal respawned(player: BasePlayer)
signal landed(player: BasePlayer, impact_speed: float)
signal jumped(player: BasePlayer)
signal called_partner(player: BasePlayer)

enum State { NORMAL, RIDING, CLIMBING, BALLOON }

const PLAYERS_GROUP := &"players"
const WEIGHTED_GROUP := &"weighted"
const INTERACTABLES_GROUP := &"interactables"
const COZY_GROUP := &"cozy_spots"
## Only walls in this group (grooved blocks) can be wall-jumped. Keeps solo climbing
## from bypassing co-op height puzzles.
const WALLJUMP_GROUP := &"walljump"
## Layers that block bodies: world (1) + props (3).
const SOLID_MASK := 1 | 4

@export_group("Player")
## 1 = Bubu / first pad, 2 = Dudu / second pad. Selects the "p1_" / "p2_" actions.
@export_range(1, 2) var player_index: int = 1
@export var display_name: String = "Bubu"

@export_group("Character")
## Weight used by pressure plates, balances and fragile floors.
@export var weight: int = 1
## Can lift heavy (weight 2) items.
@export var strong: bool = false
@export var can_wall_jump: bool = false

@export_group("Run")
@export var move_speed: float = 230.0
@export var ground_accel: float = 2000.0
@export var ground_friction: float = 2400.0
@export_range(0.0, 1.0) var air_control: float = 0.85
## Any stick tilt past the deadzone means full speed (easier for new players).
@export var digital_horizontal: bool = true
@export_range(0.1, 1.0) var heavy_carry_speed_multiplier: float = 0.85

@export_group("Jump")
@export var jump_height: float = 150.0
@export var time_to_apex: float = 0.38
@export var fall_gravity_multiplier: float = 1.15
@export var max_fall_speed: float = 650.0
@export_range(0.0, 1.0) var jump_cut_multiplier: float = 0.5
@export_range(0.1, 1.0) var apex_gravity_multiplier: float = 0.6
@export var apex_threshold: float = 70.0
@export var coyote_time: float = 0.15
@export var jump_buffer_time: float = 0.18

@export_group("Wall jump")
@export var wall_slide_speed: float = 140.0
@export var wall_jump_push: float = 270.0
@export var wall_jump_lock_time: float = 0.16
@export var wall_coyote_time: float = 0.12

@export_group("Climb")
@export var climb_speed: float = 160.0

@export_group("Piggyback")
@export var piggyback_range: float = 80.0
## Assist presses shorter than this are taps (piggyback / hug).
@export var assist_tap_max_time: float = 0.25
## Holding Assist this long calls the partner over.
@export var call_hold_time: float = 0.7
@export var carry_speed_multiplier: float = 1.0
## Jump multiplier when hopping off a grounded partner's back.
@export_range(0.0, 1.5) var dismount_jump_multiplier: float = 1.0
@export var ride_overlap: float = 12.0

@export_group("Interact")
@export var interact_range: float = 60.0

@export_group("Screen leash")
@export var leash_enabled: bool = true

@export_group("Art")
## Folder with the character's vector parts (see tools/gen_sprites.py). Empty or
## missing = the geometric placeholder below.
@export_dir var art_dir: String = ""

@export_group("Placeholder art")
@export var body_color: Color = Color.WHITE
@export var accent_color: Color = Color.BLACK
@export var lower_color: Color = Color.BLACK
@export var marker_color: Color = Color(1.0, 0.45, 0.35)
@export var show_player_tag: bool = true

var state: State = State.NORMAL
## False during dialogue, hugs and transitions: inputs read as neutral.
var controls_enabled: bool = true
var facing: int = 1
var carrier: BasePlayer = null
var rider: BasePlayer = null
var carried_item: Node2D = null

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _assist_held_time: float = 0.0
var _assist_down: bool = false
var _call_fired: bool = false
var _jumping: bool = false
var _wall_coyote: float = 0.0
var _last_wall_dir: int = 0
var _wall_lock: float = 0.0
var _climb_cooldown: float = 0.0
var _pre_move_velocity: Vector2 = Vector2.ZERO
var _vines: Array[Node2D] = []
var _wind_zones: Array[Node2D] = []

var _balloon: HeartBalloon = null
var _balloon_time: float = 0.0
var _balloon_wait: float = 0.0

var _body_size: Vector2 = Vector2(44, 58)
var _rig: CharacterRig = null
var _fx_scale: Vector2 = Vector2.ONE
var _shake_time: float = 0.0
var _blink_time: float = 2.0
var _hearts_time: float = 0.0

var _act_left: StringName
var _act_right: StringName
var _act_up: StringName
var _act_down: StringName
var _act_jump: StringName
var _act_interact: StringName
var _act_assist: StringName

@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group(PLAYERS_GROUP)
	add_to_group(WEIGHTED_GROUP)
	_bind_actions()
	var rect := _collision.shape as RectangleShape2D
	if rect != null:
		_body_size = rect.size
	_blink_time = randf_range(1.5, 4.0)
	if art_dir != "":
		var rig := CharacterRig.new()
		rig.name = &"Rig"
		add_child(rig)
		if rig.setup(art_dir):
			_rig = rig
		else:
			rig.queue_free()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if state == State.BALLOON:
		_balloon_process(delta)
		_update_visual_fx(delta)
		return

	_update_assist(delta)

	if state == State.RIDING:
		if _just(_act_jump):
			dismount(true)
		_update_visual_fx(delta)
		return

	_wall_lock = maxf(_wall_lock - delta, 0.0)
	_climb_cooldown = maxf(_climb_cooldown - delta, 0.0)

	if state == State.NORMAL:
		_try_start_climb()
	if state == State.CLIMBING:
		_climb_process(delta)
	else:
		_update_jump(delta)
		_update_horizontal(delta)
		_apply_wind(delta)
		_apply_screen_leash()

	var was_on_floor := is_on_floor()
	_pre_move_velocity = velocity
	move_and_slide()
	_after_move(was_on_floor)

	if carried_item != null:
		if is_instance_valid(carried_item):
			carried_item.call(&"follow_carrier", self)
		else:
			carried_item = null
	if rider != null:
		rider._snap_to_carrier(self)

	if _just(_act_interact):
		_on_interact()
	_check_kill_plane()
	_update_visual_fx(delta)


# --- Input -------------------------------------------------------------------------

func _bind_actions() -> void:
	var prefix := "p%d_" % player_index
	_act_left = StringName(prefix + "left")
	_act_right = StringName(prefix + "right")
	_act_up = StringName(prefix + "up")
	_act_down = StringName(prefix + "down")
	_act_jump = StringName(prefix + "jump")
	_act_interact = StringName(prefix + "interact")
	_act_assist = StringName(prefix + "assist")
	for action: StringName in [_act_left, _act_right, _act_up, _act_down, _act_jump, _act_interact, _act_assist]:
		if not InputMap.has_action(action):
			push_error("%s: missing input action '%s'" % [name, action])


func _axis_h() -> float:
	if not controls_enabled:
		return 0.0
	var dir := Input.get_axis(_act_left, _act_right)
	if digital_horizontal and dir != 0.0:
		dir = signf(dir)
	return dir


func _axis_v() -> float:
	return Input.get_axis(_act_up, _act_down) if controls_enabled else 0.0


func _just(action: StringName) -> bool:
	return controls_enabled and Input.is_action_just_pressed(action)


func _released(action: StringName) -> bool:
	return controls_enabled and Input.is_action_just_released(action)


func _held(action: StringName) -> bool:
	return controls_enabled and Input.is_action_pressed(action)


func set_controls_enabled(value: bool) -> void:
	controls_enabled = value
	if not value:
		_assist_down = false
		_assist_held_time = 0.0
		_jump_buffer_timer = 0.0
		queue_redraw()


## Tap = piggyback / hug toggle. Hold = Call/Tether.
func _update_assist(delta: float) -> void:
	if _just(_act_assist):
		_assist_down = true
		_assist_held_time = 0.0
		_call_fired = false
	elif _assist_down:
		_assist_held_time += delta
		if not _held(_act_assist):
			_assist_down = false
			if _assist_held_time <= assist_tap_max_time:
				_on_assist_tap()
			queue_redraw()
		elif not _call_fired and _assist_held_time >= call_hold_time:
			_call_fired = true
			_try_call()
			queue_redraw()
		elif _assist_held_time > assist_tap_max_time:
			queue_redraw()


func _on_assist_tap() -> void:
	var partner := get_partner()
	# Hug takes priority inside a cozy spot.
	for spot in get_tree().get_nodes_in_group(COZY_GROUP):
		if spot.has_method("try_hug") and spot.call(&"try_hug", self):
			return
	if is_riding():
		dismount(false)
	elif rider != null:
		rider.dismount(false)
	elif partner != null and can_hop_on(partner):
		hop_on(partner)
	elif partner != null and partner.state == State.NORMAL:
		nope()


# --- Movement --------------------------------------------------------------------

func _gravity() -> float:
	return 2.0 * jump_height / (time_to_apex * time_to_apex)


func _jump_velocity() -> float:
	return -2.0 * jump_height / time_to_apex


func _update_jump(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		_coyote_timer = coyote_time
		_jumping = false
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_wall_coyote = maxf(_wall_coyote - delta, 0.0)

	if _just(_act_jump):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	var wall_ok := can_wall_jump and rider == null and not _carrying_heavy()
	if wall_ok and not on_floor and is_on_wall_only() and _touching_walljump_wall():
		_last_wall_dir = -int(signf(get_wall_normal().x))
		_wall_coyote = wall_coyote_time

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		_do_jump(_jump_velocity())
	elif _jump_buffer_timer > 0.0 and wall_ok and not on_floor and _wall_coyote > 0.0 and _last_wall_dir != 0:
		_do_jump(_jump_velocity() * 0.92)
		velocity.x = -_last_wall_dir * wall_jump_push
		_wall_lock = wall_jump_lock_time
		_wall_coyote = 0.0
		_set_facing(-_last_wall_dir)

	if _jumping and velocity.y < 0.0 and _released(_act_jump):
		velocity.y *= jump_cut_multiplier

	if not on_floor:
		var g := _gravity()
		if velocity.y > 0.0:
			g *= fall_gravity_multiplier
		if absf(velocity.y) < apex_threshold:
			g *= apex_gravity_multiplier
		velocity.y = minf(velocity.y + g * delta, max_fall_speed)
		# Wall slide: holding towards the wall slows the fall.
		if wall_ok and is_on_wall_only() and _touching_walljump_wall() and velocity.y > wall_slide_speed and int(signf(_axis_h())) == _last_wall_dir:
			velocity.y = wall_slide_speed


func _touching_walljump_wall() -> bool:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if absf(c.get_normal().x) > 0.7:
			var col := c.get_collider() as Node
			if col != null and col.is_in_group(WALLJUMP_GROUP):
				return true
	return false


func _do_jump(vy: float) -> void:
	velocity.y = vy
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_jumping = true
	_fx_scale = Vector2(0.82, 1.2)
	jumped.emit(self)
	Sfx.play("jump_heavy" if weight >= 2 else "jump")
	if randf() < 0.35:
		Voices.action(_voice_name(), "jump")


func _update_horizontal(delta: float) -> void:
	if _wall_lock > 0.0:
		return
	var dir := _axis_h()
	var speed := move_speed * (carry_speed_multiplier if rider != null else 1.0)
	if _carrying_heavy():
		speed *= heavy_carry_speed_multiplier
	var control := 1.0 if is_on_floor() else air_control
	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * speed, ground_accel * control * delta)
		_set_facing(int(signf(dir)))
	else:
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * control * delta)


func _apply_wind(delta: float) -> void:
	for zone in _wind_zones:
		if not is_instance_valid(zone) or not bool(zone.call(&"is_blowing")):
			continue
		var strength: float = zone.get(&"strength")
		var max_rise: float = zone.get(&"max_rise_speed")
		velocity.y = maxf(velocity.y - strength * delta, -max_rise)
		_jumping = false
		_coyote_timer = 0.0


## Soft tether: once outside the camera's widest view, outward movement is blocked.
func _apply_screen_leash() -> void:
	if not leash_enabled:
		return
	var cam := get_viewport().get_camera_2d() as CoopCamera2D
	if cam == null:
		return
	var leash := cam.get_leash_rect()
	if global_position.x < leash.position.x and velocity.x < 0.0:
		velocity.x = 0.0
	elif global_position.x > leash.end.x and velocity.x > 0.0:
		velocity.x = 0.0


func _after_move(was_on_floor: bool) -> void:
	if is_on_floor() and not was_on_floor:
		var impact := _pre_move_velocity.y
		if impact > 120.0:
			_fx_scale = Vector2(1.0 + clampf(impact / 2400.0, 0.08, 0.3), 1.0 - clampf(impact / 2600.0, 0.06, 0.25))
			Sfx.play("land_heavy" if weight >= 2 else "land", 0.08, -4.0)
		landed.emit(self, impact)
		var floor_body := _floor_collider()
		if floor_body != null and floor_body.has_method(&"on_landed"):
			floor_body.call(&"on_landed", self, impact)


func _floor_collider() -> Object:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().y < -0.6:
			return c.get_collider()
	return null


func _set_facing(value: int) -> void:
	if value != 0 and value != facing:
		facing = value
		queue_redraw()


func face_towards(x: float) -> void:
	_set_facing(1 if x >= global_position.x else -1)


func bounce(speed: float) -> void:
	velocity.y = -speed
	_jumping = false
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_fx_scale = Vector2(0.75, 1.3)


func launch(speed: float) -> void:
	bounce(speed)
	Sfx.play("launch")


func _check_kill_plane() -> void:
	var kill_y := INF
	var room := Room.find_for(self)
	if room != null:
		kill_y = room.get_kill_y()
	else:
		var cam := get_viewport().get_camera_2d() as CoopCamera2D
		if cam != null and cam.level_bounds.has_area():
			kill_y = cam.level_bounds.end.y + 96.0
	if global_position.y > kill_y:
		lose_balance()


# --- Climbing ---------------------------------------------------------------------

func register_vine(vine: Node2D) -> void:
	if not _vines.has(vine):
		_vines.append(vine)


func unregister_vine(vine: Node2D) -> void:
	_vines.erase(vine)


func register_wind(zone: Node2D) -> void:
	if not _wind_zones.has(zone):
		_wind_zones.append(zone)


func unregister_wind(zone: Node2D) -> void:
	_wind_zones.erase(zone)


func _try_start_climb() -> void:
	if _vines.is_empty() or carried_item != null or _climb_cooldown > 0.0:
		return
	var v := _axis_v()
	if v < -0.5 or (v > 0.5 and not is_on_floor()):
		state = State.CLIMBING
		velocity = Vector2.ZERO
		_jumping = false


func _climb_process(_delta: float) -> void:
	for i in range(_vines.size() - 1, -1, -1):
		if not is_instance_valid(_vines[i]):
			_vines.remove_at(i)
	if _vines.is_empty():
		state = State.NORMAL
		if velocity.y < 0.0:
			velocity.y = -300.0  # pop up onto the ledge above the vine
		return
	var v := _axis_v()
	var h := _axis_h()
	velocity = Vector2(h * climb_speed * 0.5, v * climb_speed)
	if h != 0.0:
		_set_facing(int(signf(h)))
	if _just(_act_jump):
		state = State.NORMAL
		_climb_cooldown = 0.3
		_do_jump(_jump_velocity() * 0.85)
		velocity.x = h * move_speed
		return
	if is_on_floor() and v > 0.0:
		state = State.NORMAL


# --- Interact & carry ----------------------------------------------------------------

func _on_interact() -> void:
	if state != State.NORMAL:
		return
	if carried_item != null:
		if not bool(carried_item.call(&"try_drop", self)):
			nope()
		return
	var best: Node = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group(INTERACTABLES_GROUP):
		if not n.has_method(&"can_interact") or not bool(n.call(&"can_interact", self)):
			continue
		var pos: Vector2 = n.call(&"get_interact_position")
		var d := global_position.distance_to(pos)
		var radius := maxf(interact_range, float(n.get(&"interact_radius")))
		if d <= radius and d < best_d:
			best = n
			best_d = d
	if best != null:
		best.call(&"interact", self)


func pick_up(item: Node2D) -> void:
	carried_item = item
	Sfx.play("pickup")


func release_item() -> void:
	carried_item = null


func _carrying_heavy() -> bool:
	return carried_item != null and is_instance_valid(carried_item) and int(carried_item.get(&"weight")) >= 2


## Total weight pressing down through this body (self + rider + carried item).
func get_weight() -> int:
	var w := weight
	if rider != null:
		w += rider.get_weight()
	if carried_item != null and is_instance_valid(carried_item):
		w += int(carried_item.get(&"weight"))
	return w


## "bubu" or "dudu", for voices and stickers.
func _voice_name() -> String:
	return "bubu" if player_index == 1 else "dudu"


func nope() -> void:
	_shake_time = 0.3
	Sfx.play("nope", 0.0, -2.0)
	Voices.action(_voice_name(), "nope")


# --- Piggyback ------------------------------------------------------------------------

func is_riding() -> bool:
	return carrier != null


func get_partner() -> BasePlayer:
	for node in get_tree().get_nodes_in_group(PLAYERS_GROUP):
		if node != self and node is BasePlayer:
			return node as BasePlayer
	return null


func can_hop_on(other: BasePlayer) -> bool:
	if other == null or other == self:
		return false
	if state != State.NORMAL or other.state != State.NORMAL:
		return false
	if rider != null or other.rider != null or carried_item != null or other.carried_item != null:
		return false
	return global_position.distance_to(other.global_position) <= piggyback_range


func hop_on(other: BasePlayer) -> void:
	carrier = other
	other.rider = self
	state = State.RIDING
	velocity = Vector2.ZERO
	_jump_buffer_timer = 0.0
	_vines.clear()
	_collision.set_deferred(&"disabled", true)
	_snap_to_carrier(other)
	Sfx.play("piggy_on")
	Voices.action(_voice_name(), "piggy")
	piggyback_started.emit(self, other)


## Leaves the carrier's back. Jumping off a grounded carrier is a boosted jump.
func dismount(jump: bool) -> void:
	if carrier == null:
		return
	var old_carrier := carrier
	carrier = null
	old_carrier.rider = null
	state = State.NORMAL
	var back_pos := global_position
	var boosted := jump and old_carrier.is_on_floor() and _is_free_at(back_pos)
	if boosted:
		velocity = Vector2(old_carrier.velocity.x, _jump_velocity() * dismount_jump_multiplier)
	else:
		global_position = _feet_aligned_on(old_carrier)
		velocity = Vector2(old_carrier.velocity.x, _jump_velocity() * 0.6 if jump else 0.0)
	_jumping = jump
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	if jump:
		_fx_scale = Vector2(0.82, 1.2)
		Sfx.play("jump")
	else:
		Sfx.play("piggy_off")
	_collision.set_deferred(&"disabled", false)
	reset_physics_interpolation()
	piggyback_ended.emit(self, old_carrier)


func _snap_to_carrier(other: BasePlayer) -> void:
	var lift := other._body_size.y * 0.5 + _body_size.y * 0.5 - ride_overlap
	global_position = other.global_position + Vector2(-other.facing * 4.0, -lift)
	velocity = other.velocity
	_set_facing(other.facing)


## Position that puts this body's feet where `other`'s feet are.
func _feet_aligned_on(other: BasePlayer) -> Vector2:
	return other.global_position + Vector2(0.0, other._body_size.y * 0.5 - _body_size.y * 0.5)


func _is_free_at(pos: Vector2, extra_exclude: Array[RID] = []) -> bool:
	var space := get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _collision.shape
	params.transform = Transform2D(0.0, pos)
	params.collision_mask = SOLID_MASK
	var exclude: Array[RID] = [get_rid()]
	exclude.append_array(extra_exclude)
	params.exclude = exclude
	return space.intersect_shape(params, 1).is_empty()


# --- Call / Tether ------------------------------------------------------------------

func _try_call() -> void:
	var partner := get_partner()
	if partner == null or partner.state == State.BALLOON:
		return
	if state != State.NORMAL or not is_on_floor() or rider != null:
		nope()
		return
	if global_position.distance_to(partner.global_position) < 140.0:
		return
	var room := Room.find_for(self)
	if room != null and not room.can_call(self, partner):
		nope()
		return
	partner.travel_to_partner()
	Sfx.play("call")
	Voices.action(_voice_name(), "call")
	Stickers.pop(get_parent(), _voice_name() + "_phone", global_position - Vector2(0, _body_size.y + 30.0), 96.0, 2.0)
	called_partner.emit(self)


## Floats this player over to the partner on a heart balloon.
func travel_to_partner() -> void:
	if state == State.BALLOON:
		return
	if is_riding():
		dismount(false)
	if rider != null:
		rider.dismount(false)
	if carried_item != null and is_instance_valid(carried_item):
		carried_item.call(&"force_drop", self)
	carried_item = null
	_enter_balloon(false)


# --- Losing balance & heart balloon ---------------------------------------------------

## Falls and hazards end here: no damage, just a balloon ride back to the partner.
func lose_balance() -> void:
	if state == State.BALLOON:
		return
	if is_riding():
		dismount(false)
	if rider != null:
		var r := rider
		r.dismount(false)
		r.lose_balance()
	if carried_item != null and is_instance_valid(carried_item):
		var item := carried_item
		carried_item = null
		item.call(&"respawn_home")
	carried_item = null
	_enter_balloon(true)


func _enter_balloon(fell: bool) -> void:
	state = State.BALLOON
	velocity = Vector2.ZERO
	_vines.clear()
	_wind_zones.clear()
	_collision.set_deferred(&"disabled", true)
	visible = false
	_balloon_time = 0.0
	_balloon_wait = 0.0
	if _balloon != null and is_instance_valid(_balloon):
		_balloon.queue_free()
	_balloon = HeartBalloon.new()
	# A fall rides the heart balloon; a call flies over (broom, scooter) when there's a sticker.
	var ride := _voice_name() + ("_balloon" if fell else "_fly")
	if not fell and Stickers.frames(ride) == null:
		ride = _voice_name() + "_balloon"
	_balloon.setup(body_color, lower_color, marker_color, ride)
	get_parent().add_child(_balloon)
	_balloon.global_position = global_position
	_balloon.reset_physics_interpolation()
	Sfx.play("balloon")
	if fell:
		Voices.action(_voice_name(), "fall")
	if fell:
		balance_lost.emit(self)


func is_in_balloon() -> bool:
	return state == State.BALLOON


func _balloon_process(delta: float) -> void:
	_balloon_time += delta
	if _balloon == null or not is_instance_valid(_balloon):
		_enter_balloon(false)
		return
	var target := _balloon_target()
	var goal: Vector2 = target["pos"]
	var is_safe: bool = target["ready"]
	# Hover above the goal while it is not safe yet.
	var hover := goal + Vector2(0.0, -70.0 if not is_safe else 0.0)
	var to_goal := hover - _balloon.global_position
	var speed := minf(160.0 + 1100.0 * _balloon_time, 1150.0)
	var step := speed * delta
	if _balloon_time < 0.3:
		_balloon.global_position += Vector2(0.0, -110.0 * delta)
	elif to_goal.length() <= step:
		_balloon.global_position = hover
	else:
		_balloon.global_position += to_goal.normalized() * step
	global_position = _balloon.global_position
	if is_safe and _balloon_time >= 0.7 and _balloon.global_position.distance_to(hover) < 2.0:
		_respawn_at(goal)
	elif not is_safe:
		_balloon_wait += delta


## Where the balloon should go and whether landing there is safe right now.
func _balloon_target() -> Dictionary:
	var partner := get_partner()
	if partner != null and partner.state != State.BALLOON and _balloon_wait < 6.0:
		var spot := _feet_aligned_on(partner)
		var ok := partner.state == State.NORMAL and partner.is_on_floor() and _is_free_at(spot, [partner.get_rid()])
		return {"pos": spot, "ready": ok}
	var room := Room.find_for(self)
	if room != null:
		return {"pos": room.get_checkpoint(player_index), "ready": true}
	return {"pos": global_position, "ready": true}


func _respawn_at(pos: Vector2) -> void:
	state = State.NORMAL
	global_position = pos
	velocity = Vector2.ZERO
	visible = true
	_collision.set_deferred(&"disabled", false)
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_jumping = false
	_fx_scale = Vector2(1.3, 0.7)
	if _balloon != null and is_instance_valid(_balloon):
		_balloon.pop()
	_balloon = null
	reset_physics_interpolation()
	Sfx.play("pop")
	respawned.emit(self)


## Instantly places the player (room start, restart). Clears every transient state.
func teleport_to(target: Vector2) -> void:
	if is_riding():
		dismount(false)
	if rider != null:
		rider.dismount(false)
	if _balloon != null and is_instance_valid(_balloon):
		_balloon.queue_free()
	_balloon = null
	carried_item = null
	_vines.clear()
	_wind_zones.clear()
	state = State.NORMAL
	visible = true
	_collision.set_deferred(&"disabled", false)
	global_position = target
	velocity = Vector2.ZERO
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	_jumping = false
	_wall_lock = 0.0
	_fx_scale = Vector2.ONE
	reset_physics_interpolation()


func show_hearts(duration: float = 1.6) -> void:
	_hearts_time = duration


# --- Placeholder art ---------------------------------------------------------------------

func _update_visual_fx(delta: float) -> void:
	_fx_scale = _fx_scale.lerp(Vector2.ONE, 1.0 - exp(-12.0 * delta))
	_shake_time = maxf(_shake_time - delta, 0.0)
	_hearts_time = maxf(_hearts_time - delta, 0.0)
	_blink_time -= delta
	if _blink_time < -0.12:
		_blink_time = randf_range(2.0, 5.0)
	if _rig != null:
		_rig.animate(self, delta)
		# The carrier is drawn in front, so the rider sits behind its head, like on a back.
		z_index = 1 if rider != null else 0
	queue_redraw()


func _draw() -> void:
	var half := _body_size * 0.5
	var ear := Vector2(_body_size.x * 0.28, _body_size.y * 0.16)
	if _rig == null:
		_draw_placeholder(half, ear)
	_draw_overlays(half, ear)


func _draw_placeholder(half: Vector2, ear: Vector2) -> void:
	var shake := sin(_shake_time * 60.0) * 4.0 * (_shake_time / 0.3)
	# Squash & stretch anchored at the feet.
	draw_set_transform(Vector2(shake, half.y * (1.0 - _fx_scale.y)), 0.0, _fx_scale)

	draw_rect(Rect2(-half, _body_size), body_color)
	var lower_h := _body_size.y * 0.32
	draw_rect(Rect2(Vector2(-half.x, half.y - lower_h), Vector2(_body_size.x, lower_h)), lower_color)
	draw_rect(Rect2(Vector2(-half.x, -half.y - ear.y * 0.5), ear), accent_color)
	draw_rect(Rect2(Vector2(half.x - ear.x, -half.y - ear.y * 0.5), ear), accent_color)

	# Face: eye (blinks), nose marker on the facing side.
	var eye_y := -half.y * 0.35
	var eye_pos := Vector2(facing * half.x * 0.45, eye_y)
	if _blink_time > 0.0:
		draw_circle(eye_pos, 3.5, accent_color)
	else:
		draw_line(eye_pos - Vector2(4, 0), eye_pos + Vector2(4, 0), accent_color, 2.0)
	var tip := Vector2(facing * (half.x + 8.0), eye_y + 4.0)
	var base := Vector2(facing * (half.x - 2.0), eye_y + 4.0)
	draw_colored_polygon(PackedVector2Array([tip, base + Vector2(0, -6), base + Vector2(0, 6)]), marker_color)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Player tag, call charge ring and hug hearts, drawn over either art style.
func _draw_overlays(half: Vector2, ear: Vector2) -> void:
	if show_player_tag and rider == null:
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-12, -half.y - ear.y - 8), "P%d" % player_index, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, accent_color)
		for i in weight:
			draw_circle(Vector2(12 + i * 7, -half.y - ear.y - 13), 2.5, accent_color)

	# Call charge ring while Assist is held.
	if _assist_down and _assist_held_time > assist_tap_max_time:
		var t := clampf((_assist_held_time - assist_tap_max_time) / (call_hold_time - assist_tap_max_time), 0.0, 1.0)
		draw_arc(Vector2(0, -half.y - 30), 12.0, -PI / 2.0, -PI / 2.0 + TAU * t, 24, marker_color, 3.0)

	if _hearts_time > 0.0:
		var k := 1.6 - _hearts_time
		for i in 3:
			var p := Vector2(-18 + i * 18, -half.y - 30 - k * 40.0 - i * 6.0)
			HeartBalloon.draw_heart(self, p, 7.0, Color(1.0, 0.4, 0.5, clampf(_hearts_time, 0.0, 1.0)))
