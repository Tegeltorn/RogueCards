extends "res://tests/test_base.gd"
## Damage, suit effects, shield fights, ace sacrifice, burning.


func test_block_exact_no_damage() -> void:
	var e := scenario(["5D", "3H", "4S"], ["8S"], {}, {"pile": ["9S"]})
	e.play_cards(ids(e.state.hand.slice(0, 2)))
	e.resolve()
	eq(e.state.lives.size(), 3, "lives")
	check(has_event(e, Ev.BLOCKED), "blocked event")


func test_any_card_playable_but_only_right_colour_counts() -> void:
	var e := scenario(["5D", "4S"], ["8S"], {}, {"pile": ["9S"]})
	check(e.can_play_card(e.state.hand[1]), "black card may be played vs attack")
	check(e.is_effective(e.state.hand[0]), "red counts vs attack")
	check(not e.is_effective(e.state.hand[1]), "black does not count vs attack")
	eq(e.playable_cards().size(), 1, "only effective cards listed for the bot")
	check(e.play_cards([e.state.hand[1].id]), "play black vs attack")
	eq(int(e.compute(e.state.played)["block"]), 0, "black adds no block")


func test_diamond_draws_against_shield() -> void:
	var e := scenario(["3D"], ["9H"], {}, {"pile": ["5S"]})
	e.state.draw_pile = cards(e, ["6S"])
	e.play_cards([e.state.hand[0].id])
	eq(e.state.hand.size(), 1, "♦ draws even against a shield")


func test_hearts_on_shield_store_full_value() -> void:
	var e := scenario(["6H", "2S"], ["3H"], {}, {"pile": ["7S"]})
	e.play_cards(ids(e.state.hand))  # 2♠ = 3 attack beats shield 3, 6♥ stored
	e.resolve()
	eq(e.state.carry_shield, 6, "full heart value stored")
	# Next round (attack 7): the stored 6 counts as block before any card is played.
	eq(e.block_need(), 7, "next enemy")
	eq(int(e.compute([])["block"]), 6, "stored shield counts")


func test_miss_small_costs_one_life() -> void:
	var e := scenario(["4H"], ["8S"], {"graded_threshold": 5}, {"pile": ["9S"]})
	e.play_cards([e.state.hand[0].id])
	e.resolve()  # miss 4
	eq(e.state.lives.size(), 2, "lives")


func test_miss_graded_costs_two_lives() -> void:
	var e := scenario(["3H"], ["8S"], {"graded_threshold": 5}, {"pile": ["9S"]})
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
	var e := scenario(["3C", "4C"], ["9H"], {"club_pair_bonus": 2}, {"pile": ["9S"]})
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


func test_last_shield_unbroken_comes_back_without_damage() -> void:
	# No black cards left behind it: the shield still just goes to the bottom (no last stand).
	var e := scenario(["2S", "9H"], ["9H"], {}, {"pile": ["6H"]})
	check(not e.is_effective(e.state.hand[1]), "red cards don't count against a shield")
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	check(has_event(e, Ev.ATTACK_FAILED), "the shield holds")
	eq(e.state.lives.size(), 3, "no life lost")
	eq(e.state.enemy_pile.size(), 1, "it is back in the pile behind 6♥")
	eq(e.state.enemy_pile[-1].label(), "9♥", "at the bottom")


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


func test_only_first_diamond_draws() -> void:
	var e := scenario(["3D", "4D"], ["9S"], {"diamond_draw": "once"}, {"pile": ["5S"]})
	e.state.draw_pile = cards(e, ["6H", "7H"])
	e.play_cards([e.state.hand[0].id])
	eq(e.state.hand.size(), 2, "first ♦ drew (4♦ + 7♥)")
	e.play_cards([e.state.hand[0].id])
	eq(e.state.hand.size(), 1, "second ♦ draws nothing")
	e.resolve()
	set_round(e, ["2D"], ["4S"], ["5S"])
	e.state.draw_pile = cards(e, ["6H"])
	e.play_cards([e.state.hand[0].id])
	eq(e.state.hand.size(), 1, "a new round: ♦ draws again")


func test_diamond_needs_cards_in_the_draw_pile() -> void:
	var e := scenario(["3D"], ["9S"], {}, {"pile": ["5S"]})
	e.state.discard = cards(e, ["4H"])
	e.play_cards([e.state.hand[0].id])
	check(not has_event(e, Ev.DECK_RESHUFFLED), "no reshuffle mid-round")
	eq(e.state.hand.size(), 0, "nothing drawn")
	eq(e.state.discard.size(), 1, "discard untouched")


func test_refill_reshuffles_discard() -> void:
	var e := scenario(["3D"], ["2S"], {"hand_size": 2}, {"pile": ["5S"]})
	e.state.discard = cards(e, ["4H", "4C"])
	e.play_cards([e.state.hand[0].id])
	e.resolve()  # end of turn: the hand is refilled from the shuffled discard pile
	check(has_event(e, Ev.DECK_RESHUFFLED), "reshuffled at the refill")
	eq(e.state.hand.size(), 2, "refilled")


func test_ace_sacrifice() -> void:
	var e := scenario(["2H"], ["12S"], {}, {"pile": ["5S"], "force_mod": "S"})
	var aces := e.sacrificable_aces()
	eq(aces.size(), 2, "the two red aces can block")
	e.play_cards([e.state.hand[0].id])
	e.sacrifice_ace(aces[0].id)
	eq(e.state.lives.size(), 2, "life spent")
	e.resolve()
	check(has_event(e, Ev.BLOCKED), "2+14 blocks 12")
	eq(e.state.lives.size(), 2, "no further damage")


func test_ace_sacrifice_own_colour() -> void:
	var e := scenario([], ["12S"], {}, {"force_mod": "H"})
	for a in e.sacrificable_aces():
		check(a.base_red(), "only red aces can block")


func test_ace_sacrifice_needs_two_lives() -> void:
	var e := scenario([], ["12S"], {"lives": 1})
	eq(e.sacrificable_aces().size(), 0, "cannot sacrifice last life")


func test_retain_limit() -> void:
	var e := scenario(["2H", "5S", "6S"], ["3S"], {"keep_hand": false}, {"pile": ["4S"]})
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	eq(e.state.phase, Phase.RETAIN, "retain phase")
	check(not e.retain(ids(e.state.hand)), "cannot keep 2")
	var keep = e.state.hand[1]
	check(e.retain([keep.id]), "keep 1")
	check(e.state.hand.has(keep), "kept card in new hand")


func test_no_retain_when_floor_cleared() -> void:
	var e := scenario(["5D", "4S"], ["3S"])
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	check(e.state.phase != Phase.RETAIN, "no keep step after the last enemy card")


func test_overpower_discards_and_draws() -> void:
	var e := scenario(["7S", "3H"], ["5S"], {}, {"pile": ["9S"]})
	e.state.draw_pile = cards(e, ["6D"])
	e.play_cards([e.state.hand[0].id])  # 7♠ = 10 attack >= 2 × 5
	check(has_event(e, Ev.OVERPOWER), "overpower")
	eq(e.state.played.size(), 0, "black cards left the table")
	eq(e.state.discard.size(), 1, "discarded")
	eq(e.state.hand.size(), 2, "drew 1 (3♥ + 6♦)")
	eq(e.state.current.size(), 1, "the enemy is still there")
	e.resolve()
	eq(e.state.lives.size(), 1, "it still attacks at End turn: miss 5 costs 2 lives")


func test_no_overpower_below_double() -> void:
	var e := scenario(["5S"], ["5S"], {}, {"pile": ["9S"]})
	e.play_cards([e.state.hand[0].id])  # 7 < 10
	check(not has_event(e, Ev.OVERPOWER), "not enough")
	eq(e.state.played.size(), 1, "card stays on the table")


func test_keep_hand_between_rounds() -> void:
	var e := scenario(["2H", "5S", "6S"], ["3S"], {"hand_size": 3}, {"pile": ["4S"]})
	e.state.draw_pile = cards(e, ["9D"])
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	eq(e.state.phase, Phase.PLAY, "no keep step")
	eq(e.state.hand.size(), 3, "5♠ and 6♠ stay, one card drawn")
	check(e.state.hand.any(func(c): return c.label() == "9♦"), "drew up to the hand size")


func test_overpower_counts_cards_played_separately() -> void:
	var e := scenario(["4S", "3S", "2H"], ["5S"], {}, {"pile": ["9S"]})
	e.state.draw_pile = cards(e, ["6D", "7D"])
	e.play_cards([e.state.hand[0].id])  # 4♠ = 6 < 10
	check(not has_event(e, Ev.OVERPOWER), "not yet")
	e.play_cards([e.state.hand[0].id])  # + 3♠ = 4 → 10 >= 10
	check(has_event(e, Ev.OVERPOWER), "overpower from both plays")
	var n := e.state.hand.size()
	e.state.hand.append(card(e, "5C"))
	e.state.hand.append(card(e, "6C"))
	e.play_cards([e.state.hand[n].id, e.state.hand[n + 1].id])
	var count := 0
	for ev in e.state.events:
		if ev["type"] == Ev.OVERPOWER:
			count += 1
	eq(count, 1, "only once per round")


func test_min_draw_and_free_discard() -> void:
	var e := scenario(["2H", "5S", "6S"], ["3S"], {"hand_size": 3, "min_draw": 1, "free_discard": true}, {"pile": ["4S"]})
	e.state.draw_pile = cards(e, ["9D", "8D"])
	check(e.discard_card(e.state.hand[1].id), "free discard")
	eq(e.state.hand.size(), 2, "card left the hand")
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	eq(e.state.hand.size(), 3, "6♠ kept + drew 2 (fill to 3, min 1)")
	var f := scenario(["2H"], ["3S"], {"free_discard": false})
	check(not f.discard_card(f.state.hand[0].id), "discard off by default")


func test_failed_block_attack_returns() -> void:
	var e := scenario(["2H"], ["9S"], {"failed_attack_returns": true}, {"pile": ["5S", "6H"]})
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	check(has_event(e, Ev.DAMAGE_TAKEN), "damage taken")
	check(has_event(e, Ev.ATTACK_RETURNED), "attack returned")
	check(not has_event(e, Ev.ENEMY_DEFEATED), "not beaten")
	eq(e.state.enemy_pile[-1].label(), "9♠", "failed attack goes to the bottom")
	eq(e.state.lives.size(), 1, "miss of 7 costs 2 lives")


func test_failed_block_beaten_when_rule_off() -> void:
	var e := scenario(["2H"], ["9S"], {"failed_attack_returns": false}, {"pile": ["5S", "6H"]})
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	check(not has_event(e, Ev.ATTACK_RETURNED), "no return")
	check(has_event(e, Ev.ENEMY_DEFEATED), "beaten either way")


func test_perfect_hit_draws_extra_next_hand() -> void:
	var e := scenario(["5H", "3S"], ["5S"], {"hand_size": 2, "perfect_draw": 1}, {"pile": ["6S"]})
	e.state.draw_pile = cards(e, ["2D", "3D", "4D"])
	e.play_cards([e.state.hand[0].id])  # exactly 5
	e.resolve()
	check(has_event(e, Ev.PERFECT), "perfect block")
	eq(e.state.hand.size(), 3, "3♠ kept + fill to 2 + 1 extra")


func test_burn_double_counts_twice_its_rank() -> void:
	var e := scenario(["7H", "3S"], ["12S"], {"burn_mode": "double", "burn_limit": 1}, {"pile": ["5S"]})
	e.state.deck += cards(e, ["2C", "2D", "2H", "2S"])  # deck above the minimum
	var h = e.state.hand[0]
	check(e.burn_card(h.id), "burn 7♥")
	check(not e.state.deck.has(h), "gone from the deck")
	check(has_event(e, Ev.CARD_BURNED), "burn event")
	eq(int(e.compute(e.state.played)["block"]), 14, "7♥ burned blocks 14")
	e.resolve()
	check(has_event(e, Ev.BLOCKED), "14 blocks 12")
	check(not e.state.discard.has(h), "not in the discard pile")
	check(not e.state.draw_pile.has(h), "not in the draw pile")


func test_burn_has_no_suit_effects() -> void:
	var e := scenario(["5S", "4D", "6H"], ["9H"], {"burn_mode": "double", "burn_limit": 0}, {"pile": ["5S"]})
	e.state.deck += cards(e, ["2C", "2D", "2H", "2S"])
	e.state.draw_pile = cards(e, ["8C"])
	e.burn_card(e.state.hand[0].id)  # 5♠ burned: 10, not 15
	eq(int(e.compute(e.state.played)["attack"]), 10, "no ♠ × 1.5")
	e.burn_card(e.state.hand[0].id)  # 4♦ burned: no draw
	eq(e.state.hand.size(), 1, "♦ burned draws nothing")
	e.burn_card(e.state.hand[0].id)  # 6♥ burned against a shield: no stored shield
	e.resolve()
	eq(e.state.carry_shield, 0, "♥ burned stores no shield")


func test_burn_swap_counts_as_other_colour() -> void:
	var e := scenario(["8H"], ["9D"], {"burn_mode": "swap"}, {"pile": ["5S"]})
	e.state.deck += cards(e, ["2C", "2D", "2H", "2S"])
	e.burn_card(e.state.hand[0].id)
	var t := e.compute(e.state.played)
	eq(int(t["attack"]), 8, "8♥ burned attacks 8")
	eq(int(t["block"]), 0, "and doesn't block")


func test_burn_limits() -> void:
	var e := scenario(["2S", "3S", "4S"], ["9H"], {"burn_mode": "double", "burn_limit": 1, "burn_min_deck": 5}, {"pile": ["5S"]})
	e.state.deck += cards(e, ["2C", "2D"])  # 5 cards
	check(e.burn_card(e.state.hand[0].id), "first burn")
	check(not e.burn_card(e.state.hand[0].id), "once per round")
	var f := scenario(["2S", "3S"], ["9H"], {"burn_mode": "double", "burn_limit": 0, "burn_min_deck": 5}, {"pile": ["5S"]})
	f.state.deck += cards(f, ["2C", "2D"])  # 4 cards
	check(not f.can_burn(), "needs burn_min_deck cards in the deck")
	var u := scenario(["2S", "3S", "4S"], ["9H"], {"burn_mode": "double", "burn_limit": 0, "burn_min_deck": 5}, {"pile": ["5S"]})
	u.state.deck += cards(u, ["2C", "2D", "2H"])  # 6 cards
	check(u.burn_card(u.state.hand[0].id), "burn 1 (deck 6 -> 5)")
	check(u.burn_card(u.state.hand[0].id), "burn 2 (deck 5 -> 4): no per-round limit")
	check(not u.can_burn(), "deck 4: no more")
	var g := scenario(["2S"], ["9H"], {"burn_mode": "off"}, {"pile": ["5S"]})
	g.state.deck += cards(g, ["2C", "2D", "2H", "2S"])
	check(not g.burn_card(g.state.hand[0].id), "burning off")


func test_burn_skips_next_refill() -> void:
	var e := scenario(["7H", "2S", "3S"], ["12S"], {"burn_mode": "double", "burn_no_refill": true, "hand_size": 4}, {"pile": ["5S", "6S"]})
	e.state.deck += cards(e, ["2C", "2D", "2H", "2S"])
	e.state.draw_pile = cards(e, ["9D", "9H", "8D"])
	e.burn_card(e.state.hand[0].id)
	e.resolve()
	check(has_event(e, Ev.REFILL_SKIPPED), "refill skipped")
	eq(e.state.hand.size(), 2, "only the two kept cards")
	e.resolve()
	eq(e.state.hand.size(), 4, "refilled again the round after")


func test_burned_card_sets_the_reward() -> void:
	var e := scenario(["5H"], ["6S"], {"burn_mode": "double"})
	e.state.deck += cards(e, ["2C", "2D", "2H", "2S"])
	e.burn_card(e.state.hand[0].id)
	e.resolve()
	eq(e.state.reward.get("suit", ""), "H", "the burned 5♥ finished the floor")
