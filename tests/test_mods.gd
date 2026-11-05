extends "res://tests/test_base.gd"
## Floors, mods, setup and determinism.

const Bot := preload("res://engine/bot.gd")


func test_kings_floor_is_the_four_kings() -> void:
	var e := scenario([], ["4S"])
	e.state.deck = cards(e, ["2H", "2D", "2S", "2C", "5C"])
	e._start_floor(13)
	var kings: Array = e.state.enemy_pile + e.state.current
	eq(kings.size(), 4, "four kings")
	for k in kings:
		eq(k.rank, 13, "a king")


func test_every_floor_has_four_cards() -> void:
	var e := GameEngine.new()
	e.start_run(3, classic({"mods_enabled": false}), {})
	while e.state.phase == Phase.SETUP_PICK:
		e.setup_pick(e.state.setup_options[0].id)
	e.ack_reveal()
	for f in range(4, 14):
		e._start_floor(f)
		eq(e.state.enemy_pile.size() + e.state.current.size(), 4, "floor %d has 4 enemy cards" % f)


func test_face_hand_size() -> void:
	var e := scenario([], ["4S"], {"hand_size": 4, "face_hand_size": 3})
	e.state.deck = cards(e, ["2H", "2D", "2S", "2C", "5C"])
	e._start_floor(10)
	eq(e.state.hand.size(), 4, "floor 10: full hand")
	e._start_floor(11)
	eq(e.state.hand.size(), 3, "Jacks demand tribute: 3 cards")


func test_boss_hand_size() -> void:
	var e := scenario([], ["4S"])
	e.state.deck = cards(e, ["2H", "2D", "2S", "2C", "5C"])
	e._start_floor(13)
	eq(e.state.hand.size(), 3, "boss hand 3")


func test_win_after_boss() -> void:
	var e := scenario([], ["13S"])
	e.state.floor_num = 13
	e.state.enemy_pile = []
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
	var e := scenario([], ["12S"], {"mods_enabled": true}, {"force_mod": "H"})
	eq(e.sacrificable_aces().size(), 0, "no ace sacrifice")
	eq(e.state.lives.size(), 4, "mod ace is an extra life")


func test_random_start_threes() -> void:
	var e := GameEngine.new()
	e.start_run(5, classic({"mods_enabled": false, "start_random": 2, "start_pick_take": 0}), {})
	eq(e.state.phase, Phase.REVEAL, "no pick: straight to the reveal")
	eq(e.state.deck.size(), 6, "four twos + two random threes")
	eq(e.state.deck.filter(func(c): return c.rank == 3).size(), 2, "two threes")
	var f := GameEngine.new()
	f.start_run(5, classic({"mods_enabled": false, "start_random": 2}), {})
	eq(ids(f.state.deck), ids(e.state.deck), "same seed, same threes")


func test_start_pick() -> void:
	var e := GameEngine.new()
	e.start_run(5, classic({"mods_enabled": false, "start_random": 0, "start_pick_offer": 3, "start_pick_take": 1}), {})
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
	e.start_run(5, classic({}), {"force_mod": "D"})
	eq(int(e.reward_rules("C")["reveal"]), 3, "♣ reward reveals 3")
	eq(int(e.reward_rules("D")["picks"]), 3, "♦ reward takes all 3 revealed cards")
	eq(int(e.reward_rules("D")["reveal"]), 3, "♦ reward reveals 3")


func test_spec_preset_starts_on_three() -> void:
	var e := GameEngine.new()
	e.start_run(5, classic(Balance.load_json("res://config/presets/spec.json")), {"force_mod": "S"})
	eq(e.state.phase, Phase.REVEAL, "no start pick in the spec rules")
	e.ack_reveal()
	eq(e.state.floor_num, 3, "spec starts on the threes")


func test_setup_lives() -> void:
	var e := GameEngine.new()
	e.start_run(42, classic({"mods_enabled": false}), {})
	eq(e.state.lives.size(), int(classic()["lives"]), "lives from balance.json")
	for a in e.state.lives:
		check(a.suit != e.state.mod_suit, "mod ace is not a life")
	eq(e.state.deck.size(), 4 + int(classic()["start_random"]), "four twos + the random threes")


func test_determinism() -> void:
	var logs: Array = []
	for i in 2:
		var e := GameEngine.new()
		e.start_run(1234, classic({}), {})
		Bot.new().play_run(e)
		logs.append(JSON.stringify(e.state.events))
	eq(logs[0], logs[1], "same seed -> same log")
	var e3 := GameEngine.new()
	e3.start_run(1235, classic({}), {})
	Bot.new().play_run(e3)
	check(JSON.stringify(e3.state.events) != logs[0], "different seed differs")


func test_bot_runs_finish() -> void:
	var stuck := 0
	for sd in range(1, 200):
		var e := GameEngine.new()
		e.record_events = false
		e.start_run(sd, classic({}), {})
		Bot.new().play_run(e)
		# "stuck": an unbreakable shield (a player would restart); it must stay rare.
		check(["win", "dead", "stuck"].has(e.state.result), "seed %d result %s" % [sd, e.state.result])
		if e.state.result == "stuck":
			stuck += 1
	check(stuck <= 24, "stuck runs stay a minority (%d of 199)" % stuck)


func test_hardened_failed_attack_is_beaten() -> void:
	var e := scenario(["2H"], ["9S"], {"mods_enabled": true, "failed_attack_returns": true}, {"pile": ["5S", "6H"], "force_mod": "H"})
	eq(e.mod.id, "hardened", "hardened mod")
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	check(has_event(e, Ev.DAMAGE_TAKEN), "damage taken")
	check(not has_event(e, Ev.ATTACK_RETURNED), "no return under Hardened")
	check(has_event(e, Ev.ENEMY_DEFEATED), "beaten anyway")
