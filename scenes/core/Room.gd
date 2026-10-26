class_name Room
extends Node2D
## Base script for every Room_XX.tscn.
##
## - Owns the room's bounds (camera clamp + fall-out plane) and background.
## - Logic bus: activators (plates, buttons, levers...) call set_source(channel, id, on);
##   receivers (gates, platforms, exits...) listen to channel_changed and use evaluate().
##   A channel is active while ANY of its sources is active.
## - Spawn points: children "Spawns/P1" and "Spawns/P2" (Marker2D).
## - Call policy: Call/Tether is allowed when call_allowed is true, neither player is in a
##   CallBlockZone, or once the room exit is unlocked.

signal channel_changed(channel: StringName, active: bool)
signal completed
signal exit_unlocked_changed(unlocked: bool)
## A lantern was lit or a cozy spot hugged: a good moment to save mid-room.
signal checkpoint_reached

const ROOMS_GROUP := &"rooms"
## Components with puzzle state to keep in a mid-room save: snapshot() -> Variant (null =
## nothing worth keeping) and restore(Dictionary).
const STATE_GROUP := &"room_state"

@export var room_id: StringName = &""
## Playable area in world coordinates. The camera never shows outside it.
@export var bounds: Rect2 = Rect2(0, 0, 1920, 1080)
@export var background_color: Color = Color(0.86, 0.87, 0.89)
## Decorative backdrop style drawn behind geometry ("meadow", "town", "cave", "sky", "night", "plain").
@export var backdrop: String = "plain"
@export var backdrop_seed: int = 1
@export var call_allowed: bool = true
@export var camera_min_zoom: float = 0.55
@export var camera_max_zoom: float = 1.0
## Dialogue played the first time the room is entered.
@export var intro_dialogue: StringName = &""
## Gentle hint shown only on request from the pause menu.
@export_multiline var hint_text: String = ""
## Designer estimate of first-time play minutes for this room (used by the duration report).
@export var est_minutes: float = 5.0

var exit_unlocked: bool = false:
	set(value):
		if value != exit_unlocked:
			exit_unlocked = value
			exit_unlocked_changed.emit(value)

var _sources: Dictionary = {}          # channel -> {source_id: bool}
var _checkpoints: Array[Vector2] = []  # per player index - 1
var _completed: bool = false


func _ready() -> void:
	add_to_group(ROOMS_GROUP)
	_checkpoints = [get_spawn(1), get_spawn(2)]
	queue_redraw()


## Finds the Room that contains `node`, or null (e.g. in the test gym).
static func find_for(node: Node) -> Room:
	var n := node
	while n != null:
		if n is Room:
			return n as Room
		n = n.get_parent()
	# Players live outside the room in the Game scene: fall back to the active room.
	if node != null and node.is_inside_tree():
		var rooms := node.get_tree().get_nodes_in_group(ROOMS_GROUP)
		if not rooms.is_empty():
			return rooms[0] as Room
	return null


# --- Logic bus -------------------------------------------------------------------

func set_source(channel: StringName, source_id: String, active: bool) -> void:
	if channel == &"":
		return
	var before := is_active(channel)
	var src: Dictionary = _sources.get(channel, {})
	src[source_id] = active
	_sources[channel] = src
	var after := is_active(channel)
	if before != after:
		channel_changed.emit(channel, after)


func is_active(channel: StringName) -> bool:
	var src: Dictionary = _sources.get(channel, {})
	for v: bool in src.values():
		if v:
			return true
	return false


## ALL (default) or ANY of `channels` active. Empty list = always true.
func evaluate(channels: Array[StringName], require_all: bool = true) -> bool:
	if channels.is_empty():
		return true
	for c in channels:
		var on := is_active(c)
		if require_all and not on:
			return false
		if not require_all and on:
			return true
	return require_all


func active_count(channels: Array[StringName]) -> int:
	var n := 0
	for c in channels:
		if is_active(c):
			n += 1
	return n


# --- Spawns, checkpoints, bounds -------------------------------------------------

func get_spawn(player_index: int) -> Vector2:
	var marker := get_node_or_null("Spawns/P%d" % player_index) as Node2D
	if marker != null:
		return marker.global_position
	return bounds.position + Vector2(96.0 + 64.0 * player_index, bounds.size.y - 160.0)


func get_checkpoint(player_index: int) -> Vector2:
	var i := clampi(player_index - 1, 0, 1)
	if i < _checkpoints.size():
		return _checkpoints[i]
	return get_spawn(player_index)


func set_checkpoint(p1_pos: Vector2, p2_pos: Vector2) -> void:
	_checkpoints = [p1_pos, p2_pos]


## Puzzle state for a mid-room save: each stateful component's snapshot by node path,
## plus the respawn points.
func capture_state() -> Dictionary:
	var nodes := {}
	for n in get_tree().get_nodes_in_group(STATE_GROUP):
		if is_ancestor_of(n):
			var snap: Variant = n.call(&"snapshot")
			if snap != null:
				nodes[String(get_path_to(n))] = snap
	var cps: Array = []
	for c in _checkpoints:
		cps.append([c.x, c.y])
	return {"nodes": nodes, "checkpoints": cps}


func restore_state(d: Dictionary) -> void:
	var nodes: Dictionary = d.get("nodes", {})
	for path: String in nodes.keys():
		var n := get_node_or_null(NodePath(path))
		if n != null and n.has_method(&"restore") and nodes[path] is Dictionary:
			n.call(&"restore", nodes[path])
	var cps: Array = d.get("checkpoints", [])
	if cps.size() == 2:
		set_checkpoint(Vector2(float(cps[0][0]), float(cps[0][1])), Vector2(float(cps[1][0]), float(cps[1][1])))


func get_kill_y() -> float:
	return bounds.end.y + 96.0


# --- Call policy ------------------------------------------------------------------

func can_call(holder: Node2D, partner: Node2D) -> bool:
	if exit_unlocked:
		return true
	if not call_allowed:
		return false
	for zone in get_tree().get_nodes_in_group(&"call_block_zones"):
		if zone.has_method("contains_point") and (zone.contains_point(holder.global_position) or zone.contains_point(partner.global_position)):
			return false
	return true


# --- Completion ---------------------------------------------------------------------

func complete() -> void:
	if _completed:
		return
	_completed = true
	completed.emit()


func is_completed() -> bool:
	return _completed


# --- Backdrop -------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(bounds, background_color)
	var rng := RandomNumberGenerator.new()
	rng.seed = backdrop_seed
	var far := background_color.darkened(0.08)
	var near := background_color.darkened(0.14)
	match backdrop:
		"meadow":
			_draw_hills(rng, far, 0.62, 260.0)
			_draw_hills(rng, near, 0.75, 180.0)
			_draw_clouds(rng, background_color.lightened(0.35), 6)
		"town":
			_draw_skyline(rng, far, 0.55)
			_draw_skyline(rng, near, 0.68)
			_draw_clouds(rng, background_color.lightened(0.3), 4)
		"cave":
			_draw_stalactites(rng, near)
			_draw_hills(rng, far, 0.8, 120.0)
		"sky":
			_draw_clouds(rng, background_color.lightened(0.4), 12)
			_draw_clouds(rng, background_color.lightened(0.2), 8)
		"night":
			_draw_stars(rng, background_color.lightened(0.6), 70)
			_draw_hills(rng, near, 0.78, 160.0)
		_:
			pass


func _draw_hills(rng: RandomNumberGenerator, color: Color, level: float, amp: float) -> void:
	var pts := PackedVector2Array()
	var base_y := bounds.position.y + bounds.size.y * level
	var step := 160.0
	var x := bounds.position.x
	pts.append(Vector2(x, bounds.end.y))
	while x <= bounds.end.x + step:
		pts.append(Vector2(x, base_y - rng.randf_range(0.2, 1.0) * amp * 0.5))
		x += step
	pts.append(Vector2(bounds.end.x + step, bounds.end.y))
	# Smooth the silhouette a little by averaging neighbours.
	for i in range(2, pts.size() - 2):
		var p := pts[i]
		p.y = (pts[i - 1].y + p.y * 2.0 + pts[i + 1].y) / 4.0
		pts[i] = p
	draw_colored_polygon(pts, color)


func _draw_skyline(rng: RandomNumberGenerator, color: Color, level: float) -> void:
	var x := bounds.position.x
	var base_y := bounds.position.y + bounds.size.y * level
	while x < bounds.end.x:
		var w := rng.randf_range(80.0, 200.0)
		var h := rng.randf_range(80.0, 320.0)
		draw_rect(Rect2(x, base_y - h, w - 12.0, bounds.end.y - base_y + h), color)
		if rng.randf() < 0.5:
			draw_colored_polygon(PackedVector2Array([
				Vector2(x - 6.0, base_y - h), Vector2(x + (w - 12.0) * 0.5, base_y - h - 50.0),
				Vector2(x + w - 6.0, base_y - h)]), color)
		x += w
	draw_rect(Rect2(bounds.position.x, base_y, bounds.size.x, bounds.end.y - base_y), color)


func _draw_clouds(rng: RandomNumberGenerator, color: Color, count: int) -> void:
	for i in count:
		var c := Vector2(rng.randf_range(bounds.position.x, bounds.end.x), rng.randf_range(bounds.position.y + 40.0, bounds.position.y + bounds.size.y * 0.45))
		var r := rng.randf_range(26.0, 54.0)
		draw_circle(c, r, color)
		draw_circle(c + Vector2(r * 0.9, r * 0.2), r * 0.75, color)
		draw_circle(c - Vector2(r * 0.9, -r * 0.25), r * 0.65, color)


func _draw_stalactites(rng: RandomNumberGenerator, color: Color) -> void:
	var x := bounds.position.x
	while x < bounds.end.x:
		var w := rng.randf_range(40.0, 120.0)
		var h := rng.randf_range(40.0, 200.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x, bounds.position.y), Vector2(x + w, bounds.position.y), Vector2(x + w * 0.5, bounds.position.y + h)]), color)
		x += w + rng.randf_range(20.0, 140.0)


func _draw_stars(rng: RandomNumberGenerator, color: Color, count: int) -> void:
	for i in count:
		var c := Vector2(rng.randf_range(bounds.position.x, bounds.end.x), rng.randf_range(bounds.position.y, bounds.position.y + bounds.size.y * 0.6))
		draw_circle(c, rng.randf_range(1.5, 3.5), color)
