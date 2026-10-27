class_name StickerRig
extends Node2D
## The character drawn with its animated stickers (art/stickers/): one sticker per pose,
## picked from the player's state every frame, with squash & stretch, tilt and a "nope" shake.
##
## Poses without a sticker of their own borrow one and move it in code: climbing wiggles
## the jump, carrying and riding hold the idle, the partner call waves when there is a
## wave sticker. The origin is the ground point under the feet.

## who -> pose -> sticker. A missing pose falls back along FALLBACK.
const POSES := {
	"bubu": {"idle": "bubu_shy", "walk": "bubu_run", "jump": "bubu_jump", "wave": "bubu_wave"},
	"dudu": {"idle": "dudu_idle", "walk": "dudu_stroll", "jump": "dudu_jump"},
}
const FALLBACK := {"fall": "jump", "climb": "jump", "wave": "idle", "carry": "idle", "ride": "idle", "jump": "idle", "walk": "idle"}
## Poses shown as one still frame of a sticker: sticker -> pose -> frame (the jump stickers
## are a whole trampoline somersault; going up and coming down each hold one pose of it).
const STILLS := {
	"bubu_jump": {"jump": 0, "fall": 2, "climb": 0},
	"dudu_jump": {"jump": 0, "fall": 2, "climb": 0},
}
## Which way each sticker looks when drawn as is (1 right, -1 left, 0 front: never flipped).
const LOOKS := {"bubu_run": 1, "dudu_walk": 1}
## Sticker height on screen for a 60 px tall body (stickers include some margin and shadow).
const HEIGHT := 78.0
## Stickers whose character fills only part of the frame: [scale, share of the frame left
## empty below the feet]. The jumps leave room for the trampoline under them.
const FIT := {"bubu_jump": [1.5, 0.33], "dudu_jump": [1.5, 0.33]}

var _sprite: AnimatedSprite2D
var _who: String = ""
var _pose: String = ""
var _t: float = 0.0
var _tilt: float = 0.0


## Uses the stickers of `who` ("bubu" / "dudu"). False if its idle and walk are missing.
func setup(who: String) -> bool:
	if not POSES.has(who) or Stickers.frames(_sticker_for(who, "idle")) == null or Stickers.frames(_sticker_for(who, "walk")) == null:
		return false
	_who = who
	_sprite = AnimatedSprite2D.new()
	_sprite.centered = false
	add_child(_sprite)
	_set_pose("idle")
	return true


func _sticker_for(who: String, pose: String) -> String:
	var p := pose
	var poses: Dictionary = POSES.get(who, {})
	while not poses.has(p) and FALLBACK.has(p):
		p = FALLBACK[p]
	return String(poses.get(p, ""))


func _set_pose(pose: String) -> void:
	if pose == _pose:
		return
	_pose = pose
	var sf := Stickers.frames(_sticker_for(_who, pose))
	if sf == null:
		return
	_sprite.sprite_frames = sf
	_sprite.frame = 0
	var stills: Dictionary = STILLS.get(_sticker_for(_who, pose), {})
	if stills.has(pose):
		_sprite.stop()
		_sprite.frame = int(stills[pose])
	elif UiTheme.motion() > 0.0:
		_sprite.play(&"default")
	else:
		_sprite.stop()


func animate(pl: BasePlayer, delta: float) -> void:
	_t += delta
	var vx := pl.velocity.x
	var vy := pl.velocity.y
	var pose := "idle"
	var tilt := 0.0
	var bob := 0.0
	var speed := 1.0
	match pl.state:
		BasePlayer.State.RIDING:
			pose = "ride"
			bob = sin(_t * 4.0) * 1.0
		BasePlayer.State.CLIMBING:
			pose = "climb"
			tilt = sin(_t * 9.0) * 0.08 * clampf(absf(vy) / 60.0, 0.0, 1.0)
			speed = 0.0
		_:
			if not pl.is_on_floor():
				pose = "jump" if vy < 0.0 else "fall"
			elif absf(vx) > 20.0:
				pose = "walk"
				speed = clampf(absf(vx) / 160.0, 0.6, 1.6)
				tilt = 0.05 * signf(vx)
	if pl.carried_item != null:
		pose = "carry" if pl.is_on_floor() else pose
	if pl._assist_down and pl._assist_held_time > pl.assist_tap_max_time:
		pose = "wave"
	_set_pose(pose)
	_sprite.speed_scale = speed

	var k := 1.0 - exp(-14.0 * delta)
	_tilt = lerpf(_tilt, tilt, k)
	var m := lerpf(0.35, 1.0, UiTheme.motion())
	var shake := sin(pl._shake_time * 60.0) * 4.0 * (pl._shake_time / 0.3) * m
	position = Vector2(shake, pl._body_size.y * 0.5 + bob * m)
	rotation = _tilt * m

	var tex := _sprite.sprite_frames.get_frame_texture(&"default", _sprite.frame) if _sprite.sprite_frames != null else null
	if tex == null:
		return
	var size := tex.get_size()
	var sticker := _sticker_for(_who, pose)
	var fit: Array = FIT.get(sticker, [1.0, 0.0])
	var h := HEIGHT * pl._body_size.y / 60.0 * float(fit[0])
	var s := h / size.y
	var looks := int(LOOKS.get(sticker, 0))
	var flip := looks != 0 and looks != pl.facing
	var fx := Vector2.ONE.lerp(pl._fx_scale, m)
	scale = Vector2(fx.x * (-1.0 if flip else 1.0), fx.y) * s
	_sprite.position = Vector2(-size.x * 0.5, -size.y * (1.0 - float(fit[1])))
