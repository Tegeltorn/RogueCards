extends "res://tests/test_base.gd"
## Prototype deck-building rules behind balance keys: club swarm, lone spade, heart wall,
## hand size from deck size, reward menu and the two-suit reward choice.

const Bot := preload("res://engine/bot.gd")


func test_club_swarm() -> void:
	var e := scenario(["2C", "3C", "4C"], ["20H"], {"club_mode": "swarm", "club_swarm_bonus": 2})
	var h: Array = e.state.hand
	eq(int(e.compute([h[0]])["attack"]), 2, "one club: no bonus")
	eq(int(e.compute([h[0], h[1]])["attack"]), 9, "two clubs: +2 each")
	eq(int(e.compute(h)["attack"]), 15, "three clubs: +2 each")


func test_lone_spade() -> void:
	var e := scenario(["5S", "3C"], ["20H"], {"spade_mode": "lone", "spade_lone_mult": 2})
	var h: Array = e.state.hand
	eq(int(e.compute([h[0]])["attack"]), 10, "a spade alone counts double")
	eq(int(e.compute(h)["attack"]), 8, "with another attack card: just its rank")


func test_heart_wall_stacks_to_floor_rank() -> void:
	var e := scenario(["3H"], ["4D"], {"heart_mode": "wall"})
	e.state.floor_num = 6
	e.state.carry_shield = 2
	e.play_cards(ids(e.state.hand))
	e.resolve()
	eq(e.state.carry_shield, 5, "hearts against a shield add to the wall")
	set_round_keep(e, ["5H"], ["9H"])
	e.play_cards(ids(e.state.hand))
	e.resolve()
	eq(e.state.carry_shield, 6, "capped at the floor's rank")
	set_round_keep(e, [], ["9D"])
	e.resolve()
	eq(e.state.carry_shield, 6, "the wall stays through a round without hearts")
	set_round_keep(e, ["2D"], ["4S"])
	e.play_cards(ids(e.state.hand))
	e.resolve()
	eq(e.state.carry_shield, 4, "a block uses only what it needs")


func set_round_keep(e: GameEngine, hand: Array, enemies: Array) -> void:
	var carry := e.state.carry_shield
	var f := e.state.floor_num
	set_round(e, hand, enemies, ["9C"])
	e.state.carry_shield = carry
	e.state.floor_num = f


func test_hand_grows_with_deck() -> void:
	var e := scenario([], ["5S"], {"hand_per_deck": 4, "hand_size": 3})
	e.state.deck = cards(e, ["2H", "2D", "2S", "2C", "3H", "3D", "3S", "3C", "4H", "4D", "4S", "4C"])
	eq(e.hand_limit(), 3, "12 cards / 4 = 3")
	e.state.deck.append(card(e, "5H"))
	e.state.deck.append(card(e, "5D"))
	e.state.deck.append(card(e, "5S"))
	e.state.deck.append(card(e, "5C"))
	eq(e.hand_limit(), 4, "16 cards / 4 = 4")


func _clear_floor(over: Dictionary) -> GameEngine:
	var e := scenario(["9H"], ["3S"], over)
	e.state.deck = cards(e, ["2H", "2D", "2S", "2C", "3H", "3D"])
	e.state.beaten = cards(e, ["3H", "3D", "3C"])
	e.play_cards(ids(e.state.hand))
	e.resolve()
	return e


func test_reward_menu() -> void:
	var over := {"reward_mode": "menu", "menu_take": 1, "menu_cull": 2, "deck_min": 6}
	var e := _clear_floor(over)
	eq(e.state.phase, Phase.REWARD, "menu offered")
	eq(e.state.reward["options"].size(), 4, "all beaten cards are on offer")
	check(not e.menu_can("cull"), "no cull at the deck minimum")
	check(not e.menu_can("heal"), "no heal with all lives")
	var opts: Array = e.state.reward["options"]
	check(not e.reward_menu("take", [opts[0].id, opts[1].id]), "take is limited to menu_take")
	check(e.reward_menu("trade", [opts[0].id], [e.state.deck[0].id]), "trade")
	eq(e.state.deck.size(), 6, "trade keeps the deck size")
	eq(e.state.floor_num, 5, "next floor")
	var e2 := _clear_floor(over)
	e2.state.lost_lives.append(e2.state.lives.pop_back())
	check(e2.reward_menu("heal"), "heal")
	eq(e2.state.lives.size(), 3, "life back")


func test_reward_choice_between_two_suits() -> void:
	var e := _clear_floor({"reward_mode": "choice"})
	eq(e.state.phase, Phase.REWARD, "choice offered")
	eq(e.state.reward["choose"], ["H", "S"], "finishing suit or enemy suit")
	check(not e.reward_suit("D"), "only the two suits")
	check(e.reward_suit("S"), "choose spades")
	eq(e.state.reward["suit"], "S", "spade reward: pick any")
	eq(e.state.reward["options"].size(), 4, "all beaten cards")


func test_variant_runs_replay() -> void:
	for over in [{"reward_mode": "menu", "menu_take": 1, "deck_min": 6, "club_mode": "swarm", "hand_per_deck": 4},
			{"reward_mode": "choice", "heart_mode": "wall", "spade_mode": "lone"}]:
		var e := GameEngine.new()
		e.start_run(17, classic(over))
		var bot := Bot.new()
		var steps := 0
		while e.state.result == "" and steps < 400:
			bot.step(e)
			steps += 1
		var copy := GameEngine.new()
		check(copy.restore(e.snapshot()), "variant run replays")
		eq(copy.fingerprint(), e.fingerprint(), "variant fingerprint")
