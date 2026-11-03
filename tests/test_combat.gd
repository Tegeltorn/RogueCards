extends "res://tests/test_base.gd"
## Damage, suit effects, shield fights, lockout, ace sacrifice.


func test_block_exact_no_damage() -> void:
	var e := scenario(["5D", "3H", "4S"], ["8S"], {}, {"pile": ["9S"]})
	e.play_cards(ids(e.state.hand.slice(0, 2)))
	e.resolve()
	eq(e.state.lives.size(), 3, "lives")
	check(has_event(e, Ev.BLOCKED), "blocked event")


func test_only_right_colour_playable() -> void:
	var e := scenario(["5D", "4S"], ["8S"])
	check(e.can_play_card(e.state.hand[0]), "red vs attack")
	check(not e.can_play_card(e.state.hand[1]), "black vs attack")
	check(not e.play_cards([e.state.hand[1].id]), "play black vs attack rejected")


func test_miss_small_costs_one_life() -> void:
	var e := scenario(["4H"], ["8S"], {}, {"pile": ["9S"]})
	e.play_cards([e.state.hand[0].id])
	e.resolve()  # miss 4
	eq(e.state.lives.size(), 2, "lives")


func test_miss_graded_costs_two_lives() -> void:
	var e := scenario(["3H"], ["8S"], {}, {"pile": ["9S"]})
	e.play_cards([e.state.hand[0].id])
	e.resolve()  # miss 5
	eq(e.state.lives.size(), 1, "lives")


func test_death() -> void:
	var e := scenario([], ["12S"], {"lives": 2}, {"pile": ["9S"]})
	e.resolve()
	eq(e.state.phase, Phase.LOST, "phase")
	eq(e.state.result, "dead", "result")


func test_spade_multiplier_rounds_down() -> void:
	var e := scenario(["5S"], ["7H"], {}, {"pile": ["9S"]})
	eq(int(e.preview([e.state.hand[0].id])["attack"]), 7, "5♠ = 7")
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	check(has_event(e, Ev.ATTACK_SUCCEEDED), "shield beaten")


func test_club_pair_bonus() -> void:
	var e := scenario(["3C", "4C"], ["9H"], {}, {"pile": ["9S"]})
	eq(int(e.preview(ids(e.state.hand))["attack"]), 9, "3♣+4♣+2")
	var e2 := scenario(["3C", "4S"], ["9H"])
	eq(int(e2.preview(ids(e2.state.hand))["attack"]), 9, "3♣+6 (4♠) no bonus")


func test_shield_fail_goes_to_bottom() -> void:
	var e := scenario(["2S"], ["9H"], {}, {"pile": ["5S", "6H"]})
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	check(has_event(e, Ev.ATTACK_FAILED), "attack failed")
	eq(e.state.enemy_pile.size(), 2, "pile size after reveal of next")
	eq(e.state.enemy_pile[-1].label(), "9♥", "failed shield last")
	eq(e.state.lives.size(), 3, "no life lost")


func test_lockout() -> void:
	var e := scenario(["2S"], ["9H"], {}, {"pile": ["6H"]})
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	check(has_event(e, Ev.LOCKOUT), "lockout")
	eq(e.state.lives.size(), 2, "lost one life")


func test_heart_carry_next_round_only() -> void:
	var e := scenario(["7H", "2D"], ["3S"], {"heart_carry_mode": "next_round"}, {"pile": ["4H", "5S"]})
	e.play_cards(ids(e.state.hand))
	e.resolve()
	eq(e.state.carry_shield, 6, "overflow 6, capped at hearts 7")
	e.retain([])
	# Next enemy is a shield: carry is lost.
	e.resolve()
	eq(e.state.carry_shield, 0, "carry lost on shield round")


func test_heart_carry_capped_by_hearts() -> void:
	var e := scenario(["2H", "9D"], ["3S"], {}, {"pile": ["5S"]})
	e.play_cards(ids(e.state.hand))
	e.resolve()
	eq(e.state.carry_shield, 2, "capped at heart sum")


func test_heart_carry_next_attack_mode() -> void:
	var e := scenario(["7H"], ["3S"], {"heart_carry_mode": "next_attack"}, {"pile": ["4H", "5S"]})
	e.play_cards(ids(e.state.hand))
	e.resolve()
	e.retain([])
	e.resolve()  # shield round, nothing played
	eq(e.state.carry_shield, 4, "carry kept")


func test_diamond_draws_same_round() -> void:
	var e := scenario(["3D"], ["9S"], {}, {"pile": ["5S"]})
	e.state.draw_pile = cards(e, ["6H"])
	e.play_cards([e.state.hand[0].id])
	eq(e.state.hand.size(), 1, "drew one")
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	check(has_event(e, Ev.BLOCKED), "3+6 blocks 9")


func test_draw_reshuffles_discard() -> void:
	var e := scenario(["3D"], ["9S"], {}, {"pile": ["5S"]})
	e.state.discard = cards(e, ["4H"])
	e.play_cards([e.state.hand[0].id])
	check(has_event(e, Ev.DECK_RESHUFFLED), "reshuffled")
	eq(e.state.hand[0].label(), "4♥", "drew from old discard")


func test_ace_sacrifice() -> void:
	var e := scenario(["2H"], ["12S"], {"ace_sac_own_color": false}, {"pile": ["5S"]})
	var aces := e.sacrificable_aces()
	check(aces.size() == 3, "all aces usable")
	e.play_cards([e.state.hand[0].id])
	e.sacrifice_ace(aces[0].id)
	eq(e.state.lives.size(), 2, "life spent")
	e.resolve()
	check(has_event(e, Ev.BLOCKED), "2+14 blocks 12")
	eq(e.state.lives.size(), 2, "no further damage")


func test_ace_sacrifice_own_colour() -> void:
	var e := scenario([], ["12S"], {"ace_sac_own_color": true}, {"force_mod": "H"})
	for a in e.sacrificable_aces():
		check(a.base_red(), "only red aces can block")


func test_ace_sacrifice_needs_two_lives() -> void:
	var e := scenario([], ["12S"], {"lives": 1, "ace_sac_own_color": false})
	eq(e.sacrificable_aces().size(), 0, "cannot sacrifice last life")


func test_retain_limit() -> void:
	var e := scenario(["2H", "5S", "6S"], ["3S"], {}, {"pile": ["4S"]})
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	eq(e.state.phase, Phase.RETAIN, "retain phase")
	check(not e.retain(ids(e.state.hand)), "cannot keep 2")
	var keep = e.state.hand[1]
	check(e.retain([keep.id]), "keep 1")
	check(e.state.hand.has(keep), "kept card in new hand")
