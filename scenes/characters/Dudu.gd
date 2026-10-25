class_name Dudu
extends BasePlayer
## Dudu (bear), Player 2: joypad 1, keyboard arrows.
## Character-specific behaviour goes here; the shared controller lives in BasePlayer.


func _init() -> void:
	player_index = 2
	body_color = Color(0.55, 0.36, 0.22)
	accent_color = Color(0.3, 0.18, 0.1)
	lower_color = Color(0.45, 0.29, 0.17)
	marker_color = Color(1.0, 0.8, 0.4)
