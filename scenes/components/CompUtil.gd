class_name CompUtil
extends RefCounted
## Small helpers shared by room components.

const LAYER_WORLD := 1
const LAYER_PLAYERS := 2
const LAYER_PROPS := 4
const LAYER_HAZARDS := 8
const LAYER_TRIGGERS := 16


static func add_rect_shape(parent: Node, size: Vector2, offset: Vector2 = Vector2.ZERO) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	cs.shape = rect
	cs.position = offset
	parent.add_child(cs)
	return cs


## Configures an Area2D as a trigger that sees players and props.
static func setup_trigger(area: Area2D) -> void:
	area.collision_layer = LAYER_TRIGGERS
	area.collision_mask = LAYER_PLAYERS | LAYER_PROPS
	area.monitorable = false
	area.monitoring = true


static func players(tree: SceneTree) -> Array[BasePlayer]:
	var out: Array[BasePlayer] = []
	for n in tree.get_nodes_in_group(&"players"):
		if n is BasePlayer:
			out.append(n as BasePlayer)
	out.sort_custom(func(a: BasePlayer, b: BasePlayer) -> bool: return a.player_index < b.player_index)
	return out


static func body_weight(body: Node) -> int:
	if body.is_in_group(&"weighted") and body.has_method(&"get_weight"):
		return int(body.call(&"get_weight"))
	return 0


## Plays a dialogue through the game's dialogue service and waits for it to end.
## Without a service (test scenes) it returns immediately.
static func play_dialogue(node: Node, id: StringName) -> void:
	if id == &"" or not node.is_inside_tree():
		return
	var svc := node.get_tree().get_first_node_in_group(&"dialogue_service")
	if svc != null and svc.has_method(&"play_dialogue"):
		await svc.call(&"play_dialogue", id)


## True while a dialogue box locks the players: timed world motion holds still meanwhile,
## so reading a line never costs a platform cycle.
static func dialogue_busy(node: Node) -> bool:
	if not node.is_inside_tree():
		return false
	var svc := node.get_tree().get_first_node_in_group(&"dialogue_service")
	return svc != null and svc.has_method(&"is_busy") and bool(svc.call(&"is_busy"))


static func toast(node: Node, text: String) -> void:
	if node.is_inside_tree():
		node.get_tree().call_group(&"toast", &"show_toast", text)


static func source_id(node: Node) -> String:
	return str(node.get_instance_id())
