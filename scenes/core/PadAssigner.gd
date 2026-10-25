extends Node
## Autoload. Assigns gamepads to players automatically.
##
## The Input Map binds p1_* joypad events to device 0 and p2_* to device 1. Device ids
## are not always 0 and 1 (reconnects, virtual pads), so on every connect/disconnect this
## rewrites them: the lowest connected pad drives P1, the next one drives P2.
## Keyboard events (device -1) are never touched.

const PLAYER_COUNT := 2

signal assignments_changed(devices: Array[int])


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	reassign()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	reassign()


## Returns the joypad device id used by player 1..PLAYER_COUNT.
func device_for_player(player_index: int) -> int:
	var pads := _sorted_pads()
	var slot := player_index - 1
	return pads[slot] if slot < pads.size() else slot


func reassign() -> void:
	var devices: Array[int] = []
	for i in PLAYER_COUNT:
		var device := device_for_player(i + 1)
		devices.append(device)
		_set_joypad_device("p%d_" % (i + 1), device)
	assignments_changed.emit(devices)


func _sorted_pads() -> Array[int]:
	var pads: Array[int] = Input.get_connected_joypads()
	pads.sort()
	return pads


func _set_joypad_device(prefix: String, device: int) -> void:
	for action in InputMap.get_actions():
		if not String(action).begins_with(prefix):
			continue
		for event in InputMap.action_get_events(action):
			if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and event.device != device:
				var moved := event.duplicate() as InputEvent
				moved.device = device
				InputMap.action_erase_event(action, event)
				InputMap.action_add_event(action, moved)
