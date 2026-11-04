extends "res://tests/test_base.gd"
## Red/black jokers, mods, setup and determinism.

const Bot := preload("res://engine/bot.gd")


func test_dual_card_plays_both_colours() -> void:
	var e := scenario(["5S"], ["4S"])
	e.state.hand[0].joker = "dual"
	check(e.can_play_card(e.state.hand[0]), "dual black card blocks")


func test_draw2_on_play() -> void:
	var e := scenario(["5H"], ["4S"])
	e.state.hand[0].joker = "draw2"
	e.state.draw_pile = cards(e, ["2S", "3S"])
	e.play_cards([e.state.hand[0].id])
	eq(e.state.hand.size(), 2, "drew two")


func test_innate_in_first_hand() -> void:
	var e := scenario([], ["4S"])
	var d := cards(e, ["2H", "2D", "2S", "2C", "9C"])
	d[4].joker = "innate"
	e.state.deck = d
	e.state.balance["hand_size"] = 1
	e._start_floor(4)
	check(e.state.hand.has(d[4]), "innate card drawn first")


func _boss(theme: String, pile: Array) -> GameEngine:
	var e := scenario([], ["13S"], {}, {"force_theme": theme})
	e.state.floor_num = 13
	e.state.enemy_pile = cards(e, pile)
	return e


func test_black_joker_shield() -> void:
	var e := _boss("D", ["0J", "13H"])
	e.state.current = []
	e._next_round()
	eq(e.attack_need(), 14, "shield 14")


func test_black_joker_attack() -> void:
	var e := _boss("S", ["0J"])
	e._next_round()
	eq(e.block_need(), 14, "attack 14")


func test_black_joker_double_reveal() -> void:
	var e := _boss("C", ["0J", "13H", "13S"])
	e._next_round()
	eq(e.state.current.size(), 2, "two cards")
	eq(e.block_need(), 13, "attack part")
	eq(e.attack_need(), 13, "shield part")


func test_black_joker_returns_king() -> void:
	var e := _boss("H", ["0J", "13S"])
	e.state.beaten = cards(e, ["13D"])
	e._next_round()
	eq(e.state.current[0].label(), "K♠", "next card revealed")
	eq(e.state.enemy_pile.size(), 1, "king returned")
	eq(e.state.enemy_pile[0].label(), "K♦", "beaten king back")


func test_boss_hand_size() -> void:
	var e := scenario([], ["4S"])
	e.state.deck = cards(e, ["2H", "2D", "2S", "2C", "5C"])
	e._start_floor(13)
	eq(e.state.hand.size(), 3, "boss hand 3")


func test_win_after_boss() -> void:
	var e := _boss("S", [])
	e.state.current = cards(e, ["13S"])
	e.state.hand = cards(e, ["14H"])
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	eq(e.state.result, "win", "won")


func test_bloodthirst() -> void:
	var e := scenario(["4S"], ["5S"], {"mods_enabled": true}, {"force_mod": "S"})
	eq(e.block_need(), 6, "enemy attack +1")
	set_round(e, ["4S"], ["5H"])
	eq(int(e.preview(ids(e.state.hand))["attack"]), 10, "6 + 4")


func test_foresight() -> void:
	var e := scenario([], ["5S"], {"mods_enabled": true}, {"force_mod": "C", "pile": ["6S", "7H", "8S"]})
	eq(e.preview_enemies().size(), 1, "see the next card")
	eq(e.retain_limit(), 1, "no retain penalty")


func test_hardened() -> void:
	var e := scenario([], ["12S"], {"mods_enabled": true, "ace_sac_own_color": false}, {"force_mod": "H"})
	eq(e.sacrificable_aces().size(), 0, "no ace sacrifice")
	eq(e.state.lives.size(), 4, "mod ace is a 4th life")


func test_start_pick() -> void:
	var e := GameEngine.new()
	e.start_run(5, Balance.make({"mods_enabled": false}), {})
	eq(e.state.phase, Phase.SETUP_PICK, "start pick")
	eq(e.state.setup_options.size(), 3, "three threes offered")
	eq(e.state.setup_picks, 1, "keep one")
	for c in e.state.setup_options:
		eq(c.rank, 3, "offered cards are threes")
	e.setup_pick(e.state.setup_options[1].id)
	eq(e.state.phase, Phase.REVEAL, "done after one")
	eq(e.state.deck.size(), 5, "four twos + a three")
	e.ack_reveal()
	eq(e.state.floor_num, 4, "the run starts on the fours")


func test_rich_reveals_more() -> void:
	var e := GameEngine.new()
	e.start_run(5, Balance.make({}), {"force_mod": "D"})
	eq(e.state.setup_picks, 1, "Rich keeps one three like everyone")
	eq(int(e.reward_rules("C")["reveal"]), 3, "♣ reward reveals 3")
	eq(int(e.reward_rules("D")["picks"]), 3, "♦ reward takes all 3 revealed cards")
	eq(int(e.reward_rules("D")["reveal"]), 3, "♦ reward reveals 3")


func test_spec_preset_starts_on_three() -> void:
	var e := GameEngine.new()
	e.start_run(5, Balance.make(Balance.load_json("res://config/presets/spec.json")), {"force_mod": "S"})
	eq(e.state.phase, Phase.REVEAL, "no start pick in the spec rules")
	e.ack_reveal()
	eq(e.state.floor_num, 3, "spec starts on the threes")


func test_setup_lives_and_theme() -> void:
	var e := GameEngine.new()
	e.start_run(42, Balance.make({}), {})
	eq(e.state.lives.size(), 3, "three lives")
	for a in e.state.lives:
		check(a.suit != e.state.mod_suit, "mod ace is not a life")
	eq(e.state.deck.size(), 4, "four twos before the pick")


func test_short_floors() -> void:
	var e := GameEngine.new()
	e.start_run(3, Balance.make({"mods_enabled": false}), {})
	while e.state.phase == Phase.SETUP_PICK:
		e.setup_pick(e.state.setup_options[0].id)
	e.ack_reveal()
	eq(e.state.enemy_pile.size() + e.state.current.size(), 3, "floor 4 short")
	e._start_floor(6)
	eq(e.state.enemy_pile.size() + e.state.current.size(), 4, "floor 6 full")


func test_determinism() -> void:
	var logs: Array = []
	for i in 2:
		var e := GameEngine.new()
		e.start_run(1234, Balance.make({}), {})
		Bot.new().play_run(e)
		logs.append(JSON.stringify(e.state.events))
	eq(logs[0], logs[1], "same seed -> same log")
	var e3 := GameEngine.new()
	e3.start_run(1235, Balance.make({}), {})
	Bot.new().play_run(e3)
	check(JSON.stringify(e3.state.events) != logs[0], "different seed differs")


func test_bot_runs_finish() -> void:
	for sd in range(1, 200):
		var e := GameEngine.new()
		e.record_events = false
		e.start_run(sd, Balance.make({}), {})
		Bot.new().play_run(e)
		check(e.state.result == "win" or e.state.result == "dead", "seed %d result %s" % [sd, e.state.result])


func test_hardened_failed_attack_is_beaten() -> void:
	var e := scenario(["2H"], ["9S"], {"mods_enabled": true, "failed_attack_returns": true}, {"pile": ["5S", "6H"], "force_mod": "H"})
	eq(e.mod.id, "hardened", "hardened mod")
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	check(has_event(e, Ev.DAMAGE_TAKEN), "damage taken")
	check(not has_event(e, Ev.ATTACK_RETURNED), "no return under Hardened")
	check(has_event(e, Ev.ENEMY_DEFEATED), "beaten anyway")
