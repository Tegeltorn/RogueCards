extends SceneTree
## Runs every tests/test_*.gd (except test_base.gd). Exit code 1 on any failure.
##   godot --headless --script res://tests/run_tests.gd


func _init() -> void:
	var total := 0
	var failed: Array = []
	var dir := DirAccess.open("res://tests")
	var files: Array = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_base.gd":
			files.append(f)
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/" + f)
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var inst = script.new()
			inst.current_test = f.get_basename() + "." + name
			inst.call(name)
			total += 1
			if inst.failures.is_empty():
				print("  ok   ", inst.current_test)
			else:
				for msg in inst.failures:
					print("  FAIL ", msg)
				failed.append(inst.current_test)
	print("\n%d tests, %d failed" % [total, failed.size()])
	quit(1 if not failed.is_empty() or total == 0 else 0)
