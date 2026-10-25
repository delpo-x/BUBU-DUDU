class_name DialogueTrigger
extends Area2D
## Plays a dialogue when a player (or both, with require_both) walks in.
## Plays once per save by default (flag "dlg_<room>_<id>"). Origin = center.

@export var size: Vector2 = Vector2(96, 256)
@export var dialogue: StringName = &""
@export var require_both: bool = false
@export var once: bool = true
## Optional: only fires while this channel is active (e.g. after a door opened).
@export var channel: StringName = &""

var _room: Room
var _fired: bool = false


func _ready() -> void:
	CompUtil.setup_trigger(self)
	collision_mask = CompUtil.LAYER_PLAYERS
	CompUtil.add_rect_shape(self, size)
	_room = Room.find_for(self)
	if once and bool(GameState.get_flag(_flag_key())):
		_fired = true


func _flag_key() -> String:
	var rid := String(_room.room_id) if _room != null else ""
	return "dlg_%s_%s" % [rid, dialogue]


func _contains(p: BasePlayer) -> bool:
	if p.state == BasePlayer.State.BALLOON:
		return false
	return overlaps_body(p) or (p.carrier != null and overlaps_body(p.carrier))


func _physics_process(_delta: float) -> void:
	if _fired or dialogue == &"":
		return
	if channel != &"" and (_room == null or not _room.is_active(channel)):
		return
	var players := CompUtil.players(get_tree())
	var inside := 0
	for p in players:
		if _contains(p):
			inside += 1
	if inside == 0 or (require_both and inside < players.size()):
		return
	_fired = true
	if once:
		GameState.set_flag(_flag_key())
	CompUtil.play_dialogue(self, dialogue)
