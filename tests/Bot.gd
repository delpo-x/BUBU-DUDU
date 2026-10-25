extends Node
## Test bot: plays a room by pressing the same input actions the gamepads use
## (Input.action_press), so every solution exercises the real controller code.
## Runs before the players each physics frame (priority -100) so "just pressed" works.
##
## A solution is an Array of step dictionaries {"op": ..., ...}; see _tick_* below.
## Positions are world pixels. "top" = a floor surface y the jump must clear before
## steering (prevents bumping into ledge undersides).

signal finished(ok: bool, message: String)

const VERBS: Array[String] = ["left", "right", "up", "down", "jump", "interact", "assist"]
const DEFAULT_TIMEOUT := 12.0
const MIN_HOLD := 3

var players: Array[BasePlayer] = []
var room: Room
var steps: Array = []
var index: int = -1
var running: bool = false
var balloon_events: int = 0
var log_steps: bool = false

var _step: Dictionary = {}
var _t: float = 0.0
var _phase: int = 0
var _want: Dictionary = {}
var _left_floor: Array[bool] = [false, false]
var _dlg_timer: float = 0.0
var _mem: Dictionary = {}
var _held_frames: Dictionary = {}


func _init() -> void:
	process_physics_priority = -100


func setup(p1: BasePlayer, p2: BasePlayer, r: Room) -> void:
	players = [p1, p2]
	room = r
	for p in players:
		if not p.balance_lost.is_connected(_on_balance_lost):
			p.balance_lost.connect(_on_balance_lost)


func _on_balance_lost(_p: BasePlayer) -> void:
	balloon_events += 1


func run(solution: Array) -> void:
	steps = solution
	index = -1
	running = true
	balloon_events = 0
	_next()


func _next() -> void:
	index += 1
	_t = 0.0
	_phase = 0
	_mem = {}
	_left_floor = [false, false]
	if index >= steps.size():
		_finish(true, "all steps done")
		return
	_step = steps[index]
	if log_steps:
		print("  step %d: %s" % [index, _step])


func _finish(ok: bool, msg: String) -> void:
	running = false
	_release_all()
	finished.emit(ok, msg)


func _fail(msg: String) -> void:
	_finish(false, "step %d (%s): %s" % [index, _step.get("op", "?"), msg])


func _release_all() -> void:
	for p in [1, 2]:
		for v in VERBS:
			var a := StringName("p%d_%s" % [p, v])
			if Input.is_action_pressed(a):
				Input.action_release(a)


func _hold(p: int, verb: String) -> void:
	_want[StringName("p%d_%s" % [p, verb])] = true


func _physics_process(delta: float) -> void:
	_want = {}
	if running:
		_auto_advance_dialogue(delta)
		var locked := false
		for p in players:
			if not p.controls_enabled:
				locked = true
		if not locked:
			_t += delta
			var timeout := float(_step.get("timeout", DEFAULT_TIMEOUT))
			if _t > timeout:
				_fail("timeout after %.1fs (p1 %s, p2 %s)" % [timeout, players[0].global_position.round(), players[1].global_position.round()])
			else:
				_tick(delta)
	# A simulated press is seen by the players one frame later, so every press is
	# held for at least MIN_HOLD frames (otherwise press + release land together).
	for p in [1, 2]:
		for v in VERBS:
			var a := StringName("p%d_%s" % [p, v])
			var want := _want.has(a)
			var pressed := Input.is_action_pressed(a)
			if pressed:
				_held_frames[a] = int(_held_frames.get(a, 0)) + 1
			if want and not pressed:
				Input.action_press(a)
				_held_frames[a] = 0
			elif not want and pressed and int(_held_frames.get(a, 0)) >= MIN_HOLD:
				Input.action_release(a)


func _auto_advance_dialogue(delta: float) -> void:
	var svc := get_tree().get_first_node_in_group(&"dialogue_service")
	if svc == null or not svc.has_method(&"is_busy") or not bool(svc.call(&"is_busy")):
		_dlg_timer = 0.0
		return
	_dlg_timer += delta
	if _dlg_timer > 0.25:
		_dlg_timer = 0.0
		svc.call(&"advance")


# --- Helpers ------------------------------------------------------------------------

func _pl(step: Dictionary, key: String = "p") -> BasePlayer:
	return players[int(step.get(key, 1)) - 1]


func _feet(pl: BasePlayer) -> float:
	return pl.global_position.y + pl._body_size.y * 0.5


func _steer(p: int, pl: BasePlayer, x: float, tol: float = 6.0) -> void:
	var dx := x - pl.global_position.x
	if absf(dx) > tol:
		_hold(p, "right" if dx > 0.0 else "left")


## Holds towards x; returns true once the player has settled there.
func _walk(p: int, x: float, tol: float) -> bool:
	var pl := players[p - 1]
	var dx := x - pl.global_position.x
	# Release early: ground friction needs ~12px to stop from full speed.
	if absf(dx) > tol + 10.0:
		_hold(p, "right" if dx > 0.0 else "left")
		return false
	return absf(pl.velocity.x) < 15.0 and (pl.is_on_floor() or pl.is_riding())


func _tick(_delta: float) -> void:
	var op := String(_step.get("op", ""))
	if log_steps and Engine.get_physics_frames() % 3 == 0:
		var q := players[int(_step.get("p", 1)) - 1]
		print("    t=%.2f ph=%d pos=%s vel=%s floor=%s want=%s" % [_t, _phase, q.global_position.round(), q.velocity.round(), q.is_on_floor(), _want.keys()])
	match op:
		"walk":
			var wp := int(_step.get("p", 1))
			if _walk(wp, _x(_step, players[wp - 1]), float(_step.get("tol", 8.0))):
				_next()
		"walk2":
			var a := _walk(1, float(_step["x1"]), float(_step.get("tol", 8.0)))
			var b := _walk(2, float(_step["x2"]), float(_step.get("tol", 8.0)))
			if a and b:
				_next()
		"jump", "dismount", "fly", "bounce":
			_tick_jump(op)
		"jump2":
			_tick_jump2()
		"piggy":
			_tick_tap("assist", func() -> bool: return _pl(_step).is_riding())
		"unpiggy":
			_tick_tap("assist", func() -> bool: return not _pl(_step).is_riding())
		"interact":
			_tick_tap("interact", func() -> bool: return true)
		"pickup":
			_tick_tap("interact", func() -> bool: return _pl(_step).carried_item != null)
		"drop":
			_tick_tap("interact", func() -> bool: return _pl(_step).carried_item == null)
		"face":
			var p := int(_step.get("p", 1))
			var dir := int(_step.get("dir", 1))
			if _pl(_step).facing == dir and _t > 0.05:
				_next()
			else:
				_hold(p, "right" if dir > 0 else "left")
		"hug":
			_tick_hug()
		"call":
			_tick_call()
		"wait":
			if _t >= float(_step.get("s", 1.0)):
				_next()
		"wait_ch":
			if room.is_active(StringName(String(_step["ch"]))) == bool(_step.get("on", true)):
				_next()
		"wait_near":
			var n := room.get_node_or_null(NodePath(String(_step["node"]))) as Node2D
			if n == null:
				_fail("missing node " + String(_step["node"]))
				return
			var target := Vector2(float(_step["x"]), float(_step["y"]))
			var near := n.global_position.distance_to(target) <= float(_step.get("tol", 8.0))
			# arrive: it must first be away, so we catch the start of its pause.
			if bool(_step.get("arrive", false)) and not _mem.has("away"):
				if not near:
					_mem["away"] = true
			elif near:
				_next()
		"climb":
			_tick_climb()
		"walljump":
			_tick_walljump()
		"hold":
			var p2 := int(_step.get("p", 1))
			for v: String in _step.get("verbs", [String(_step.get("verb", ""))]):
				_hold(p2, v)
			if _t >= float(_step.get("s", 0.5)):
				_next()
		"settle":
			# Both on the floor and not moving.
			var ok := true
			for pl in players:
				if pl.is_in_balloon() or (not pl.is_on_floor() and not pl.is_riding()) or absf(pl.velocity.x) > 15.0:
					ok = false
			if ok and _t > 0.1:
				_next()
		"expect":
			_tick_expect()
		"wait_complete":
			if room.is_completed():
				_next()
		_:
			_fail("unknown op")


func _tick_tap(verb: String, done: Callable) -> void:
	var p := int(_step.get("p", 1))
	if _phase == 0:
		_hold(p, verb)
		_phase = 1
	elif _phase == 1:
		_phase = 2
	elif done.call() and _t > float(_step.get("after", 0.1)):
		_next()
	elif _t > 1.5:
		_fail("tap had no effect")


## x from the step, optionally relative to a node: {"x_node": "Things/Crate", "x_dx": -40}.
func _x(step: Dictionary, pl: BasePlayer) -> float:
	if step.has("x_node"):
		var n := room.get_node_or_null(NodePath(String(step["x_node"]))) as Node2D
		if n != null:
			return n.global_position.x + float(step.get("x_dx", 0.0))
	return float(step.get("x", pl.global_position.x))


## jump {p, x, top?, run?, hold?}: press jump, keep it held while rising, steer to x
##   (only once the feet clear `top`, if given), done on landing.
## dismount {p (rider), x, top?}: same, starting from the partner's back.
## fly {p, via?, x, top?}: no press; walk towards `via` until airborne (wind, seesaw).
## bounce {p, via, x, top}: hop towards the pad at `via`, then steer once bounced.
func _tick_jump(op: String) -> void:
	var p := int(_step.get("p", 1))
	var pl := players[p - 1]
	var x := _x(_step, pl)
	var has_top := _step.has("top")
	var top := float(_step.get("top", 0.0))
	if op == "fly" or op == "bounce":
		if _phase == 0:
			if op == "bounce" and pl.is_on_floor() and not _mem.has("hopped"):
				_hold(p, "jump")
				_mem["hopped"] = true
			elif op == "bounce" and (pl.velocity.y < 0.0 or pl.is_on_floor()) and _t < 0.8:
				_hold(p, "jump")
			if _step.has("via"):
				_steer(p, pl, float(_step["via"]), 4.0)
			var up_speed := -900.0 if op == "bounce" else -150.0
			if pl.velocity.y < up_speed:
				_phase = 1
				_left_floor[p - 1] = true
			elif op == "bounce" and pl.is_on_floor() and _t > 0.3 and _mem.has("hopped"):
				_mem.erase("hopped")
			return
		# Airborne: same landing logic as a jump (no jump hold).
		if not has_top or _feet(pl) < top - 2.0:
			_steer(p, pl, x)
		if not pl.is_on_floor() and not pl.is_riding():
			_left_floor[p - 1] = true
		if _left_floor[p - 1] and pl.is_on_floor() and _t > 0.2:
			if has_top and _feet(pl) > top + 6.0:
				_fail("landed below target (feet %.0f > %.0f)" % [_feet(pl), top])
			elif absf(pl.global_position.x - x) > float(_step.get("land_tol", 130.0)):
				_fail("landed at %s, wanted x %.0f" % [pl.global_position.round(), x])
			else:
				_next()
		elif pl.is_in_balloon():
			_fail("fell")
		return
	var is_dismount := op == "dismount"
	match _phase:
		0:
			if is_dismount and not pl.is_riding():
				_fail("not riding")
				return
			if not is_dismount and not pl.is_on_floor():
				if _t > 1.0:
					_fail("not on floor to jump")
				return
			_hold(p, "jump")
			if not has_top or bool(_step.get("run", false)):
				_steer(p, pl, x)
			_phase = 1
		_:
			var airborne := not pl.is_on_floor() and not pl.is_riding()
			if airborne:
				_left_floor[p - 1] = true
			var hold_time := float(_step.get("hold", 10.0))
			if (pl.velocity.y < 0.0 or not _left_floor[p - 1]) and _t < hold_time:
				_hold(p, "jump")
			var clear := not has_top or _feet(pl) < top - 2.0 or bool(_step.get("run", false))
			if clear:
				_steer(p, pl, x)
			if _left_floor[p - 1] and pl.is_on_floor():
				var land_tol := float(_step.get("land_tol", 90.0))
				if absf(pl.global_position.x - x) > land_tol and not bool(_step.get("any", false)):
					_fail("landed at %s, wanted x %.0f" % [pl.global_position.round(), x])
				elif has_top and _feet(pl) > top + 6.0 and not bool(_step.get("any", false)) and not bool(_step.get("nocheck", false)):
					_fail("landed below target (feet %.0f > %.0f)" % [_feet(pl), top])
				else:
					_next()
			elif pl.is_in_balloon():
				_fail("fell while jumping")


## jump2 {x1, x2, top?}: both jump at once (same rules as jump).
func _tick_jump2() -> void:
	var has_top := _step.has("top")
	var top := float(_step.get("top", 0.0))
	var done := 0
	for i in 2:
		var p := i + 1
		var pl := players[i]
		var x := float(_step["x%d" % p])
		if _phase == 0:
			_hold(p, "jump")
			if not has_top:
				_steer(p, pl, x)
			continue
		if not pl.is_on_floor():
			_left_floor[i] = true
		if pl.velocity.y < 0.0 or not _left_floor[i]:
			_hold(p, "jump")
		if not has_top or _feet(pl) < top - 2.0:
			_steer(p, pl, x)
		if _left_floor[i] and pl.is_on_floor():
			done += 1
		if pl.is_in_balloon():
			_fail("fell while jumping")
			return
	if _phase == 0:
		_phase = 1
	elif done == 2:
		_next()


func _tick_hug() -> void:
	if _phase == 0:
		_hold(1, "assist")
		_hold(2, "assist")
		_phase = 1
	elif _phase == 1:
		_phase = 2
	elif _t > 0.3:
		# Hug done once controls are back (the lock pauses this step's clock).
		var spot_done := true
		for s in get_tree().get_nodes_in_group(&"cozy_spots"):
			if s.has_method(&"try_hug") and not bool(s.call(&"is_done")) and s.call(&"_contains", players[0]):
				spot_done = false
		if spot_done:
			_next()
		elif _t > 2.0:
			_fail("hug did not start")


func _tick_call() -> void:
	var p := int(_step.get("p", 1))
	var partner := players[2 - p]
	if _phase == 0:
		_hold(p, "assist")
		if _t > 0.85:
			_phase = 1
	elif partner.is_in_balloon():
		_phase = 2
	elif _phase == 2 and partner.is_on_floor():
		_next()
	elif _phase == 1 and _t > 1.5:
		_fail("call refused")


## climb {p, top (surface y), x (where to step off at the top)}
func _tick_climb() -> void:
	var p := int(_step.get("p", 1))
	var pl := players[p - 1]
	var top := float(_step["top"])
	var x := float(_step.get("x", pl.global_position.x))
	match _phase:
		0:
			_hold(p, "up")
			if pl.state == BasePlayer.State.CLIMBING:
				_phase = 1
			elif _t > 1.0:
				_fail("could not grab vine")
		1:
			if pl.state == BasePlayer.State.CLIMBING:
				_hold(p, "up")
			else:
				_phase = 2
		_:
			_steer(p, pl, x)
			if pl.is_on_floor() and _feet(pl) <= top + 4.0:
				_next()
			elif pl.is_on_floor() and _t > 0.5 and _feet(pl) > top + 4.0:
				_fail("fell off the vine")


## walljump {p, top (surface y to reach), x (landing x), dir (first wall direction)}
## Bounces between grooved walls: hold towards a wall, jump when touching it.
func _tick_walljump() -> void:
	var p := int(_step.get("p", 1))
	var pl := players[p - 1]
	var top := float(_step["top"])
	var x := float(_step["x"])
	if not _mem.has("dir"):
		_mem["dir"] = int(_step.get("dir", 1))
		_mem["cool"] = 0.0
	_mem["cool"] = float(_mem["cool"]) - get_physics_process_delta_time()
	if _phase == 0:
		if pl.is_on_floor():
			_hold(p, "jump")
			_phase = 1
		return
	# Head for the top only on a jump that already moves towards the landing spot.
	if _feet(pl) < top - 4.0 and int(_mem["dir"]) == int(signf(x - pl.global_position.x)):
		_phase = 2
	if _phase == 2:
		_steer(p, pl, x)
		if pl.velocity.y < 0.0:
			_hold(p, "jump")
		if pl.is_on_floor():
			if _feet(pl) <= top + 4.0:
				_next()
			else:
				_fail("dropped before reaching the top")
		return
	var dir := int(_mem["dir"])
	_hold(p, "right" if dir > 0 else "left")
	if pl.velocity.y < 0.0:
		_hold(p, "jump")
	if pl.is_on_wall_only() and pl._touching_walljump_wall() and float(_mem["cool"]) <= 0.0:
		# Fresh press: release this frame is handled by the hold map (jump not wanted).
		_want.erase(StringName("p%d_jump" % p))
		_mem["dir"] = -dir
		_mem["cool"] = 0.1
		_mem["press_next"] = true
	elif _mem.get("press_next", false):
		_hold(p, "jump")
		_mem["press_next"] = false
	if pl.is_on_floor() and _t > 0.4:
		_phase = 0


func _tick_expect() -> void:
	var what := String(_step.get("what", ""))
	var ok := false
	match what:
		"channel":
			ok = room.is_active(StringName(String(_step["ch"]))) == bool(_step.get("on", true))
		"riding":
			ok = _pl(_step).is_riding()
		"carrying":
			ok = _pl(_step).carried_item != null
		"memory":
			ok = GameState.has_memory(String(_step["id"]))
		"above":
			ok = _feet(_pl(_step)) <= float(_step["y"]) + 4.0
		_:
			_fail("unknown expectation")
			return
	if ok:
		_next()
	elif _t > float(_step.get("within", 0.5)):
		_fail("expectation failed: %s" % what)
