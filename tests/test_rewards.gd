extends "res://tests/test_base.gd"
## Rewards decided by the suit of the player's last card that counted against the final enemy card.


## Finish floor 3 with an ace of `last`'s suit: a red ace blocks an attack (3S), a black ace breaks a
## shield (3H), so that ace sets the reward.
func _clear_with(last: String, deck: Array, over: Dictionary = {}, beaten_before: Array = []) -> GameEngine:
	var suit := last.right(1)
	var red := suit in ["H", "D"]
	var e := scenario([], ["3S" if red else "3H"], over)
	var s := e.state
	s.deck = cards(e, deck)
	s.beaten = cards(e, beaten_before)
	s.hand = cards(e, ["14" + suit])
	e.play_cards([s.hand[0].id])
	e.resolve()
	return e


func _finish(hand: Array, enemy: String) -> GameEngine:
	var e := scenario(hand, [enemy])
	e.state.deck = cards(e, ["2H", "2D", "2S", "2C"])
	e.play_cards(ids(e.state.hand))
	e.resolve()
	return e


func test_reward_follows_last_counting_card() -> void:
	eq(_finish(["5D", "6H"], "3S").state.reward.get("suit"), "H", "last red blocker")
	eq(_finish(["6H", "5D"], "3S").state.reward.get("suit"), "D", "play order decides")
	eq(_finish(["5H", "2C"], "3S").state.reward.get("suit"), "H", "a black card doesn't block")
	eq(_finish(["9C", "4D"], "3H").state.reward.get("suit"), "C", "a red card doesn't break a shield")
	eq(_finish(["2S", "9C"], "3H").state.reward.get("suit"), "C", "last black attacker")


func test_reward_card_preview_matches() -> void:
	var e := scenario(["5D", "6H", "2C"], ["3S"])
	var h: Array = e.state.hand
	eq(e.reward_card([h[0], h[1], h[2]]).suit, "H", "preview: last red")
	eq(e.reward_card([h[2]]), null, "nothing counts yet")


func test_reward_falls_back_to_enemy_suit() -> void:
	var e := scenario([], ["3S"])
	e.state.deck = cards(e, ["2H", "2D", "2S", "2C"])
	e.state.carry_shield = 5
	e.resolve()  # the stored shield blocks alone
	eq(e.state.reward.get("suit"), "S", "enemy suit when no card counted")


func test_sacrificed_ace_sets_reward() -> void:
	var e := scenario(["2C"], ["3H"])
	e.state.deck = cards(e, ["2H", "2D", "2S", "2C"])
	var ace = null
	for a in e.sacrificable_aces():
		if a.base_black():
			ace = a
	check(ace != null, "two of the three life aces are never both red")
	check(e.sacrifice_ace(ace.id), "sacrificed")
	e.resolve()
	eq(e.state.reward.get("suit"), ace.suit, "ace suit")


func test_spade_reward_all_options() -> void:
	var e := _clear_with("3S", ["2H", "2D", "2S", "2C"], {}, ["3H", "3D"])
	eq(e.state.phase, Phase.REWARD, "phase")
	eq(e.state.reward["options"].size(), 3, "all beaten cards offered")
	eq(int(e.state.reward["picks"]), 1, "one pick")


func test_diamond_reward_takes_two() -> void:
	var e := _clear_with("3D", ["2H", "2D", "2S"], {"deck_cap": 9}, ["3H", "3S"])
	eq(int(e.state.reward["picks"]), 2, "two picks")
	var opts: Array = e.state.reward["options"]
	e.reward_take(opts[0].id)
	eq(e.state.phase, Phase.REWARD, "still picking")
	e.reward_take(opts[0].id)
	eq(e.state.deck.size(), 5, "deck grew by two")


func test_heart_reward_heals() -> void:
	var e := _clear_with("3H", ["2H", "2D", "2S", "2C"], {}, ["3S"])
	# full lives -> reveal 2 take 1
	eq(e.state.phase, Phase.REWARD, "pick when lives full")
	var e2 := scenario([], ["3S"])
	e2.state.lost_lives.append(e2.state.lives.pop_back())
	e2.state.hand = cards(e2, ["14H"])
	e2.play_cards([e2.state.hand[0].id])
	e2.resolve()
	eq(e2.state.lives.size(), 3, "healed")
	check(has_event(e2, Ev.LIFE_RESTORED), "restored event")


func test_club_reward_take_then_remove() -> void:
	var e := _clear_with("3C", ["2H", "2D", "2S", "2C"], {}, ["3H"])
	var opts: Array = e.state.reward["options"]
	eq(opts.size(), 2, "reveal 2")
	e.reward_take(opts[0].id)
	eq(e.state.phase, Phase.REWARD_REMOVE, "must remove")
	check(e.reward_remove(e.state.deck[0].id), "removed")
	eq(e.state.deck.size(), 4, "back to 4")


func test_deck_min_blocks_removal() -> void:
	var e := _clear_with("3C", ["2H", "2D", "2S", "2C"], {"deck_min": 5}, ["3H"])
	e.reward_take(e.state.reward["options"][0].id)
	# deck is 5 = deck_min, so no removal step
	check(e.state.phase != Phase.REWARD_REMOVE, "no removal at deck_min")


func test_decline_only_when_full() -> void:
	var e := _clear_with("3S", ["2H", "2D", "2S", "2C"], {"deck_cap": 9, "reward_optional": false}, ["3H"])
	check(not e.reward_skip(), "cannot decline below cap")
	var g := _clear_with("3S", ["2H", "2D", "2S", "2C"], {"deck_cap": 0, "reward_optional": true}, ["3H"])
	check(not g.deck_full(), "no cap: never full")
	check(g.reward_skip(), "optional rewards: may decline")
	var f := _clear_with("3S", ["2H", "2D", "2S", "2C", "3D"], {"deck_cap": 5}, ["3H"])
	check(f.reward_skip(), "can decline at cap")


func test_deck_cap_requires_swap() -> void:
	var e := _clear_with("3S", ["2H", "2D", "2S", "2C", "3D"], {"deck_cap": 5}, ["3H"])
	var opt = e.state.reward["options"][0]
	check(e.deck_full(), "deck full")
	check(not e.reward_take(opt.id), "needs a swap target")
	var out = e.state.deck[0]
	check(e.reward_take(opt.id, out.id), "swap")
	eq(e.state.deck.size(), 5, "size unchanged")
	check(not e.state.deck.has(out), "swapped out")


func test_red_joker_after_jack_floor() -> void:
	var e := scenario([], ["11S"], {}, {"force_theme": "S"})
	e.state.floor_num = 11
	e.state.hand = cards(e, ["14H"])
	e.state.deck = cards(e, ["2H", "2D", "2S", "2C"])
	e.play_cards([e.state.hand[0].id])
	e.resolve()
	e.reward_take(e.state.reward["options"][0].id)
	eq(e.state.phase, Phase.JOKER_ATTACH, "joker offered")
	var target = e.state.deck[0]
	e.attach_joker(target.id)
	eq(target.joker, "double", "spade theme = double")
	eq(target.value(), 4, "2 doubled")
	eq(e.state.floor_num, 12, "next floor")


func test_reward_resolve_clubs_take_and_remove_at_once() -> void:
	var e := _clear_with("3C", ["2H", "2D", "2S", "2C"], {"deck_cap": 0}, ["3H"])
	var opt = e.state.reward["options"][0]
	var old = e.state.deck[0]
	check(e.removal_needed(1), "clubs: removal needed after taking one")
	check(not e.reward_resolve([opt.id]), "removal missing")
	check(e.reward_resolve([opt.id], old.id), "take + remove in one action")
	check(e.state.deck.has(opt), "taken")
	check(not e.state.deck.has(old), "removed")
	check(e.state.phase != Phase.REWARD and e.state.phase != Phase.REWARD_REMOVE, "reward finished")


func test_reward_resolve_diamonds_both_at_once() -> void:
	var e := _clear_with("3D", ["2H", "2D", "2S"], {"deck_cap": 0}, ["3H", "3S"])
	var ids: Array = e.state.reward["options"].map(func(c): return c.id)
	check(e.reward_resolve(ids), "take both")
	eq(e.state.deck.size(), 5, "deck grew by two")
