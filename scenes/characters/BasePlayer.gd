class_name BasePlayer
extends CharacterBody2D
## Shared controller for Bubu and Dudu.
##
## - Per-player input: reads actions named "p<player_index>_<verb>" from the Input Map.
## - Forgiving platforming: coyote time, jump buffering, apex hang, gentle falls.
## - Piggyback: a short tap on Assist near the partner hops onto their back.
##   Holding Assist is reserved for Call/Tether (not implemented yet).
## - Placeholder art drawn in _draw(); the collision shape is the single source of size.

signal piggyback_started(rider: BasePlayer, carrier: BasePlayer)
signal piggyback_ended(rider: BasePlayer, carrier: BasePlayer)

const PLAYERS_GROUP := &"players"

@export_group("Player")
## 1 = Bubu / joypad 0, 2 = Dudu / joypad 1. Selects the "p1_" / "p2_" actions.
@export_range(1, 2) var player_index: int = 1

@export_group("Run")
@export var move_speed: float = 230.0
## Pixels/s² while accelerating on the ground.
@export var ground_accel: float = 2000.0
## Pixels/s² while slowing down on the ground with no input.
@export var ground_friction: float = 2400.0
## Fraction of ground acceleration available in the air (1.0 = full control).
@export_range(0.0, 1.0) var air_control: float = 0.85
## If true, any stick tilt past the deadzone means full speed (easier for new players).
@export var digital_horizontal: bool = true

@export_group("Jump")
## Peak height of a full jump, in pixels.
@export var jump_height: float = 150.0
## Seconds to reach the peak. Gravity and jump velocity are derived from these two.
@export var time_to_apex: float = 0.38
## Gravity multiplier while falling. Kept low on purpose: falls should feel soft.
@export var fall_gravity_multiplier: float = 1.15
## Terminal fall speed in pixels/s.
@export var max_fall_speed: float = 650.0
## Releasing Jump early multiplies upward velocity by this (short hop).
@export_range(0.0, 1.0) var jump_cut_multiplier: float = 0.5
## Near the apex (|vy| below threshold) gravity is scaled by this for extra hang time.
@export_range(0.1, 1.0) var apex_gravity_multiplier: float = 0.6
@export var apex_threshold: float = 70.0
## Grace period after walking off a ledge during which a jump still works.
@export var coyote_time: float = 0.15
## An early Jump press is remembered this long and fires on landing.
@export var jump_buffer_time: float = 0.18

@export_group("Piggyback")
## Max distance (pixels, center to center) to hop onto the partner.
@export var piggyback_range: float = 80.0
## Assist presses shorter than this count as a tap (piggyback); longer = hold (Call, later).
@export var assist_tap_max_time: float = 0.25
## Speed multiplier while carrying someone. 1.0 = no penalty (never punishing).
@export var carry_speed_multiplier: float = 1.0
## Fraction of jump velocity used when the rider jumps off.
@export_range(0.0, 1.5) var dismount_jump_multiplier: float = 0.75
## How much the rider sinks into the carrier's back, in pixels.
@export var ride_overlap: float = 12.0

@export_group("Screen leash")
## Stop walking outward once outside the camera's maximum view (soft tether).
@export var leash_enabled: bool = true

@export_group("Placeholder art")
@export var body_color: Color = Color.WHITE
## Ears and top accent.
@export var accent_color: Color = Color.BLACK
## Lower body band (legs).
@export var lower_color: Color = Color.BLACK
@export var marker_color: Color = Color(1.0, 0.45, 0.35)
@export var show_player_tag: bool = true

## +1 = facing right, -1 = facing left.
var facing: int = 1
## Partner whose back we are on, or null.
var carrier: BasePlayer = null
## Partner riding on our back, or null.
var rider: BasePlayer = null

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _assist_held_time: float = 0.0
var _assist_down: bool = false
var _jumping: bool = false

var _body_size: Vector2 = Vector2(44, 58)

var _act_left: StringName
var _act_right: StringName
var _act_jump: StringName
var _act_interact: StringName
var _act_assist: StringName

@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group(PLAYERS_GROUP)
	_bind_actions()
	var rect := _collision.shape as RectangleShape2D
	if rect != null:
		_body_size = rect.size
	queue_redraw()


func _physics_process(delta: float) -> void:
	_update_assist(delta)

	if is_riding():
		# The carrier positions us after it moves; we only listen for dismount.
		if Input.is_action_just_pressed(_act_jump):
			dismount(true)
		return

	_update_jump(delta)
	_update_horizontal(delta)
	_apply_screen_leash()
	move_and_slide()

	if rider != null:
		rider._snap_to_carrier(self)


# --- Input ---------------------------------------------------------------

func _bind_actions() -> void:
	var prefix := "p%d_" % player_index
	_act_left = StringName(prefix + "left")
	_act_right = StringName(prefix + "right")
	_act_jump = StringName(prefix + "jump")
	_act_interact = StringName(prefix + "interact")
	_act_assist = StringName(prefix + "assist")
	for action: StringName in [_act_left, _act_right, _act_jump, _act_interact, _act_assist]:
		if not InputMap.has_action(action):
			push_error("%s: missing input action '%s'" % [name, action])


## Tap = piggyback toggle. Hold is left free for Call/Tether.
func _update_assist(delta: float) -> void:
	if Input.is_action_just_pressed(_act_assist):
		_assist_down = true
		_assist_held_time = 0.0
	elif _assist_down:
		_assist_held_time += delta
		if Input.is_action_just_released(_act_assist):
			_assist_down = false
			if _assist_held_time <= assist_tap_max_time:
				_on_assist_tap()


func _on_assist_tap() -> void:
	if is_riding():
		dismount(false)
	elif rider != null:
		rider.dismount(false)
	else:
		var partner := get_partner()
		if partner != null and can_hop_on(partner):
			hop_on(partner)


# --- Movement ------------------------------------------------------------

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

	if Input.is_action_just_pressed(_act_jump):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	# Buffered press + still within coyote window => jump. Consume both timers.
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = _jump_velocity()
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_jumping = true

	# Variable height: releasing early while rising cuts the jump.
	if _jumping and velocity.y < 0.0 and Input.is_action_just_released(_act_jump):
		velocity.y *= jump_cut_multiplier

	if not on_floor:
		var g := _gravity()
		if velocity.y > 0.0:
			g *= fall_gravity_multiplier
		if absf(velocity.y) < apex_threshold:
			g *= apex_gravity_multiplier
		velocity.y = minf(velocity.y + g * delta, max_fall_speed)


func _update_horizontal(delta: float) -> void:
	var dir := Input.get_axis(_act_left, _act_right)
	if digital_horizontal and dir != 0.0:
		dir = signf(dir)

	var speed := move_speed * (carry_speed_multiplier if rider != null else 1.0)
	var control := 1.0 if is_on_floor() else air_control

	if dir != 0.0:
		velocity.x = move_toward(velocity.x, dir * speed, ground_accel * control * delta)
		_set_facing(int(signf(dir)))
	else:
		velocity.x = move_toward(velocity.x, 0.0, ground_friction * control * delta)


## Soft tether: once outside the camera's widest view, outward movement is blocked.
func _apply_screen_leash() -> void:
	if not leash_enabled:
		return
	var cam := get_viewport().get_camera_2d() as CoopCamera2D
	if cam == null:
		return
	var bounds := cam.get_leash_rect()
	if global_position.x < bounds.position.x and velocity.x < 0.0:
		velocity.x = 0.0
	elif global_position.x > bounds.end.x and velocity.x > 0.0:
		velocity.x = 0.0


func _set_facing(value: int) -> void:
	if value != 0 and value != facing:
		facing = value
		queue_redraw()


# --- Piggyback -----------------------------------------------------------

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
	if is_riding() or rider != null or other.is_riding() or other.rider != null:
		return false
	return global_position.distance_to(other.global_position) <= piggyback_range


func hop_on(other: BasePlayer) -> void:
	carrier = other
	other.rider = self
	velocity = Vector2.ZERO
	_jump_buffer_timer = 0.0
	_collision.set_deferred(&"disabled", true)
	_snap_to_carrier(other)
	piggyback_started.emit(self, other)


## Leaves the carrier's back. With jump = true, hops off with a small boost.
func dismount(jump: bool) -> void:
	if carrier == null:
		return
	var old_carrier := carrier
	carrier = null
	old_carrier.rider = null
	# The carrier's spot is guaranteed free of world geometry; players don't collide.
	global_position = old_carrier.global_position
	velocity = Vector2(old_carrier.velocity.x, 0.0)
	if jump:
		velocity.y = _jump_velocity() * dismount_jump_multiplier
		_jumping = true
	_coyote_timer = 0.0
	_collision.set_deferred(&"disabled", false)
	piggyback_ended.emit(self, old_carrier)


func _snap_to_carrier(other: BasePlayer) -> void:
	var lift := other._body_size.y * 0.5 + _body_size.y * 0.5 - ride_overlap
	global_position = other.global_position + Vector2(-other.facing * 4.0, -lift)
	velocity = other.velocity
	_set_facing(other.facing)


## Instantly moves the player (debug reset now, heart-balloon return later).
func teleport_to(target: Vector2) -> void:
	if is_riding():
		dismount(false)
	if rider != null:
		rider.dismount(false)
	global_position = target
	velocity = Vector2.ZERO
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	reset_physics_interpolation()


# --- Placeholder art -----------------------------------------------------

func _draw() -> void:
	var half := _body_size * 0.5
	var body := Rect2(-half, _body_size)
	draw_rect(body, body_color)

	# Lower band (legs) and two ears.
	var lower_h := _body_size.y * 0.32
	draw_rect(Rect2(Vector2(-half.x, half.y - lower_h), Vector2(_body_size.x, lower_h)), lower_color)
	var ear := Vector2(_body_size.x * 0.28, _body_size.y * 0.16)
	draw_rect(Rect2(Vector2(-half.x, -half.y - ear.y * 0.5), ear), accent_color)
	draw_rect(Rect2(Vector2(half.x - ear.x, -half.y - ear.y * 0.5), ear), accent_color)

	# Facing marker: a nose triangle on the facing side at eye height.
	var eye_y := -half.y * 0.35
	var tip := Vector2(facing * (half.x + 8.0), eye_y)
	var base := Vector2(facing * (half.x - 2.0), eye_y)
	draw_colored_polygon(PackedVector2Array([tip, base + Vector2(0, -6), base + Vector2(0, 6)]), marker_color)
	draw_circle(Vector2(facing * half.x * 0.45, eye_y), 3.5, accent_color)

	if show_player_tag:
		var font := ThemeDB.fallback_font
		var tag := "P%d" % player_index
		draw_string(font, Vector2(-10, -half.y - ear.y - 6), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, accent_color)
