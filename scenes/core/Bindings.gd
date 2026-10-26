extends Node
## Autoload "Bindings": remappable controls for both players, saved in user://controls.cfg.
##
## Each action keeps one keyboard key (physical, so it sits in the same place on any layout)
## and, for the buttons, one gamepad button. Moving on a pad always uses the left stick and
## the D-pad. Assigning a key or button that another action already uses swaps the two, so
## nothing is ever left unbound. Pads stay assigned per player by PadAssigner.

signal changed

## Overridable so tests never touch the real file.
var path: String = "user://controls.cfg"
## Actions shown in the controls menu, in order: suffix -> label.
const ACTIONS := {
	"left": "Sinistra", "right": "Destra", "up": "Su", "down": "Giù",
	"jump": "Salto", "interact": "Interagisci", "assist": "Groppa / chiama / abbraccio",
	"pause": "Pausa",
}
## Actions whose gamepad button can be changed (movement is the stick and the D-pad).
const PAD_ACTIONS := ["jump", "interact", "assist", "pause"]
const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Select", JOY_BUTTON_GUIDE: "Home", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "Croce su", JOY_BUTTON_DPAD_DOWN: "Croce giù",
	JOY_BUTTON_DPAD_LEFT: "Croce sinistra", JOY_BUTTON_DPAD_RIGHT: "Croce destra",
}
## Key names the font and the players read better in Italian.
const KEY_NAMES := {
	KEY_SPACE: "Spazio", KEY_ENTER: "Invio", KEY_KP_ENTER: "Invio (tastierino)",
	KEY_ESCAPE: "Esc", KEY_BACKSPACE: "Backspace", KEY_TAB: "Tab", KEY_SHIFT: "Maiusc",
	KEY_CTRL: "Ctrl", KEY_ALT: "Alt", KEY_LEFT: "Freccia sinistra", KEY_RIGHT: "Freccia destra",
	KEY_UP: "Freccia su", KEY_DOWN: "Freccia giù", KEY_PERIOD: "Punto", KEY_COMMA: "Virgola",
	KEY_SLASH: "/", KEY_MINUS: "Meno",
}

## action -> Array[InputEvent] as the project defines them (for "reset").
var _defaults: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in all_actions():
		_defaults[a] = InputMap.action_get_events(a).map(func(e: InputEvent) -> InputEvent: return e.duplicate())
	load_bindings()


func all_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for p in [1, 2]:
		for suffix: String in ACTIONS.keys():
			out.append(StringName("p%d_%s" % [p, suffix]))
	return out


# --- Reading --------------------------------------------------------------------------

func key_of(action: StringName) -> InputEventKey:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return e
	return null


func pad_of(action: StringName) -> InputEventJoypadButton:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and _is_pad_button_action(action):
			return e
	return null


func key_label(action: StringName) -> String:
	var k := key_of(action)
	if k == null:
		return "—"
	var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	if KEY_NAMES.has(code):
		return KEY_NAMES[code]
	# The key's name on this keyboard layout (QWERTZ, AZERTY...), where the display server knows it.
	var local := code
	if k.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
		local = DisplayServer.keyboard_get_keycode_from_physical(code)
	return OS.get_keycode_string(local)


func pad_label(action: StringName) -> String:
	if not _is_pad_button_action(action):
		return "Levetta / croce"
	var b := pad_of(action)
	return "—" if b == null else String(PAD_NAMES.get(b.button_index, "Pulsante %d" % b.button_index))


func can_rebind_pad(action: StringName) -> bool:
	return _is_pad_button_action(action)


func _is_pad_button_action(action: StringName) -> bool:
	return String(action).substr(3) in PAD_ACTIONS


# --- Changing -------------------------------------------------------------------------

## Gives `action` this key; the action that had it (either player) gets the old one.
func set_key(action: StringName, physical: Key) -> void:
	var old := key_of(action)
	for other in all_actions():
		var k := key_of(other)
		if other != action and k != null and _code(k) == physical:
			_replace_key(other, _code(old) if old != null else KEY_NONE)
	_replace_key(action, physical)
	_after_change()


## Gives `action` this pad button; the same player's action that had it gets the old one.
func set_pad(action: StringName, button: JoyButton) -> void:
	if not _is_pad_button_action(action):
		return
	var prefix := String(action).substr(0, 3)
	var old := pad_of(action)
	for other in all_actions():
		var b := pad_of(other)
		if other != action and String(other).begins_with(prefix) and b != null and b.button_index == button:
			_replace_pad(other, old.button_index if old != null else JOY_BUTTON_INVALID)
	_replace_pad(action, button)
	_after_change()


func reset_defaults() -> void:
	for a: StringName in _defaults.keys():
		InputMap.action_erase_events(a)
		for e: InputEvent in _defaults[a]:
			InputMap.action_add_event(a, e.duplicate())
	_after_change()


func _code(k: InputEventKey) -> Key:
	return k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode


func _replace_key(action: StringName, physical: Key) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	if physical != KEY_NONE:
		var k := InputEventKey.new()
		k.physical_keycode = physical
		InputMap.action_add_event(action, k)


func _replace_pad(action: StringName, button: JoyButton) -> void:
	var device := 0
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			device = e.device
			InputMap.action_erase_event(action, e)
	if button != JOY_BUTTON_INVALID:
		var b := InputEventJoypadButton.new()
		b.button_index = button
		b.device = device
		InputMap.action_add_event(action, b)


func _after_change() -> void:
	save_bindings()
	PadAssigner.reassign()
	changed.emit()


# --- Saving ---------------------------------------------------------------------------

func save_bindings() -> void:
	var cfg := ConfigFile.new()
	for a in all_actions():
		var k := key_of(a)
		cfg.set_value("keys", String(a), int(_code(k)) if k != null else 0)
		if _is_pad_button_action(a):
			var b := pad_of(a)
			cfg.set_value("pad", String(a), b.button_index if b != null else -1)
	cfg.save(path)


func load_bindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for a in all_actions():
		if cfg.has_section_key("keys", String(a)):
			var k: Variant = cfg.get_value("keys", String(a))
			if (k is int or k is float) and int(k) > 0:
				_replace_key(a, int(k) as Key)
		if _is_pad_button_action(a) and cfg.has_section_key("pad", String(a)):
			var b: Variant = cfg.get_value("pad", String(a))
			if (b is int or b is float) and int(b) >= 0 and int(b) < JOY_BUTTON_MAX:
				_replace_pad(a, int(b) as JoyButton)
	# A damaged file (a key used twice, an action left without one) would make the game
	# unplayable: go back to the default controls instead.
	if not _is_complete():
		push_warning("Bindings: damaged controls file, default controls restored")
		reset_defaults()
		return
	PadAssigner.reassign()
	changed.emit()


## Every action has a key no other action uses; each player's buttons are all different.
func _is_complete() -> bool:
	var keys := {}
	var pads := {}
	for a in all_actions():
		var k := key_of(a)
		if k == null or keys.has(_code(k)):
			return false
		keys[_code(k)] = true
		if _is_pad_button_action(a):
			var b := pad_of(a)
			if b == null:
				return false
			var id := "%s%d" % [String(a).substr(0, 3), b.button_index]
			if pads.has(id):
				return false
			pads[id] = true
	return true
