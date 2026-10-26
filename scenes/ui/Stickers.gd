class_name Stickers
extends RefCounted
## Frame-by-frame sticker animations from art/stickers/ (made by tools/gen_stickers.py).
## Drawn by hand with `frame()` so menus and the dialogue box can paint them like any
## other texture. "Riduci movimento" holds the first frame.

const DIR := "res://art/stickers/%s.tres"

static var _cache: Dictionary = {}


static func frames(sticker: String) -> SpriteFrames:
	if not _cache.has(sticker):
		var path := DIR % sticker
		_cache[sticker] = load(path) as SpriteFrames if ResourceLoader.exists(path) else null
	return _cache[sticker]


## Texture of `sticker` at `time` seconds, looping; null if the sticker is missing.
static func frame(sticker: String, time: float) -> Texture2D:
	var sf := frames(sticker)
	if sf == null:
		return null
	var n := sf.get_frame_count(&"default")
	if n == 0:
		return null
	var i := 0
	if UiTheme.motion() > 0.0:
		i = int(time * sf.get_animation_speed(&"default")) % n
	return sf.get_frame_texture(&"default", i)


## Rect of size `box` centred on `center` that keeps the texture's aspect ratio.
static func fit(tex: Texture2D, center: Vector2, box: Vector2) -> Rect2:
	var s := tex.get_size()
	var k := minf(box.x / s.x, box.y / s.y)
	return Rect2(center - s * k * 0.5, s * k)


## A sticker playing once above a world position, then fading out (hugs, snacks...).
static func pop(parent: Node, sticker: String, at: Vector2, height: float = 140.0, seconds: float = 2.6) -> void:
	var sf := frames(sticker)
	if sf == null or parent == null or not parent.is_inside_tree():
		return
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = sf
	var tex := sf.get_frame_texture(&"default", 0)
	spr.scale = Vector2.ONE * height / tex.get_size().y
	spr.z_index = 50
	spr.modulate.a = 0.0
	parent.add_child(spr)
	spr.global_position = at - Vector2(0, height * 0.5)
	if UiTheme.motion() > 0.0:
		spr.play(&"default")
	var tw := spr.create_tween()
	tw.tween_property(spr, "modulate:a", 1.0, 0.25)
	tw.tween_interval(maxf(seconds - 0.6, 0.0))
	tw.tween_property(spr, "modulate:a", 0.0, 0.35)
	tw.tween_callback(spr.queue_free)
