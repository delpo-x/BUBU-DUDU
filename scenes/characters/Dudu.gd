class_name Dudu
extends BasePlayer
## Dudu (bear), Player 2: second pad, keyboard arrows.
## Heavy (weight 2) and strong: lifts heavy crates, cracks fragile floors.


func _init() -> void:
	player_index = 2
	display_name = "Dudu"
	weight = 2
	strong = true
	can_wall_jump = false
	body_color = Color(0.55, 0.36, 0.22)
	accent_color = Color(0.3, 0.18, 0.1)
	lower_color = Color(0.45, 0.29, 0.17)
	marker_color = Color(1.0, 0.8, 0.4)
	art_dir = "res://art/characters/dudu"
