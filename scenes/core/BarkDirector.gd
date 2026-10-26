class_name BarkDirector
extends Node
## Contextual character lines ("barks"): short exchanges picked from pools in
## data/dialogue/barks.json when something happens in play (a fall, a call, a piggyback,
## a memory, a door opening, a long time in one room, nobody touching the pad...).
##
## They play in the normal dialogue box, which locks both players, so a request only
## plays at a calm moment: nobody airborne, climbing, in a balloon, on a moving platform
## or in wind, and no timed button running. Requests that find no calm moment within
## `calm_window` seconds of play are dropped. A global cooldown and a per-room cap keep
## them rare, and each pool cycles through all its entries before repeating (saved).

## Minimum seconds between the end of any dialogue and the next line.
@export var cooldown: float = 75.0
## Minimum quiet seconds after any dialogue (story, sign, cozy spot) before a line.
@export var after_dialogue: float = 6.0
## Lines per room (the "taking long" lines don't count).
@export var room_cap: int = 3
## Seconds of play a request waits for a calm moment.
@export var calm_window: float = 8.0
@export var slow_minutes: float = 6.0
@export var stuck_minutes: float = 11.0
@export var idle_seconds: float = 60.0
@export var fast_room_seconds: float = 90.0
## Seconds the moment must stay calm before a line starts (a jump that just began still
## reads as "on the floor" for a frame).
@export var calm_hold: float = 0.5

## Event -> [pool prefix, chance]. "_bubu"/"_dudu" pools are keyed by who did it.
const CHANCES := {
	"fall": 0.35, "call": 0.4, "piggy": 0.2, "memory": 0.5, "progress": 0.25,
	"ambient": 0.2, "fast": 0.5, "resume": 1.0, "falls_many": 1.0,
	"slow": 1.0, "stuck": 1.0, "idle": 1.0,
}
## Pool -> speaker -> sticker mood for their lines in it (see DialogueBox "m"), unless a
## line has its own.
const MOODS := {
	"falls_many": {"bubu": "cry", "dudu": "sus"},
	"call_bubu": {"bubu": "phone"},
	"call_dudu": {"bubu": "hey"},
	"resume": {"bubu": "bed"},
	"slow": {"bubu": "think", "dudu": "sus"},
	"stuck": {"bubu": "worried"},
	"fast": {"dudu": "handsome"},
}
## Pools that wait for calm for as long as the room lasts and ignore the room cap.
const PERSISTENT := ["slow", "stuck", "idle"]
const VERBS: Array[String] = ["left", "right", "up", "down", "jump", "interact", "assist"]

var game: Game
var rng := RandomNumberGenerator.new()

var _quiet: float = 1e6          # seconds since the last bark ended
var _since_dialogue: float = 1e6 # seconds since any dialogue ended
var _idle: float = 0.0
var _room_lines: int = 0
var _room_falls: int = 0
var _once: Dictionary = {}       # per-room one-shot events
var _channels_on: Dictionary = {}
var _pending: Dictionary = {}    # {pool, left, persistent}
var _entered_rooms: int = 0
var _fast_next: bool = false
var _actions: Array[StringName] = []
var _calm_time: float = 0.0


func setup(owner_game: Game) -> void:
	game = owner_game
	for p in 2:
		for verb in VERBS:
			_actions.append(StringName("p%d_%s" % [p + 1, verb]))
	for pl: BasePlayer in [game.bubu, game.dudu]:
		pl.balance_lost.connect(_on_fall)
		pl.called_partner.connect(_on_call)
		pl.piggyback_started.connect(_on_piggy)
	GameState.memory_collected.connect(_on_memory)
	game.room_entered.connect(_on_room_entered)


# --- Events ---------------------------------------------------------------------------

func _on_room_entered(_ch: int, _idx: int) -> void:
	var room := game.room
	# Tests get the same lines on every run; players get variety.
	if game.fast_transitions:
		rng.seed = hash(String(room.room_id))
	else:
		rng.randomize()
	_room_lines = 0
	_room_falls = 0
	_once = {}
	_channels_on = {}
	_pending = {}
	_idle = 0.0
	_entered_rooms += 1
	room.channel_changed.connect(_on_channel)
	room.completed.connect(_on_room_completed, CONNECT_ONE_SHOT)
	var has_intro := room.intro_dialogue != &"" and not bool(GameState.get_flag("room_intro_%s" % room.room_id))
	if _entered_rooms == 1 and GameState.play_time > 60.0 and not has_intro:
		request("resume")
	elif _fast_next and not has_intro:
		request("fast")
	elif room.intro_dialogue == &"":
		request("ambient_c%d" % (game.chapter_index + 1), CHANCES["ambient"])
	_fast_next = false


func _on_room_completed() -> void:
	_fast_next = game.room_time < fast_room_seconds


func _on_fall(pl: BasePlayer) -> void:
	_room_falls += 1
	if _room_falls >= 4 and not _once.has("falls_many"):
		_once["falls_many"] = true
		request("falls_many")
	else:
		request("fall_" + _who(pl))


func _on_call(pl: BasePlayer) -> void:
	request("call_" + _who(pl))


func _on_piggy(_rider: BasePlayer, _carrier: BasePlayer) -> void:
	request("piggy")


func _on_memory(_id: String) -> void:
	if game != null and game.room != null:
		request("memory")


func _on_channel(channel: StringName, active: bool) -> void:
	if active and not _channels_on.has(channel):
		_channels_on[channel] = true
		request("progress")


func _who(pl: BasePlayer) -> String:
	return "bubu" if pl == game.bubu else "dudu"


# --- Requests -------------------------------------------------------------------------

## Asks for a line from `pool`. `chance` overrides the event's default probability.
func request(pool: String, chance: float = -1.0) -> void:
	if not GameState.barks_enabled or not has_pool(pool):
		return
	var event := _event_of(pool)
	if chance < 0.0:
		chance = float(CHANCES.get(event, 0.3))
	var persistent := PERSISTENT.has(event)
	# Right after a story dialogue (cozy spot, sign, intro) the moment belongs to it.
	if not persistent and (_since_dialogue < after_dialogue or game.dialogue.is_busy()) and event not in ["resume", "fast", "ambient"]:
		return
	if rng.randf() >= chance:
		return
	# Keep the more important request when one is already waiting.
	if not _pending.is_empty() and bool(_pending["persistent"]) and not persistent:
		return
	_pending = {"pool": pool, "left": calm_window, "persistent": persistent}


func has_pool(pool: String) -> bool:
	var entries: Variant = GameState.barks.get(pool, null)
	return entries is Array and not (entries as Array).is_empty()


func _event_of(pool: String) -> String:
	for e: String in CHANCES.keys():
		if pool == e or pool.begins_with(e + "_"):
			return e
	return pool


func is_pending() -> bool:
	return not _pending.is_empty()


# --- Loop -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if game == null or game.room == null:
		return
	var blocked := game.is_transitioning() or game.dialogue.is_busy()
	if game.dialogue.is_busy():
		_since_dialogue = 0.0
	else:
		_since_dialogue += delta
		_quiet += delta
	if blocked:
		_calm_time = 0.0
		return
	_calm_time = _calm_time + delta if is_calm() else 0.0
	_track_time_and_idle(delta)
	if _pending.is_empty():
		return
	var persistent := bool(_pending["persistent"])
	if not persistent:
		_pending["left"] = float(_pending["left"]) - delta
		if float(_pending["left"]) <= 0.0:
			_pending = {}
			return
	if _quiet < (cooldown * 0.3 if persistent else cooldown) or _since_dialogue < after_dialogue:
		return
	if not persistent and _room_lines >= room_cap:
		_pending = {}
		return
	if _calm_time < calm_hold:
		return
	var pool := String(_pending["pool"])
	_pending = {}
	_play(pool)


func _track_time_and_idle(delta: float) -> void:
	var t := game.room_time
	if t > stuck_minutes * 60.0 and not _once.has("stuck"):
		_once["stuck"] = true
		request("stuck")
	elif t > slow_minutes * 60.0 and not _once.has("slow"):
		_once["slow"] = true
		request("slow")
	var any := false
	for a in _actions:
		if Input.is_action_pressed(a):
			any = true
			break
	_idle = 0.0 if any else _idle + delta
	if _idle > idle_seconds and not _once.has("idle"):
		_once["idle"] = true
		request("idle")


## True when locking the controls for a moment can't cost anyone a jump or a timer.
func is_calm() -> bool:
	for pl: BasePlayer in [game.bubu, game.dudu]:
		if pl.state != BasePlayer.State.NORMAL or not pl.is_on_floor():
			return false
		if pl.rider != null or pl.is_riding() or pl.velocity.y < -1.0:
			return false
		if pl.get_platform_velocity().length() > 1.0 or not pl._wind_zones.is_empty():
			return false
	for n in get_tree().get_nodes_in_group(Room.ROOMS_GROUP):
		for b in (n as Node).find_children("*", "WallButton", true, false):
			if (b as WallButton).mode == WallButton.Mode.BUTTON and (b as WallButton).is_active():
				return false
	return true


func _play(pool: String) -> void:
	var lines := pick(pool)
	if lines.is_empty():
		return
	if MOODS.has(pool):
		lines = lines.map(func(ln: Variant) -> Variant:
			var moods: Dictionary = MOODS[pool]
			if ln is Dictionary and moods.has(ln.get("s")) and not (ln as Dictionary).has("m"):
				return (ln as Dictionary).merged({"m": moods[ln.get("s")]})
			return ln)
	if not PERSISTENT.has(_event_of(pool)):
		_room_lines += 1
	_quiet = 0.0
	await game.dialogue.play_lines(lines, StringName("bark_" + pool))
	_quiet = 0.0


## Next entry of a pool: a fixed shuffled order per pool, position saved in the profile,
## so nothing repeats until the whole pool has been heard.
func pick(pool: String) -> Array:
	var entries: Array = GameState.barks.get(pool, [])
	if entries.is_empty():
		return []
	var order: Array[int] = []
	for i in entries.size():
		order.append(i)
	var shuffle := RandomNumberGenerator.new()
	shuffle.seed = hash(pool)
	for i in range(order.size() - 1, 0, -1):
		var j := shuffle.randi_range(0, i)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp
	var key := "bark_" + pool
	var pos := int(GameState.get_flag(key, 0))
	GameState.set_flag(key, pos + 1)
	var entry: Variant = entries[order[pos % order.size()]]
	return entry if entry is Array else []
