class_name BalancePad
extends AnimatableBody2D
## One pad of a BalancePair. Forwards landings to the pair.

var pair: Node = null
var side: int = 0


func on_landed(body: Node, impact: float) -> void:
	if pair != null:
		pair.call(&"on_pad_landed", side, body, impact)
