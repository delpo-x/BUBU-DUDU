extends Node2D
## Whitebox test gym: places both players on their spawn points and offers a debug reset.

@onready var _bubu: BasePlayer = $Players/Bubu
@onready var _dudu: BasePlayer = $Players/Dudu
@onready var _spawn_p1: Marker2D = $SpawnPoints/SpawnP1
@onready var _spawn_p2: Marker2D = $SpawnPoints/SpawnP2
@onready var _camera: CoopCamera2D = $CoopCamera2D


func _ready() -> void:
	respawn_all()


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"debug_reset"):
		respawn_all()


func respawn_all() -> void:
	_bubu.teleport_to(_spawn_p1.global_position)
	_dudu.teleport_to(_spawn_p2.global_position)
	_camera.snap_to_targets()
