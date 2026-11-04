extends SceneTree
## UI smoke test: plays whole runs through the real UI (bot decisions, UI animations and routing).
##   godot --headless --script res://tests/ui_smoke.gd -- [--runs 3] [--shots dir]
## With --shots (run without --headless, e.g. under xvfb-run) it saves a screenshot of every new screen.

const Bot := preload("res://engine/bot.gd")
const SimLib := preload("res://sim/sim_lib.gd")

var _shots := ""
var _shot_n := 0
var _seen: Dictionary = {}
var _burned := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := SimLib.parse_args(OS.get_cmdline_user_args())
	var runs := int(args.get("runs", "3"))
	# Watchdog: a script error can leave the loop waiting forever; fail instead of hanging.
	create_timer(float(args.get("watchdog", "300")), true, false, true).timeout.connect(func():
		push_error("UI smoke test timed out")
		quit(1))
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
			if r == 0 and main.screen_name == "reward":
				await _reward_via_ui(main)
			elif r == 0 and main.screen_name == "combat" and main.engine.state.phase == main.Phase.PLAY:
				await _fight_via_ui(main)
			else:
				main.act(func(): bot.step(main.engine))
			await _wait(main)
			steps += 1
			# The saved run must replay to the same state (resume after a reload).
			var copy = load("res://engine/engine.gd").new()
			if not copy.restore(main.engine.snapshot()):
				push_error("saved run does not replay at step %d" % steps)
				errors += 1
			if main.screen_name != main._screen_for_phase():
				push_error("screen %s does not match phase %s" % [main.screen_name, main.engine.state.phase_name()])
				errors += 1
		await _shot(main, "summary_" + main.engine.state.result)
		print("run %d: %s on floor %d after %d steps" % [r, main.engine.state.result, main.engine.state.floor_num, steps])
		if main.engine.state.result == "":
			errors += 1
	# Resume: a run saved mid-fight comes back on start (as after the page reloads).
	main.new_run(7)
	await _wait(main)
	main.act(func(): bot.step(main.engine))
	await _wait(main)
	var want: String = main.engine.fingerprint()
	var again = load("res://ui/main.tscn").instantiate()
	root.add_child(again)
	await _wait(again)
	if again.engine == null or again.engine.fingerprint() != want or again.screen_name != again._screen_for_phase():
		push_error("unfinished run was not resumed")
		errors += 1
	again.quit_to_menu()
	await create_timer(1.0).timeout  # let its screen fade-out tweens finish
	again.queue_free()
	await process_frame
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
	# Start pick through the reveal screen: select the three(s), confirm; the fight must start at once.
	if main.engine.state.phase == main.Phase.SETUP_PICK:
		var scr0 = main.screen
		for i in main.engine.state.setup_picks:
			scr0._on_pick(main.engine.state.setup_options[i].id)
		await scr0._on_start()
		await _wait(main)
		if main.engine.state.phase != main.Phase.PLAY:
			push_error("fight did not start after the start pick: " + main.engine.state.phase_name())
	else:
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


## Uses the reward screen like a player: select, (pick a deck card), confirm.
func _reward_via_ui(main) -> void:
	var scr = main.screen
	var s = main.engine.state
	if s.phase == main.Phase.REWARD:
		var picks: int = mini(int(s.reward["picks"]), s.reward["options"].size())
		# ♦ arrives preselected; otherwise select as many options as allowed.
		for c in s.reward["options"]:
			if scr._opt_sels.size() < picks and not scr._opt_sels.has(c.id):
				scr._on_option(c.id)
	if scr._deck_pickable():
		scr._on_deck(s.deck[0].id)
	await _shot(main, "reward_selected_" + s.phase_name())
	if scr._confirm.disabled:
		push_error("reward confirm disabled in %s: %s" % [s.phase_name(), scr._confirm.text])
		main.act(func(): Bot.new().step(main.engine))
		return
	await scr._on_confirm()


## Fights like a player: drag a useful card onto the enemy while still short, otherwise End turn.
func _fight_via_ui(main) -> void:
	var scr = main.screen
	var e = main.engine
	var t: Dictionary = e.compute(e.state.played)
	var short: bool = int(t["block"]) < int(t["block_need"]) or int(t["attack"]) < int(t["attack_need"])
	var cards: Array = e.playable_cards()
	# Once per smoke test: burn a card on the fire as soon as burning is allowed.
	if short and not _burned and e.can_burn() and scr._hand_views.has(e.state.hand[0].id):
		_burned = true
		await _burn_via_ui(main, e.state.hand[0].id)
		return
	if short and not cards.is_empty() and scr._hand_views.has(cards[0].id):
		var cv = scr._hand_views[cards[0].id]
		var drop: Vector2 = scr._drop_zone().get_center()
		scr._on_drag_started(cv)
		scr._on_drag_moved(cv, drop)
		scr._on_drag_released(cv, drop)
		return
	scr._on_main()


## Drags a hand card onto the fire like a player; it must burn.
func _burn_via_ui(main, id: int) -> void:
	var scr = main.screen
	var e = main.engine
	var cv = scr._hand_views[id]
	var fire: Vector2 = scr._fire.get_global_rect().get_center()
	scr._on_drag_started(cv)
	scr._on_drag_moved(cv, fire)
	await _shot(main, "combat_burn_hover")
	scr._on_drag_released(cv, fire)
	if not e.state.played.any(func(c): return c.burned):
		push_error("dropping a card on the fire did not burn it")
	await _wait(main)
	await _shot(main, "combat_burned")
