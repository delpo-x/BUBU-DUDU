extends Node
## Base for headless tests: check() counts results; run() is overridden and awaited.

var passed := 0
var failed := 0
## When true only failures are printed (big suites stay readable).
var quiet := false


func check(ok: bool, label: String) -> bool:
	if ok:
		passed += 1
		if not quiet:
			print("[OK] " + label)
	else:
		failed += 1
		print("[FAIL] " + label)
	return ok


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func run() -> void:
	pass
