class_name CarryableItem
extends RigidBody2D
## A crate that can be picked up with Interact (B), carried overhead and put down or
## tossed. Heavy crates (weight 2) can only be lifted by a strong character.
## Crates are not pushable: walking into one treats it like a wall, so puzzles stay
## predictable. Lost crates (pits, hazards) pop back to where they started.

## A free crate also lands on players (rests on a head) instead of sinking into them,
## which would push the player down into the floor.
const FREE_MASK := CompUtil.LAYER_WORLD | CompUtil.LAYER_PROPS | CompUtil.LAYER_PLAYERS

@export var size: Vector2 = Vector2(40, 40)
@export var weight: int = 1
@export var interact_radius: float = 64.0
@export var color: Color = Color(0.72, 0.52, 0.32)

var carrier: BasePlayer = null
var _home: Vector2
var _room: Room
var _shape: CollisionShape2D
var _pending: bool = false
var _pending_pos: Vector2
var _pending_vel: Vector2
var _poof: float = 0.0


func _ready() -> void:
	add_to_group(&"weighted")
	add_to_group(&"interactables")
	add_to_group(&"props")
	collision_layer = CompUtil.LAYER_PROPS
	collision_mask = FREE_MASK
	lock_rotation = true
	mass = 1.0 + weight
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	var mat := PhysicsMaterial.new()
	mat.friction = 1.0
	mat.bounce = 0.0
	physics_material_override = mat
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	_shape = CompUtil.add_rect_shape(self, size)
	_home = global_position
	add_to_group(Room.STATE_GROUP)
	_room = Room.find_for(self)


func get_weight() -> int:
	return 0 if carrier != null else weight


func get_interact_position() -> Vector2:
	return global_position


func can_interact(player: BasePlayer) -> bool:
	return carrier == null and player.carried_item == null and player.rider == null \
		and player.state == BasePlayer.State.NORMAL


func interact(player: BasePlayer) -> void:
	if weight >= 2 and not player.strong:
		player.nope()
		CompUtil.toast(self, "Troppo pesante per %s!" % player.display_name)
		return
	carrier = player
	freeze = true
	collision_layer = 0
	collision_mask = 0
	z_index = 5
	player.pick_up(self)


## Called by the carrier every physics frame after it moves.
func follow_carrier(player: BasePlayer) -> void:
	var lift := player._body_size.y * 0.5 + size.y * 0.5 + 2.0
	global_position = player.global_position + Vector2(0.0, -lift)


## Puts the crate down in front (or keeps it where it is, above the head).
## Moving players toss it forward. Returns false if there is no free space.
func try_drop(player: BasePlayer) -> bool:
	var feet_y := player.global_position.y + player._body_size.y * 0.5
	var front := Vector2(player.global_position.x + player.facing * (player._body_size.x * 0.5 + size.x * 0.5 + 6.0), feet_y - size.y * 0.5 - 1.0)
	var candidates: Array[Vector2] = [front, front + Vector2(0, -24), global_position]
	for c in candidates:
		if _is_free(c, player):
			var toss := Vector2(player.velocity.x * 0.8, minf(player.velocity.y, 0.0) * 0.5 - 60.0)
			if absf(player.velocity.x) > 40.0:
				toss.x += player.facing * 160.0
				Sfx.play("throw")
			else:
				Sfx.play("drop")
			_release(c, toss)
			return true
	return false


## Drops immediately where it is (carrier was called away).
func force_drop(_player: BasePlayer) -> void:
	_release(global_position, Vector2.ZERO)


func respawn_home() -> void:
	_poof = 0.3
	Sfx.play("pop", 0.05, -4.0)
	_release(_home, Vector2.ZERO)


func _release(pos: Vector2, vel: Vector2) -> void:
	if carrier != null:
		carrier.release_item()
	carrier = null
	z_index = 0
	collision_layer = CompUtil.LAYER_PROPS
	collision_mask = FREE_MASK
	global_position = pos
	freeze = false
	_pending = true
	_pending_pos = pos
	_pending_vel = vel
	sleeping = false
	reset_physics_interpolation()


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _pending:
		_pending = false
		state.transform = Transform2D(0.0, _pending_pos)
		state.linear_velocity = _pending_vel
		state.angular_velocity = 0.0


func _is_free(pos: Vector2, player: BasePlayer) -> bool:
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _shape.shape
	params.transform = Transform2D(0.0, pos)
	params.collision_mask = CompUtil.LAYER_WORLD | CompUtil.LAYER_PROPS | CompUtil.LAYER_PLAYERS
	params.exclude = [get_rid(), player.get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(params, 1).is_empty()


func _physics_process(delta: float) -> void:
	_poof = maxf(_poof - delta, 0.0)
	if carrier != null and not is_instance_valid(carrier):
		carrier = null
		respawn_home()
	if carrier == null and _room != null and global_position.y > _room.get_kill_y():
		respawn_home()
	queue_redraw()


func _draw() -> void:
	var half := size * 0.5
	var c := color.darkened(0.15) if weight >= 2 else color
	draw_rect(Rect2(-half, size), c)
	draw_rect(Rect2(-half, size), c.darkened(0.4), false, 3.0)
	draw_line(-half + Vector2(4, 4), half - Vector2(4, 4), c.darkened(0.3), 3.0)
	draw_line(Vector2(-half.x + 4, half.y - 4), Vector2(half.x - 4, -half.y + 4), c.darkened(0.3), 3.0)
	for i in weight:
		draw_circle(Vector2((i - (weight - 1) * 0.5) * 10.0, 0), 4.0, c.lightened(0.45))
	if _poof > 0.0:
		draw_arc(Vector2.ZERO, half.x + 20.0 * (1.0 - _poof / 0.3), 0.0, TAU, 24, Color(1, 1, 1, _poof / 0.3), 3.0)


# --- Checkpoint save (see Room.capture_state) ---------------------------------------

## Where the crate is (a carried one is put down under its carrier's feet).
func snapshot() -> Variant:
	var pos := global_position
	if carrier != null and is_instance_valid(carrier):
		pos = carrier.global_position + Vector2(carrier.facing * 40.0, 0.0)
	return {"x": pos.x, "y": pos.y}


func restore(d: Dictionary) -> void:
	_release(Vector2(float(d.get("x", _home.x)), float(d.get("y", _home.y))), Vector2.ZERO)
