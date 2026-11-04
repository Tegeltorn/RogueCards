extends "res://tests/test_base.gd"
## Rewards decided by the suit of the last beaten enemy card.


## Beat a single enemy card as the last card of floor 3 to trigger the reward.
func _clear_with(last: String, deck: Array, over: Dictionary = {}, beaten_before: Array = []) -> GameEngine:
	var e := scenario([], [last], over)
	var s := e.state
	s.deck = cards(e, deck)
	s.beaten = cards(e, beaten_before)
	var red := last.right(1) in ["H", "D"]
	s.hand = cards(e, ["14S" if red else "14H"])
	e.play_cards([s.hand[0].id])
	e.resolve()
	return e


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
	var e2 := scenario([], ["3H"])
	e2.state.lost_lives.append(e2.state.lives.pop_back())
	e2.state.hand = cards(e2, ["14S"])
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
