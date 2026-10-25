class_name Bubu
extends BasePlayer
## Bubu (panda), Player 1: joypad 0, keyboard WASD.
## Character-specific behaviour goes here; the shared controller lives in BasePlayer.


func _init() -> void:
	player_index = 1
	body_color = Color(0.96, 0.96, 0.94)
	accent_color = Color(0.08, 0.08, 0.1)
	lower_color = Color(0.08, 0.08, 0.1)
	marker_color = Color(1.0, 0.5, 0.55)
