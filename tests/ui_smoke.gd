extends SceneTree
## UI smoke test: plays whole runs through the real UI (bot decisions, UI animations and routing).
##   godot --headless --script res://tests/ui_smoke.gd -- [--runs 3] [--shots dir]
## With --shots (run without --headless, e.g. under xvfb-run) it saves a screenshot of every new screen.

const Bot := preload("res://engine/bot.gd")
const SimLib := preload("res://sim/sim_lib.gd")

var _shots := ""
var _shot_n := 0
var _seen: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := SimLib.parse_args(OS.get_cmdline_user_args())
	var runs := int(args.get("runs", "3"))
	_shots = args.get("shots", "")
	Engine.time_scale = float(args.get("speed", "8"))
	var main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await _shot(main, "menu")
	var bot := Bot.new()
	var errors := 0
	for r in runs:
		main.new_run(100 + r)
		await _wait(main)
		var steps := 0
		if r == 0:
			await _overlays(main)
		while main.engine.state.result == "" and steps < 400:
			await _shot(main, main.screen_name + "_" + main.engine.state.phase_name())
			main.act(func(): bot.step(main.engine))
			await _wait(main)
			steps += 1
			if main.screen_name != main._screen_for_phase():
				push_error("screen %s does not match phase %s" % [main.screen_name, main.engine.state.phase_name()])
				errors += 1
		await _shot(main, "summary_" + main.engine.state.result)
		print("run %d: %s on floor %d after %d steps" % [r, main.engine.state.result, main.engine.state.floor_num, steps])
		if main.engine.state.result == "":
			errors += 1
	main.open_log()
	await _shot(main, "log")
	main.open_stats()
	await _shot(main, "stats")
	main.open_debug()
	await _shot(main, "debug")
	print("UI smoke done, errors: %d" % errors)
	quit(1 if errors > 0 else 0)


func _wait(main) -> void:
	await process_frame
	var guard := 0
	while main.is_busy() and guard < 2000:
		await process_frame
		guard += 1
	await process_frame


func _shot(main, name: String) -> void:
	if _shots == "" or _seen.has(name):
		return
	_seen[name] = true
	for i in 30:
		await process_frame
	var img := root.get_texture().get_image()
	_shot_n += 1
	img.save_png("%s/%02d_%s.png" % [_shots, _shot_n, name])


## Opens the in-fight overlays and the one-card tooltip once (catches script errors, takes shots).
func _overlays(main) -> void:
	main.act(func(): main.engine.ack_reveal() if main.engine.state.phase == main.Phase.REVEAL else null)
	await _wait(main)
	if main.engine.state.phase == main.Phase.SETUP_PICK:
		main.act(func(): main.engine.setup_pick(main.engine.state.setup_options[0].id))
		await _wait(main)
		main.act(func(): main.engine.ack_reveal())
		await _wait(main)
	var Help = load("res://ui/screens/help.gd")
	var scr = main.screen
	if main.screen_name == "combat" and not main.engine.state.hand.is_empty():
		scr._selected = [main.engine.state.hand[0].id]
		scr._update_controls()
		await _shot(main, "combat_tooltip")
		scr._selected = []
		scr._update_controls()
	for pair in [["rules", Help.rules_overlay(main)], ["aces", Help.aces_overlay(main)], ["mods", Help.mods_overlay(main)]]:
		var p: Control = pair[1]
		main.open_overlay(p)
		await _shot(main, "overlay_" + pair[0])
		p.queue_free()
		await process_frame
		await process_frame
