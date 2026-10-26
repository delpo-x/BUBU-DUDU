extends SceneTree
## Headless test entry point. Autoloads (Sfx, GameState) only exist once the tree is
## running, so this file stays dependency-free and loads the real test at runtime.
##   godot --headless --path . --import
##   godot --headless --path . --script res://tests/run.gd -- smoke
## The argument after "--" names tests/test_<name>.gd (default: all listed in ALL).
## Exit code 0 = every check passed.

const ALL: Array[String] = ["smoke", "components", "flow", "rooms", "chaos"]

## Shared with tests (root meta "error_logger"): any unexpected engine error fails the run.
var logger: Logger = null


func _initialize() -> void:
	var names: Array[String] = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("-") and ResourceLoader.exists("res://tests/test_%s.gd" % a):
			names.append(a)
	if names.is_empty():
		names = ALL.duplicate()
	_run_all(names)


func _run_all(names: Array[String]) -> void:
	logger = (load("res://tests/ErrorLogger.gd") as GDScript).new()
	OS.add_logger(logger)
	root.set_meta(&"error_logger", logger)
	await process_frame
	var total_failed := 0
	var total_passed := 0
	for n in names:
		var path := "res://tests/test_%s.gd" % n
		if not ResourceLoader.exists(path):
			print("[SKIP] missing %s" % path)
			continue
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			print("[FAIL] %s does not compile" % path)
			total_failed += 1
			continue
		var node: Node = script.new()
		node.name = "Test_" + n
		root.add_child(node)
		await node.run()
		total_passed += int(node.get(&"passed"))
		total_failed += int(node.get(&"failed"))
		var errs: Array[String] = logger.call(&"take_errors")
		if errs.is_empty():
			total_passed += 1
			print("[OK] %s: no engine errors" % n)
		else:
			total_failed += 1
			print("[FAIL] %s: %d engine errors" % [n, errs.size()])
			for e in errs.slice(0, 8):
				print("   " + e)
		node.queue_free()
		await process_frame
	print("Results: %d passed, %d failed" % [total_passed, total_failed])
	for audio: NodePath in [^"Sfx", ^"Voices"]:
		var n := root.get_node_or_null(audio)
		if n != null:
			n.call(&"stop_all")
	# Give the audio thread time to drop the stopped playbacks before the engine shuts down
	# (quitting with live playbacks could crash at exit).
	await create_timer(0.25, true, false, true).timeout
	OS.remove_logger(logger)
	quit(1 if total_failed > 0 else 0)
