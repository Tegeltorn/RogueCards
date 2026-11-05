extends "res://tests/test_base.gd"
## Hand / draw economy variants: continuous refill, draw-per-turn with a hand limit, redraw, dig burn.

const Bot := preload("res://engine/bot.gd")


func test_continuous_refill_shuffles_mid_draw() -> void:
	var e := scenario(["2H"], ["3S"], {"hand_size": 3, "keep_hand": true, "refill_mode": "continuous"}, {"pile": ["4S"]})
	e.state.draw_pile = cards(e, ["9D"])
	e.state.discard = cards(e, ["5D", "6D"])
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	eq(e.state.hand.size(), 3, "drew the last card, shuffled, kept drawing")
	check(has_event(e, Ev.DECK_RESHUFFLED), "reshuffled")


func test_empty_refill_draws_short() -> void:
	var e := scenario(["2H"], ["3S"], {"hand_size": 3, "keep_hand": true}, {"pile": ["4S"]})
	e.state.draw_pile = cards(e, ["9D"])
	e.state.discard = cards(e, ["5D", "6D"])
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	eq(e.state.hand.size(), 1, "only the last card")


func test_draw_per_turn_and_hand_limit() -> void:
	var over := {"hand_size": 5, "keep_hand": true, "draw_per_turn": 2, "hand_max": 3}
	var e := scenario(["2H", "5S", "6S", "7S", "8S"], ["3S"], over, {"pile": ["4S", "4C"]})
	e.state.floor_round = 2
	e.state.draw_pile = cards(e, ["9D", "10D", "3D"])
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	eq(e.state.phase, Phase.RETAIN, "4 cards left: discard down to 3")
	eq(e.retain_limit(), 3)
	var keep: Array = ids(e.state.hand.slice(0, 3))
	check(e.retain(keep), "keep 3")
	eq(e.state.hand.size(), 5, "3 kept + 2 drawn")
	eq(e.state.discard.size(), 2, "played card and the discarded one")


func test_redraw_once_per_round() -> void:
	var e := scenario(["2H", "2S", "3C"], ["9S"], {"redraw_limit": 1, "redraw_cost": 1})
	e.state.draw_pile = cards(e, ["9D", "10D"])
	check(e.can_redraw(), "may redraw")
	check(e.redraw([e.state.hand[1].id, e.state.hand[2].id]), "redraw two")
	eq(e.state.hand.size(), 2, "drew one fewer")
	eq(e.state.discard.size(), 2, "thrown cards discarded")
	check(not e.can_redraw(), "only once")


func test_dig_burn_draws() -> void:
	var e := scenario(["2H", "2S", "3C", "4C", "5C"], ["9S"], {"burn_mode": "dig", "burn_draw": 2, "burn_no_refill": false})
	e.state.draw_pile = cards(e, ["9D", "10D"])
	check(e.burn_card(e.state.hand[1].id), "burn")
	eq(e.state.hand.size(), 6, "one burned, two drawn")
	eq(e.state.deck.size(), 4, "gone for good")
	check(e.state.played.is_empty(), "a dug card does not count")


func test_variant_presets_replay_and_finish() -> void:
	for p in ["variant_reserve", "variant_fresh", "variant_redraw"]:
		var ov := Balance.load_json("res://config/presets/%s.json" % p)
		ov.erase("_note")
		for seed in [7, 19]:
			var e := GameEngine.new()
			e.start_run(seed, classic(ov))
			var bot := Bot.new()
			var steps := 0
			while e.state.result == "" and steps < 400:
				if not bot.step(e):
					break
				steps += 1
			var copy := GameEngine.new()
			check(copy.restore(e.snapshot()), "%s seed %d replays" % [p, seed])
			eq(copy.fingerprint(), e.fingerprint(), "%s seed %d" % [p, seed])

