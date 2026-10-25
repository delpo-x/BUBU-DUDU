class_name CoopCamera2D
extends Camera2D
## Single shared camera for couch co-op.
##
## - Tracks the midpoint of every node in the "players" group.
## - Zooms smoothly so the players' bounding box (plus padding) stays in frame.
## - Clamps the *visible rect* (not just the center) to level_bounds.
## - Exposes get_leash_rect() so players stop walking out of the widest view.
## All smoothing is exponential (1 - exp(-rate * dt)), so it feels the same at any frame rate.

const PLAYERS_GROUP := &"players"

@export_group("Bounds")
## World-space rectangle the camera view must stay inside.
@export var level_bounds: Rect2 = Rect2(0, 0, 1920, 1080)
@export var clamp_to_bounds: bool = true

@export_group("Framing")
## World-space margin kept around the players' bounding box, per side.
@export var framing_padding: Vector2 = Vector2(220, 170)
## Vertical offset of the focus point (negative = look slightly above the players).
@export var vertical_bias: float = -40.0
## Most zoomed-out value allowed (smaller = see more).
@export var min_zoom: float = 0.55
## Most zoomed-in value allowed.
@export var max_zoom: float = 1.0

@export_group("Smoothing")
## Higher = snappier position follow.
@export var follow_rate: float = 6.0
## Higher = snappier zoom changes. Kept lower than follow to avoid "breathing".
@export var zoom_rate: float = 2.5

@export_group("Leash")
## Inset from the widest possible view where the soft tether starts blocking players.
@export var leash_margin: float = 48.0

var _zoom_value: float = 1.0


func _init() -> void:
	# Players move in the physics step; follow after them to avoid one-frame lag.
	# Set before entering the tree (physics interpolation requires physics mode).
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	process_physics_priority = 100


func _ready() -> void:
	position_smoothing_enabled = false
	ignore_rotation = true
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	make_current()
	snap_to_targets.call_deferred()


func _physics_process(delta: float) -> void:
	var targets := _get_targets()
	if targets.is_empty():
		return
	var vp := get_viewport_rect().size

	var goal_zoom := _fit_zoom(targets, vp)
	_zoom_value = lerpf(_zoom_value, goal_zoom, 1.0 - exp(-zoom_rate * delta))
	zoom = Vector2.ONE * _zoom_value

	var goal := _clamp_center(_focus_point(targets), _zoom_value, vp)
	global_position = global_position.lerp(goal, 1.0 - exp(-follow_rate * delta))
	# Hard clamp too: a zoom-out must never reveal space outside the level.
	global_position = _clamp_center(global_position, _zoom_value, vp)


## Jumps straight to the ideal framing (level start, respawn, room change).
func snap_to_targets() -> void:
	var targets := _get_targets()
	if targets.is_empty():
		return
	var vp := get_viewport_rect().size
	_zoom_value = _fit_zoom(targets, vp)
	zoom = Vector2.ONE * _zoom_value
	global_position = _clamp_center(_focus_point(targets), _zoom_value, vp)
	reset_physics_interpolation()
	reset_smoothing()


## Widest view the camera can reach from its current center, inset by leash_margin.
## Players outside this rect cannot keep walking outward.
func get_leash_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var half := vp * 0.5 / _effective_min_zoom(vp)
	return Rect2(global_position - half, half * 2.0).grow(-leash_margin)


func _get_targets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group(PLAYERS_GROUP):
		if node is Node2D and (node as Node2D).is_visible_in_tree():
			result.append(node as Node2D)
	return result


func _bounding_box(targets: Array[Node2D]) -> Rect2:
	var box := Rect2(targets[0].global_position, Vector2.ZERO)
	for t in targets:
		box = box.expand(t.global_position)
	return box


func _focus_point(targets: Array[Node2D]) -> Vector2:
	return _bounding_box(targets).get_center() + Vector2(0.0, vertical_bias)


func _fit_zoom(targets: Array[Node2D], vp: Vector2) -> float:
	var needed := _bounding_box(targets).size + framing_padding * 2.0
	var fit := minf(vp.x / maxf(needed.x, 1.0), vp.y / maxf(needed.y, 1.0))
	return clampf(fit, _effective_min_zoom(vp), max_zoom)


## min_zoom, raised if needed so the view is never larger than the level itself.
func _effective_min_zoom(vp: Vector2) -> float:
	var z := min_zoom
	if clamp_to_bounds and level_bounds.has_area():
		z = maxf(z, maxf(vp.x / level_bounds.size.x, vp.y / level_bounds.size.y))
	return minf(z, max_zoom)


## Keeps the visible rect inside level_bounds. If the level is smaller than the
## view on an axis, centers on that axis instead.
func _clamp_center(center: Vector2, z: float, vp: Vector2) -> Vector2:
	if not clamp_to_bounds or not level_bounds.has_area():
		return center
	var half := vp * 0.5 / z
	var lo := level_bounds.position + half
	var hi := level_bounds.end - half
	var out := center
	out.x = clampf(center.x, lo.x, hi.x) if lo.x <= hi.x else level_bounds.get_center().x
	out.y = clampf(center.y, lo.y, hi.y) if lo.y <= hi.y else level_bounds.get_center().y
	return out
