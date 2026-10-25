class_name Bubu
extends BasePlayer
## Bubu (panda), Player 1: first pad, keyboard WASD.
## Light (weight 1) and agile: the only one who can wall-jump.


func _init() -> void:
	player_index = 1
	display_name = "Bubu"
	weight = 1
	strong = false
	can_wall_jump = true
	body_color = Color(0.96, 0.96, 0.94)
	accent_color = Color(0.08, 0.08, 0.1)
	lower_color = Color(0.08, 0.08, 0.1)
	marker_color = Color(1.0, 0.5, 0.55)
	art_dir = "res://art/characters/bubu"
