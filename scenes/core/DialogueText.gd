class_name DialogueText
extends RefCounted
## Variations for dialogue lines, so the same conversation reads differently depending on
## how the players got there. Applied to every line before it is shown.
##
## - "if": a condition; the line is skipped when it is false. It is a Godot Expression over
##   the VARS below, plus mem("m1_a") (memory found) and seen("flag") (save flag set):
##   {"s": "dudu", "if": "falls_dudu > falls_bubu", "t": "..."}
## - {a|b|c} in the text: one of them, picked at random.
## - {name} in the text: the value of a VAR, e.g. "Sei caduto {falls_dudu} volte."
##
## A contextual-line entry whose lines are all skipped is skipped as a whole.

## Names usable in conditions and in {name}.
const VARS := [
	"falls", "falls_bubu", "falls_dudu", "calls", "calls_bubu", "calls_dudu", "hugs", "piggy",
	"memories", "memories_total", "chapter", "minutes", "hours", "last_memory", "clumsier",
]

static var _rng := RandomNumberGenerator.new()


## The lines that apply now, with their text filled in. Lines are copied, never changed.
static func resolve(lines: Array) -> Array:
	var ctx := context()
	var helper := DialogueText.new()
	var out: Array = []
	for ln: Variant in lines:
		if not ln is Dictionary:
			continue
		var d := (ln as Dictionary).duplicate()
		var cond := String(d.get("if", ""))
		if cond != "" and not helper.check(cond, ctx):
			continue
		d["t"] = fill(String(d.get("t", "")), ctx)
		d.erase("if")
		out.append(d)
	return out


## Current values of VARS.
static func context() -> Dictionary:
	var fb := int(GameState.get_flag("stat_falls_bubu", 0))
	var fd := int(GameState.get_flag("stat_falls_dudu", 0))
	var cb := int(GameState.get_flag("stat_calls_bubu", 0))
	var cd := int(GameState.get_flag("stat_calls_dudu", 0))
	var total := 0
	for ch in GameState.chapter_count():
		total += GameState.memories_in_chapter(ch).size()
	var last := String(GameState.get_flag("stat_last_memory", ""))
	return {
		"falls": fb + fd, "falls_bubu": fb, "falls_dudu": fd,
		"calls": cb + cd, "calls_bubu": cb, "calls_dudu": cd,
		"hugs": int(GameState.get_flag("stat_hugs", 0)), "piggy": int(GameState.get_flag("stat_piggy", 0)),
		"memories": GameState.memories.size(), "memories_total": total,
		"chapter": GameState.chapter_index + 1,
		"minutes": int(GameState.play_time / 60.0), "hours": int(GameState.play_time / 3600.0),
		"last_memory": String((GameState.memory_defs.get(last, {}) as Dictionary).get("title", "")),
		"clumsier": "Dudu" if fd > fb else "Bubu",
	}


## Replaces {a|b} with one choice and {name} with its value; other braces stay.
static func fill(text: String, ctx: Dictionary) -> String:
	var out := ""
	var i := 0
	while i < text.length():
		var open := text.find("{", i)
		if open < 0:
			out += text.substr(i)
			break
		var close := text.find("}", open)
		if close < 0:
			out += text.substr(i)
			break
		out += text.substr(i, open - i)
		var inner := text.substr(open + 1, close - open - 1)
		if inner.contains("|"):
			var opts := inner.split("|")
			out += opts[_rng.randi_range(0, opts.size() - 1)]
		elif ctx.has(inner):
			out += str(ctx[inner])
		else:
			out += "{" + inner + "}"
		i = close + 1
	return out


## Evaluates a condition; a broken one is reported and counts as false.
func check(cond: String, ctx: Dictionary) -> bool:
	var e := Expression.new()
	if e.parse(cond, PackedStringArray(VARS)) != OK:
		push_warning("DialogueText: bad condition '%s': %s" % [cond, e.get_error_text()])
		return false
	var inputs: Array = []
	for v: String in VARS:
		inputs.append(ctx.get(v, 0))
	var r: Variant = e.execute(inputs, self, false)
	if e.has_execute_failed():
		push_warning("DialogueText: condition failed '%s'" % cond)
		return false
	return bool(r)


func mem(id: String) -> bool:
	return GameState.has_memory(id)


func seen(flag: String) -> bool:
	return bool(GameState.get_flag(flag, false))
