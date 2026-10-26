class_name ControlsPanel
extends PanelContainer
## Remapping: one row per action, a keyboard and a pad cell for Bubu and for Dudu. Pick a
## cell, then press the new key or button (a pad cell listens to that player's pad). Waiting
## ends by itself after a few seconds. Navigable with either pad.

signal closed

const WAIT := 5.0

var _cells: Dictionary = {}     # Button -> [action, "key" | "pad"]
var _first: Control
var _back: Button
var _status: Label
var _waiting: Button = null
var _wait_left: float = 0.0
var _armed: bool = false        # the press that started waiting has been released


func _ready() -> void:
	theme = UiTheme.get_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(1000, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 8)
	add_child(v)
	v.add_child(UiTheme.label("Assegna i tasti", 34, UiTheme.ACCENT_INK, HORIZONTAL_ALIGNMENT_CENTER))
	_status = UiTheme.label("Scegli una casella e premi il nuovo tasto o pulsante.", 18, UiTheme.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_status)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 4)
	v.add_child(grid)
	for title in ["", "Bubu · tastiera", "Bubu · pad", "Dudu · tastiera", "Dudu · pad"]:
		grid.add_child(UiTheme.label(title, 18, UiTheme.ACCENT_INK, HORIZONTAL_ALIGNMENT_CENTER))
	var focusables: Array[Control] = []
	var grid_cells: Array = []    # rows of [col, Button]
	for suffix: String in Bindings.ACTIONS.keys():
		var line: Array = []
		grid_cells.append(line)
		grid.add_child(UiTheme.label(String(Bindings.ACTIONS[suffix]), 18))
		for p in [1, 2]:
			var action := StringName("p%d_%s" % [p, suffix])
			for kind in ["key", "pad"]:
				var b := Button.new()
				b.custom_minimum_size = Vector2(170, 36)
				b.add_theme_font_size_override(&"font_size", 17)
				b.focus_entered.connect(func() -> void: Sfx.play("ui_move", 0.0, -10.0))
				if kind == "pad" and not Bindings.can_rebind_pad(action):
					b.disabled = true
					b.focus_mode = Control.FOCUS_NONE
				else:
					b.pressed.connect(_start_wait.bind(b))
					focusables.append(b)
					line.append([(p - 1) * 2 + (0 if kind == "key" else 1), b])
				_cells[b] = [action, kind]
				grid.add_child(b)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 16)
	v.add_child(row)
	var reset := UiTheme.button("Ripristina predefiniti", func() -> void:
		Bindings.reset_defaults()
		_status.text = "Tasti originali ripristinati.")
	_back = UiTheme.button("Indietro", _close)
	row.add_child(reset)
	row.add_child(_back)
	focusables.append(reset)
	focusables.append(_back)
	UiTheme.chain_focus(focusables)
	_link_grid(grid_cells, reset)
	_first = focusables[0]
	Bindings.changed.connect(_refresh)
	_refresh()


## Up/down keep the column (skipping rows where it can't change), left/right stay in
## the row; the chain from UiTheme.chain_focus already covers the rest.
func _link_grid(rows: Array, below: Control) -> void:
	for r in rows.size():
		for cell: Array in rows[r]:
			var b: Button = cell[1]
			var up := _in_column(rows, r, -1, int(cell[0]))
			var down := _in_column(rows, r, 1, int(cell[0]))
			if up != null:
				b.focus_neighbor_top = b.get_path_to(up)
			b.focus_neighbor_bottom = b.get_path_to(down if down != null else below)
			var line: Array = rows[r]
			var i := line.find(cell)
			if i > 0:
				b.focus_neighbor_left = b.get_path_to(line[i - 1][1])
			if i < line.size() - 1:
				b.focus_neighbor_right = b.get_path_to(line[i + 1][1])


func _in_column(rows: Array, from: int, step: int, col: int) -> Button:
	var r := from + step
	while r >= 0 and r < rows.size():
		for cell: Array in rows[r]:
			if int(cell[0]) == col:
				return cell[1]
		r += step
	return null


func open() -> void:
	visible = true
	_refresh()
	_first.grab_focus()


func _refresh() -> void:
	for b: Button in _cells.keys():
		var a: StringName = _cells[b][0]
		b.text = Bindings.key_label(a) if _cells[b][1] == "key" else Bindings.pad_label(a)


func _start_wait(b: Button) -> void:
	_waiting = b
	_wait_left = WAIT
	_armed = false
	b.text = "…"
	var who := "Bubu" if String(_cells[b][0]).begins_with("p1") else "Dudu"
	_status.text = ("Premi un tasto per %s" if _cells[b][1] == "key" else "Premi un pulsante sul pad di %s") % who


func _process(delta: float) -> void:
	if _waiting == null:
		return
	_wait_left -= delta
	if _wait_left <= 0.0:
		_status.text = "Nessun tasto premuto: non è cambiato niente."
		_stop_wait()


func _input(event: InputEvent) -> void:
	if _waiting == null or not visible:
		return
	get_viewport().set_input_as_handled()
	# Wait for the press that opened the cell to be released first.
	if not _armed:
		if not event.is_pressed():
			_armed = true
		return
	if not event.is_pressed() or event.is_echo():
		return
	var action: StringName = _cells[_waiting][0]
	if _cells[_waiting][1] == "key" and event is InputEventKey:
		var k := event as InputEventKey
		Bindings.set_key(action, k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
		_done(action)
	elif _cells[_waiting][1] == "pad" and event is InputEventJoypadButton:
		var player := 1 if String(action).begins_with("p1") else 2
		if event.device != PadAssigner.device_for_player(player) and Input.get_connected_joypads().size() > 1:
			_status.text = "Usa il pad di %s." % ("Bubu" if player == 1 else "Dudu")
			return
		Bindings.set_pad(action, (event as InputEventJoypadButton).button_index)
		_done(action)


func _done(action: StringName) -> void:
	Sfx.play("ui_accept", 0.0, -4.0)
	_status.text = "Fatto: %s." % String(Bindings.ACTIONS[String(action).substr(3)])
	_stop_wait()


func _stop_wait() -> void:
	var b := _waiting
	_waiting = null
	_refresh()
	if b != null:
		b.grab_focus()


func _close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and _waiting == null and UiTheme.is_back(event):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_back", 0.0, -4.0)
		_close()
