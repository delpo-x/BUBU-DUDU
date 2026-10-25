extends Logger
## Counts engine and script errors during the test run so the suite fails on any of them
## (an error printed to the console is a bug even if every check passed).
## Tests that provoke an error on purpose call expect_errors(n) first.

var _mutex := Mutex.new()
var errors: Array[String] = []
var expected: int = 0


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	_mutex.lock()
	if expected > 0:
		expected -= 1
	else:
		errors.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function])
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


func expect_errors(n: int) -> void:
	_mutex.lock()
	expected += n
	_mutex.unlock()


func take_errors() -> Array[String]:
	_mutex.lock()
	var out := errors.duplicate()
	errors.clear()
	_mutex.unlock()
	return out
