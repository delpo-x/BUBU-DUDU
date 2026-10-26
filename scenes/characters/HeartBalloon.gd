class_name HeartBalloon
extends Node2D
## Visual for the "no game over" return trip: a heart balloon carrying a tiny
## version of the character. Movement is driven by BasePlayer; this only draws.
## With a sticker (art/stickers/<who>_balloon) the character riding its heart is drawn instead.

const STICKER_H := 104.0

var _body: Color = Color.WHITE
var _lower: Color = Color.BLACK
var _heart: Color = Color(1.0, 0.45, 0.5)
var _t: float = 0.0
var _popping: float = -1.0
var _sticker: String = ""


func setup(body: Color, lower: Color, heart: Color, sticker: String = "") -> void:
	_sticker = sticker
	_body = body
	_lower = lower
	_heart = Color(1.0, 0.42, 0.52).lerp(heart, 0.25)
	z_index = 20


func _process(delta: float) -> void:
	_t += delta
	if _popping >= 0.0:
		_popping += delta
		if _popping > 0.25:
			queue_free()
	queue_redraw()


## Bursts and frees itself.
func pop() -> void:
	_popping = 0.0


func _draw() -> void:
	var bob := sin(_t * 5.0) * 4.0
	if _popping >= 0.0:
		var k := _popping / 0.25
		for i in 8:
			var a := TAU * i / 8.0
			draw_circle(Vector2(cos(a), sin(a)) * (10.0 + 40.0 * k) + Vector2(0, -50), 4.0 * (1.0 - k), _heart)
		return
	var tex := Stickers.frame(_sticker, _t) if _sticker != "" else null
	if tex != null:
		draw_texture_rect(tex, Stickers.fit(tex, Vector2(0, -44 + bob), Vector2(STICKER_H, STICKER_H)), false)
		return
	var heart_pos := Vector2(0, -56 + bob)
	draw_line(heart_pos + Vector2(0, 14), Vector2(0, -14), Color(0.3, 0.3, 0.35), 1.5)
	draw_heart(self, heart_pos, 18.0, _heart)
	# Tiny dangling character.
	var sway := sin(_t * 3.0) * 3.0
	draw_rect(Rect2(Vector2(-10 + sway, -14), Vector2(20, 26)), _body)
	draw_rect(Rect2(Vector2(-10 + sway, 4), Vector2(20, 8)), _lower)


## Draws a filled heart centered at `pos` on any CanvasItem.
static func draw_heart(canvas: CanvasItem, pos: Vector2, size: float, color: Color) -> void:
	var r := size * 0.5
	canvas.draw_circle(pos + Vector2(-r * 0.55, -r * 0.2), r * 0.62, color)
	canvas.draw_circle(pos + Vector2(r * 0.55, -r * 0.2), r * 0.62, color)
	canvas.draw_colored_polygon(PackedVector2Array([
		pos + Vector2(-r * 1.12, 0.0), pos + Vector2(r * 1.12, 0.0), pos + Vector2(0.0, r * 1.15)]), color)
