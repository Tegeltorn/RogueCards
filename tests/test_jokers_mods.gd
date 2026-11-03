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
	eq(int(e.preview(ids(e.state.hand))["attack"]), 7, "6 + 1")


func test_foresight() -> void:
	var e := scenario([], ["5S"], {"mods_enabled": true}, {"force_mod": "C", "pile": ["6S", "7H", "8S"]})
	eq(e.retain_limit(), 0, "no retain")
	eq(e.preview_enemies().size(), 2, "see two")


func test_hardened() -> void:
	var e := scenario([], ["12S"], {"mods_enabled": true, "ace_sac_own_color": false}, {"force_mod": "H"})
	eq(e.sacrificable_aces().size(), 0, "no ace sacrifice")


func test_rich_setup() -> void:
	var e := GameEngine.new()
	e.start_run(5, Balance.make({}), {"force_mod": "D"})
	eq(e.state.phase, Phase.SETUP_PICK, "setup pick")
	var pick = e.state.setup_options[2]
	e.setup_pick(pick.id)
	eq(e.state.deck.size(), 5, "deck 5")
	e.ack_reveal()
	var total: int = e.state.enemy_pile.size() + e.state.current.size()
	eq(total, 3, "floor 3 has the other three")
	for c in e.state.enemy_pile + e.state.current:
		check(c.suit != pick.suit, "picked three not an enemy")


func test_setup_lives_and_theme() -> void:
	var e := GameEngine.new()
	e.start_run(42, Balance.make({}), {})
	eq(e.state.lives.size(), 3, "three lives")
	for a in e.state.lives:
		check(a.suit != e.state.mod_suit, "mod ace is not a life")
	eq(e.state.deck.size(), 4, "four twos")


func test_short_floors() -> void:
	var e := GameEngine.new()
	e.start_run(3, Balance.make({"mods_enabled": false}), {})
	e.ack_reveal()
	eq(e.state.enemy_pile.size() + e.state.current.size(), 3, "floor 3 short")
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
