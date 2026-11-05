extends "res://tests/test_base.gd"
## The combined proposal (config/presets/combo.json): fight once + reserve hand + reward menu.

const Bot := preload("res://engine/bot.gd")


func _combo() -> Dictionary:
	var p := Balance.load_json("res://config/presets/combo.json")
	p.erase("_note")
	return Balance.make(p)


func test_combo_runs_always_finish() -> void:
	var b := _combo()
	var wins := 0
	for sd in range(1, 121):
		var e := GameEngine.new()
		e.record_events = false
		e.start_run(sd, b, {})
		Bot.new().play_run(e)
		check(e.state.result == "win" or e.state.result == "dead", "seed %d result %s (never stuck)" % [sd, e.state.result])
		if e.state.result == "win":
			wins += 1
	check(wins > 5 and wins < 60, "combo wins a minority of runs (%d of 120)" % wins)


func test_combo_every_enemy_fought_once() -> void:
	var p := Balance.load_json("res://config/presets/combo.json")
	p.erase("_note")
	p["mods_enabled"] = false
	var e := scenario(["2S"], ["5H"], p, {"pile": ["6S"]})
	e.play_cards([e.state.hand[0].id])
	e.resolve()  # 3 attack against a 5 shield (a small miss): it falls anyway, for a life
	eq(e.state.lives.size(), int(p["lives"]) - 1, "a failed shield costs 1 life")
	check(not e.state.enemy_pile.any(func(c): return c.rank == 5), "and does not come back")
