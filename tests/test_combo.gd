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


func test_trade_needs_deck_min() -> void:
	var p := Balance.load_json("res://config/presets/combo.json")
	p.erase("_note")
	var e := scenario([], ["4S"], p)
	e.state.deck = cards(e, ["2H", "2D", "2S", "2C", "3H", "3S"])  # 6 cards, below deck_min 9
	e.state.current = []
	e.state.enemy_pile = []
	e.state.beaten = cards(e, ["4H", "4D", "4S", "4C"])
	e.state.last_beaten = e.state.beaten[3]
	e._floor_cleared()
	check(e.state.reward.get("menu", false), "reward menu")
	check(not e.menu_can("cull"), "no cull below deck_min")
	var take = e.state.reward["options"][0]
	check(not e.menu_can("trade"), "no trade below deck_min")
	check(not e.reward_menu("trade", [take.id], [e.state.deck[0].id]), "trade refused")
	e.state.deck += cards(e, ["5H", "5S", "6D"])  # 9 cards
	check(e.menu_can("trade"), "trade at deck_min")
	check(e.reward_menu("trade", [take.id], [e.state.deck[0].id]), "trade done")
	eq(e.state.deck.size(), 9, "same size")
