extends RefCounted
## The rules engine. Pure logic: no nodes, no UI. All state lives in `state` (GameState).
## Every change is reported as an event dictionary {type, ...}; the UI replays them in order.

signal event_emitted(ev: Dictionary)

const Card := preload("res://engine/card.gd")
const Rng := preload("res://engine/rng.gd")
const GameState := preload("res://engine/game_state.gd")
const Balance := preload("res://engine/balance.gd")
const Ev := preload("res://engine/events.gd")
const ModBase := preload("res://engine/mods/mod_base.gd")
const MOD_SCRIPTS := {
	"hardened": preload("res://engine/mods/hardened.gd"),
	"rich": preload("res://engine/mods/rich.gd"),
	"bloodthirst": preload("res://engine/mods/bloodthirst.gd"),
	"foresight": preload("res://engine/mods/foresight.gd"),
}
const Phase := GameState.Phase

var state: GameState
var rng: Rng
var mod: ModBase
var record_events := true  # the simulator turns this off for speed
var _excluded: Dictionary = {}  # rank -> Array of suits taken by the start pick (removed from that floor)
## Every player action taken this run, as [name, args]. With the seed this rebuilds the run exactly
## (the engine is deterministic), so the UI can save a run and resume it after a reload.
var journal: Array = []
var _start: Dictionary = {}
var _depth := 0  # > 0 while an action runs (actions calling actions are not journaled twice)

const SAVE_VERSION := 4


# ---------------------------------------------------------------- setup

## options: force_mod ("H".."C"), start_floor (int)
func start_run(p_seed: int, balance: Dictionary = {}, options: Dictionary = {}) -> void:
	state = GameState.new()
	rng = Rng.new(p_seed)
	journal = []
	_depth = 0
	_start = {"seed": p_seed, "balance": balance.duplicate(true), "options": options.duplicate(true)}
	_excluded = {}
	state.seed_value = p_seed
	state.balance = Balance.normalise(balance.duplicate(true)) if not balance.is_empty() else Balance.make()
	var b := state.balance
	_emit(Ev.RUN_STARTED, {"seed": p_seed})

	# Mod ace: shuffle the four aces, draw one. The other aces are lives.
	var aces: Array = []
	for s in Card.SUITS:
		aces.append(_new_card(14, s))
	rng.shuffle(aces)
	_force_front(aces, options.get("force_mod", ""))
	state.mod_ace = aces.pop_front()
	state.mod_suit = state.mod_ace.suit
	state.lives = aces.slice(0, int(b["lives"]))
	if state.lives.size() < int(b["lives"]) and not b["mods_enabled"]:
		state.lives.append(state.mod_ace)  # no mods: the fourth ace is a life too
	state.max_lives = state.lives.size()

	# Mod.
	var mdata: Dictionary = Balance.mods().get(state.mod_suit, {})
	if b["mods_enabled"] and MOD_SCRIPTS.has(mdata.get("id", "")):
		mod = MOD_SCRIPTS[mdata["id"]].new()
	else:
		mod = ModBase.new()
	if b["mods_enabled"]:
		mod.setup(state.mod_suit, mdata)
		if mod.mod_ace_is_life():
			state.lives.append(state.mod_ace)
			state.max_lives = state.lives.size()

	# Starting deck: the four twos.
	for s in Card.SUITS:
		state.deck.append(_new_card(2, s))

	_emit(Ev.MOD_REVEALED, {"suit": state.mod_suit, "name": mod.name, "desc": mod.desc, "active": b["mods_enabled"]})

	state.floor_num = int(options.get("start_floor", first_floor()))
	# Random start cards: `start_random` cards of `start_pick_rank` (the threes), dealt at random.
	var pick_rank := int(b.get("start_pick_rank", 0))
	var extra := clampi(int(b.get("start_random", 0)), 0, 4)
	if pick_rank > 0 and extra > 0:
		var threes: Array = []
		for s in Card.SUITS:
			threes.append(_new_card(pick_rank, s))
		rng.shuffle(threes)
		for c in threes.slice(0, extra):
			state.deck.append(c)
			_excluded[c.rank] = _excluded.get(c.rank, []) + [c.suit]
			_emit(Ev.SETUP_PICKED, {"card": c.label(), "id": c.id})
	# Optional start pick: reveal `start_pick_offer` cards of `start_pick_rank` and keep some of them.
	var picks := mod.modify_start_picks(int(b.get("start_pick_take", 0)))
	if pick_rank > 0 and picks > 0:
		var pool: Array = []
		for s in Card.SUITS:
			pool.append(_new_card(pick_rank, s))
		rng.shuffle(pool)
		state.setup_options = pool.slice(0, clampi(int(b.get("start_pick_offer", 4)), 1, 4))
		state.setup_picks = mini(picks, state.setup_options.size())
		state.phase = Phase.SETUP_PICK
		_emit(Ev.SETUP_PICK, {"options": _labels(state.setup_options), "picks": state.setup_picks})
	else:
		state.phase = Phase.REVEAL


func first_floor() -> int:
	return clampi(int(state.balance.get("first_floor", GameState.FIRST_FLOOR)), 3, GameState.BOSS_FLOOR)


func setup_pick(card_id: int) -> bool:
	return _act("setup_pick", [card_id])


func _do_setup_pick(card_id: int) -> bool:
	if state.phase != Phase.SETUP_PICK:
		return false
	var c = state.find_in(state.setup_options, card_id)
	if c == null:
		return false
	state.deck.append(c)
	_excluded[c.rank] = _excluded.get(c.rank, []) + [c.suit]
	state.setup_options.erase(c)
	state.setup_picks -= 1
	_emit(Ev.SETUP_PICKED, {"card": c.label(), "id": c.id})
	if state.setup_picks <= 0 or state.setup_options.is_empty():
		state.setup_options.clear()
		state.phase = Phase.REVEAL
	return true


func ack_reveal() -> bool:
	return _act("ack_reveal", [])


func _do_ack_reveal() -> bool:
	if state.phase != Phase.REVEAL:
		return false
	_start_floor(state.floor_num)
	return true


# ---------------------------------------------------------------- floors & rounds

func _start_floor(f: int) -> void:
	state.floor_num = f
	state.floor_round = 0
	state.beaten = []
	state.current = []
	state.last_beaten = null
	state.last_used = null
	# Every floor is the four cards of its rank (the kings last), minus any taken by the start pick.
	state.floor_num = mini(f, GameState.BOSS_FLOOR)
	var cards: Array = []
	var removed: Array = _excluded.get(state.floor_num, [])
	for s in Card.SUITS:
		if not removed.has(s):
			cards.append(_new_card(state.floor_num, s))
	rng.shuffle(cards)
	state.enemy_pile = cards
	# Piles reset every floor: the whole deck is shuffled into a new draw pile.
	state.draw_pile = state.deck.duplicate()
	rng.shuffle(state.draw_pile)
	state.discard = []
	state.hand = []
	state.played = []
	state.retained = []
	state.carry_shield = 0
	state.skip_refill = false
	_emit(Ev.FLOOR_STARTED, {"floor": state.floor_num, "count": state.enemy_pile.size()})
	_next_round()


func _next_round() -> void:
	state.current = []
	while state.current.is_empty():
		if state.enemy_pile.is_empty():
			_floor_cleared()
			return
		state.current = [state.enemy_pile.pop_front()]
	state.round_num += 1
	state.floor_round += 1
	for c in state.current:
		_emit(Ev.ENEMY_REVEALED, {"card": c.label(), "id": c.id, "rank": c.rank, "suit": c.suit,
			"intent": "attack" if c.base_black() else "shield", "value": enemy_value(c),
			"left": state.enemy_pile.size(), "total_left": state.enemy_pile.size() + state.current.size()})
	# Fill the hand. With keep_hand, unplayed cards simply stay; otherwise only the retained ones.
	state.overpowered = false
	state.burns_this_round = 0
	state.diamond_draws = 0
	if not keep_hand():
		state.hand = state.retained
	state.retained = []
	# The face cards (Jack, Queen, King floors) demand tribute: a smaller hand.
	var limit := hand_limit()
	# Draw up to the hand size, but always at least `min_draw` cards. With `draw_per_turn` > 0 the
	# floor's first hand is drawn up to the hand size, every later round draws that many cards.
	var to_draw := maxi(limit - state.hand.size(), int(state.balance.get("min_draw", 0))) + state.bonus_draw
	var per_turn := int(state.balance.get("draw_per_turn", 0))
	if per_turn > 0 and state.floor_round > 1:
		to_draw = per_turn + state.bonus_draw
	state.bonus_draw = 0
	if state.skip_refill:
		# You burned last round: no new cards this time.
		state.skip_refill = false
		to_draw = 0
		_emit(Ev.REFILL_SKIPPED, {"hand": state.hand.size()})
	# Start of turn: only an empty draw pile is refilled from the shuffled discard pile. A short draw
	# pile is not topped up: you draw what is there.
	if to_draw > 0 and state.draw_pile.is_empty() and not state.discard.is_empty():
		_reshuffle()
	for i in to_draw:
		var d = _draw_one()
		if d == null and continuous_refill() and not state.discard.is_empty():
			_reshuffle()  # `refill_mode` continuous: draw the rest, shuffle, keep drawing
			d = _draw_one()
		if d == null:
			break
		state.hand.append(d)
	if str(state.balance.get("redraw_scope", "round")) != "floor" or state.floor_round == 1:
		state.redraws_this_round = 0  # `redraw_scope`: the redraw limit counts per round or per floor
	state.phase = Phase.PLAY
	_emit(Ev.HAND_FILLED, {"hand": _labels(state.hand), "ids": _ids(state.hand)})


## Hand size this floor. With `hand_per_deck` > 0 a bigger deck holds a bigger hand:
## at least deck size ÷ hand_per_deck (rounded down).
func hand_limit() -> int:
	# `face_from`: the first floor whose cards demand tribute (a smaller hand); 11 = Jack.
	var face_from := int(state.balance.get("face_from", 11))
	var limit := int(state.balance["face_hand_size"] if state.floor_num >= face_from else state.balance["hand_size"])
	var per := int(state.balance.get("hand_per_deck", 0))
	if per > 0:
		limit = maxi(limit, state.deck.size() / per)
	return limit


## Draws the top card of the draw pile, or null when it is empty. The discard pile is shuffled back
## only at the start of a turn whose draw pile is empty (see _next_round), and at a new floor.
func _draw_one():
	if state.draw_pile.is_empty():
		return null
	return state.draw_pile.pop_back()


## `refill_mode` "continuous": when the draw pile runs out while you fill your hand, shuffle the
## discard pile into a new draw pile and keep drawing ("empty", the default: only at an empty start).
func continuous_refill() -> bool:
	return str(state.balance.get("refill_mode", "empty")) == "continuous"


func _reshuffle() -> void:
	state.draw_pile = state.discard
	state.discard = []
	rng.shuffle(state.draw_pile)
	_emit(Ev.DECK_RESHUFFLED, {"count": state.draw_pile.size()})



# ---------------------------------------------------------------- queries (UI + bot)

func enemy_value(c) -> int:
	if c.base_black():
		return mod.modify_enemy_attack(c.rank)
	return c.rank


func block_need() -> int:
	var n := 0
	for c in state.enemy_attack_cards():
		n += enemy_value(c)
	return n


func attack_need() -> int:
	var n := 0
	for c in state.enemy_shield_cards():
		n += enemy_value(c)
	return n


## Any card in hand may be played (e.g. ♦ on a shield just to draw, ♥ on a shield to store shield).
func can_play_card(c) -> bool:
	return state.phase == Phase.PLAY and state.hand.has(c)


## True if the card counts against the revealed enemy (right colour: red vs attack, black vs shield).
func is_effective(c) -> bool:
	return (block_need() > 0 and c.is_red()) or (attack_need() > 0 and c.is_black())


## Cards in hand that count against the current enemy (used by the bot and for highlighting).
func playable_cards() -> Array:
	var out: Array = []
	for c in state.hand:
		if can_play_card(c) and is_effective(c):
			out.append(c)
	return out



func retain_limit() -> int:
	if keep_hand() and hand_max() > 0:
		return hand_max()
	return mod.modify_retain(int(state.balance["retain"]))


func ace_sac_allowed() -> bool:
	return state.balance["ace_sac_enabled"] and mod.can_ace_sac() and state.phase == Phase.PLAY \
		and state.lives.size() >= 2


## Aces that may be sacrificed right now.
func sacrificable_aces() -> Array:
	var out: Array = []
	if not ace_sac_allowed():
		return out
	for a in state.lives:
		if (a.base_red() and block_need() > 0) or (a.base_black() and attack_need() > 0):
			out.append(a)
	return out


func preview_enemies() -> Array:
	return state.enemy_pile.slice(0, mod.preview_count())


## Value of a burned card: double its rank ("double") or its rank in the other colour ("swap").
## Only the number counts: no suit effects.
func burn_value(c) -> int:
	if burn_mode() == "dig":
		return 0
	return c.rank * (2 if burn_mode() == "double" else 1)


func burn_mode() -> String:
	return str(state.balance.get("burn_mode", "off"))


## Colour a card counts as when played: a burned card in "swap" mode counts as the other colour.
func counts_red(c) -> bool:
	if c.burned and burn_mode() == "swap":
		return c.base_black()
	return c.base_red()


## True when the card adds only its number (sacrificed ace, burned card): no suit effects.
func _plain(c) -> bool:
	return c.burned or (c.temp and not state.balance["ace_sac_suit_effects"])


func _block_val(c) -> int:
	if c.burned:
		return burn_value(c)
	if _plain(c):
		return c.rank
	return c.value()


func _attack_val(c) -> int:
	if c.burned:
		return burn_value(c)
	if _plain(c):
		return c.rank
	if c.suit == "S" and str(state.balance.get("spade_mode", "mult")) == "mult":
		return int(floor(c.value() * float(state.balance["spade_multiplier"])))
	return c.value()


## Attack total of the black cards played this round, with the suit synergies:
## ♣ `club_mode` "pair": +club_pair_bonus with 2+ clubs; "swarm": +club_swarm_bonus per club with 2+ clubs.
## ♠ `spade_mode` "mult": × spade_multiplier each; "lone": a ♠ that is your only attack card counts
## × spade_lone_mult (an integer), otherwise just its rank.
func _black_total(blacks: Array) -> int:
	var b := state.balance
	var atk := 0
	var clubs := 0
	for c in blacks:
		atk += _attack_val(c)
		if c.suit == "C" and not _plain(c):
			clubs += 1
	if clubs >= 2:
		if str(b.get("club_mode", "pair")) == "swarm":
			atk += clubs * int(b.get("club_swarm_bonus", 1))
		else:
			atk += int(b["club_pair_bonus"])
	if str(b.get("spade_mode", "mult")) == "lone" and blacks.size() == 1:
		var c = blacks[0]
		if c.suit == "S" and not _plain(c):
			atk = c.rank * int(b.get("spade_lone_mult", 2))
	return atk


## Totals for a set of played cards (used for the live counter and for resolution).
func compute(cards: Array) -> Dictionary:
	var bneed := block_need()
	var aneed := attack_need()
	var carry := state.carry_shield if bneed > 0 else 0
	var reds: Array = []
	var blacks: Array = []
	for c in cards:
		if counts_red(c):
			reds.append(c)
		else:
			blacks.append(c)
	var block := carry
	var hearts := 0
	for c in reds:
		block += _block_val(c)
		if c.suit == "H" and not _plain(c):
			hearts += _block_val(c)
	var attack := _black_total(blacks)
	if not blacks.is_empty():
		attack = mod.modify_player_attack(attack)
	return {"block": block, "attack": attack, "block_need": bneed, "attack_need": aneed,
		"hearts": hearts, "carry": carry, "carry_all": state.carry_shield, "block_cards": reds, "attack_cards": blacks}


## Attack value of the black cards among `cards` if they overpower the revealed attack, else 0.
func overpower_value(cards: Array) -> int:
	var mult := int(state.balance.get("overpower_multiplier", 2))
	if mult <= 0 or block_need() <= 0 or attack_need() > 0:
		return 0
	var blacks: Array = cards.filter(func(c): return not counts_red(c))
	if blacks.is_empty():
		return 0
	var atk := mod.modify_player_attack(_black_total(blacks))
	return atk if atk >= mult * block_need() else 0


## Reward rules for finishing a floor on `suit` (with the mod applied), for the "last card" tip.
func reward_rules(suit: String) -> Dictionary:
	var r := {"suit": suit, "heal": 0, "picks": 1, "reveal": 2, "remove": false, "all": false}
	if str(state.balance.get("reward_mode", "suit")) == "camp":
		# Camp: the finishing suit doesn't matter. Take 1 of the beaten cards (`camp_reveal` of them
		# revealed, 0 = all), or rest, or trim (see trim()).
		var n := int(state.balance.get("camp_reveal", 0))
		r["all"] = n <= 0
		r["reveal"] = n
		mod.modify_reward(r)
		return r
	match suit:
		"S": r["all"] = true
		"C": r["remove"] = true
		"H": r["heal"] = 1
		"D": r["picks"] = 2
	mod.modify_reward(r)
	return r


## Live preview: already played cards plus the given hand card ids.
func preview(selected_ids: Array) -> Dictionary:
	var cards := state.played.duplicate()
	for id in selected_ids:
		var c = state.find_in(state.hand, id)
		if c != null:
			cards.append(c)
	return compute(cards)


# ---------------------------------------------------------------- actions

## Moves cards from hand to the table. ♦ and draw2 cards draw immediately.
func play_cards(ids: Array) -> bool:
	return _act("play_cards", [ids])


func _do_play_cards(ids: Array) -> bool:
	if state.phase != Phase.PLAY:
		return false
	var cards: Array = []
	for id in ids:
		var c = state.find_in(state.hand, id)
		if c == null or not can_play_card(c) or cards.has(c):
			return false
		cards.append(c)
	if cards.is_empty():
		return true
	for c in cards:
		state.hand.erase(c)
		state.played.append(c)
	_emit(Ev.CARDS_PLAYED, {"cards": _labels(cards), "ids": _ids(cards)})
	var draws := _check_overpower()
	for c in cards:
		if c.suit == "D" and _diamond_draws():
			draws += 1
			state.diamond_draws += 1
	_draw_now(draws)
	return true


## Overpower: black cards worth at least `overpower_multiplier` × the enemy attack (with no shield
## revealed) are discarded at once and you draw 1 card. The enemy still attacks at End turn.
## Counts every black card played against this attack so far; triggers once per round.
## Returns the number of cards to draw.
func _check_overpower() -> int:
	var ov := 0 if state.overpowered else overpower_value(state.played)
	if ov <= 0:
		return 0
	var blacks: Array = state.played.filter(func(c): return not counts_red(c))
	for c in blacks:
		state.played.erase(c)
		if not c.temp and not c.burned:
			state.discard.append(c)
	state.overpowered = true
	_emit(Ev.OVERPOWER, {"attack": ov, "enemy": block_need(), "ids": _ids(blacks), "cards": _labels(blacks)})
	return int(state.balance.get("overpower_draw", 1))


## Whether the next ♦ played draws a card (`diamond_draw`): "always", "block" (only while there is
## an attack to block) or "once" (only the first ♦ each round).
func _diamond_draws() -> bool:
	match str(state.balance.get("diamond_draw", "always")):
		"block":
			return block_need() > 0
		"once":
			return state.diamond_draws == 0
		"off":
			return false
	return true


func _draw_now(n: int) -> void:
	for i in n:
		var d = _draw_one()
		if d == null:
			break
		state.hand.append(d)
		_emit(Ev.CARD_DRAWN, {"card": d.label(), "id": d.id})


## Burn: a card from your hand burns up and leaves your deck for good. This round it counts as
## double its rank in its own colour ("double") or as its rank in the other colour ("swap"),
## with no suit effects. At most `burn_limit` per round (0 = no limit), only while the deck has at
## least `burn_min_deck` cards. With `burn_no_refill`, a round you burned in means no hand refill
## at the start of the next round.
func can_burn(c = null) -> bool:
	if state.phase != Phase.PLAY or burn_mode() == "off":
		return false
	var lim := int(state.balance.get("burn_limit", 0))
	if lim > 0 and state.burns_this_round >= lim:
		return false
	if state.deck.size() < int(state.balance.get("burn_min_deck", 0)):
		return false
	return c == null or state.hand.has(c)


func burn_card(card_id: int) -> bool:
	return _act("burn_card", [card_id])


func _do_burn_card(card_id: int) -> bool:
	var c = state.find_in(state.hand, card_id)
	if c == null or not can_burn(c):
		return false
	state.hand.erase(c)
	state.deck.erase(c)
	if burn_mode() == "dig":
		# Dig: the card goes back in the box and you draw `burn_draw` cards instead (no value).
		c.burned = true
		state.burns_this_round += 1
		state.burned_total += 1
		_emit(Ev.CARD_BURNED, {"card": c.label(), "id": c.id, "value": 0, "colour": "none", "deck": state.deck.size()})
		_draw_now(int(state.balance.get("burn_draw", 2)))
		return true
	c.burned = true
	state.played.append(c)
	state.burns_this_round += 1
	state.burned_total += 1
	if bool(state.balance.get("burn_no_refill", false)):
		state.skip_refill = true
	_emit(Ev.CARD_BURNED, {"card": c.label(), "id": c.id, "value": burn_value(c),
		"colour": "red" if counts_red(c) else "black", "deck": state.deck.size()})
	_draw_now(_check_overpower())
	return true


## Redraw (mulligan): `redraw_limit` times per round or per floor (`redraw_scope`; 0 = off), before
## you play any card, set aside any cards from your hand, draw that many minus `redraw_cost`, then
## discard the set-aside cards.
func can_redraw() -> bool:
	var lim := int(state.balance.get("redraw_limit", 0))
	return state.phase == Phase.PLAY and lim > 0 and state.redraws_this_round < lim and state.played.is_empty()


func redraw(ids: Array) -> bool:
	return _act("redraw", [ids])


func _do_redraw(ids: Array) -> bool:
	if not can_redraw() or ids.is_empty():
		return false
	var cards: Array = []
	for id in ids:
		var c = state.find_in(state.hand, id)
		if c == null or cards.has(c):
			return false
		cards.append(c)
	for c in cards:
		state.hand.erase(c)
		_emit(Ev.CARD_DISCARDED, {"card": c.label(), "id": c.id})
	state.redraws_this_round += 1
	var n := maxi(0, cards.size() - int(state.balance.get("redraw_cost", 0)))
	for i in n:
		if state.draw_pile.is_empty() and continuous_refill() and not state.discard.is_empty():
			_reshuffle()
		var d = _draw_one()
		if d == null:
			break
		state.hand.append(d)
		_emit(Ev.CARD_DRAWN, {"card": d.label(), "id": d.id})
	state.discard.append_array(cards)
	return true


## Free discard: throw an unplayed card on the discard pile (no effect). Only with free_discard on.
func can_discard() -> bool:
	return state.phase == Phase.PLAY and bool(state.balance.get("free_discard", false))


func discard_card(card_id: int) -> bool:
	return _act("discard_card", [card_id])


func _do_discard_card(card_id: int) -> bool:
	if not can_discard():
		return false
	var c = state.find_in(state.hand, card_id)
	if c == null:
		return false
	state.hand.erase(c)
	state.discard.append(c)
	_emit(Ev.CARD_DISCARDED, {"card": c.label(), "id": c.id})
	return true


func sacrifice_ace(ace_id: int) -> bool:
	return _act("sacrifice_ace", [ace_id])


func _do_sacrifice_ace(ace_id: int) -> bool:
	var a = state.find_in(sacrificable_aces(), ace_id)
	if a == null:
		return false
	state.lives.erase(a)
	state.lost_lives.append(a)
	var t = _new_card(int(state.balance["ace_value"]), a.suit)
	t.temp = true
	state.played.append(t)
	_emit(Ev.ACE_SACRIFICED, {"card": a.label(), "id": a.id, "value": t.rank, "temp_id": t.id})
	_emit(Ev.LIFE_LOST, {"card": a.label(), "id": a.id, "lives": state.lives.size(), "cause": "sacrifice"})
	return true


## Ends the play step and resolves the round.
func resolve() -> bool:
	return _act("resolve", [])


func _do_resolve() -> bool:
	if state.phase != Phase.PLAY:
		return false
	var t := compute(state.played)
	var b := state.balance
	var bneed: int = t["block_need"]
	var aneed: int = t["attack_need"]
	if bneed > 0:
		var blk: int = t["block"]
		var new_carry := 0
		if blk >= bneed:
			_emit(Ev.BLOCKED, {"block": blk, "attack": bneed, "exact": blk == bneed})
			if blk == bneed:
				_perfect("block")
			if _heart_wall():
				# Wall: unused stored shield and the hearts' leftover stay stored (up to the cap).
				new_carry = mini(mini(blk - bneed, int(t["hearts"]) + int(t["carry"])), _wall_cap())
			else:
				new_carry = mini(blk - bneed, t["hearts"])
		else:
			var miss := bneed - blk
			var dmg := miss_lives(miss)
			_emit(Ev.DAMAGE_TAKEN, {"block": blk, "attack": bneed, "miss": miss, "lives": dmg})
			if _lose_lives(dmg, "damage"):
				return true
		# An attack you failed to block goes to the bottom of the enemy pile and comes back
		# (when failed_attack_returns is on); a blocked one is beaten.
		var returns := blk < bneed and bool(b.get("failed_attack_returns", false)) and mod.failed_attacks_return()
		for e in state.enemy_attack_cards():
			if returns:
				state.enemy_pile.append(e)
				_emit(Ev.ATTACK_RETURNED, {"id": e.id, "card": e.label()})
			else:
				_beat(e, _last_counting(state.played, t["block_cards"]))
		state.carry_shield = new_carry
		if new_carry > 0:
			_emit(Ev.SHIELD_STORED, {"amount": new_carry})
	elif int(t["hearts"]) > 0:
		# ♥ played with no attack to block: the whole heart value is stored (replaces older shield;
		# a wall adds to it, up to the cap).
		state.carry_shield = int(t["hearts"])
		if _heart_wall():
			state.carry_shield = mini(state.carry_shield + int(t["carry_all"]), _wall_cap())
		_emit(Ev.SHIELD_STORED, {"amount": state.carry_shield})
	elif _heart_wall():
		pass  # a wall keeps its stored shield until an attack uses it
	elif b["heart_carry_mode"] == "next_round":
		state.carry_shield = 0
	if aneed > 0:
		var atk: int = t["attack"]
		var shields := state.enemy_shield_cards()
		if atk >= aneed:
			_emit(Ev.ATTACK_SUCCEEDED, {"attack": atk, "shield": aneed, "exact": atk == aneed})
			if atk == aneed:
				_perfect("attack")
			for e in shields:
				_beat(e, _last_counting(state.played, t["attack_cards"]))
		else:
			# Not broken. `failed_shield`: "return" = it goes to the bottom of the enemy pile and comes
			# back; "wound" = it costs lives like a missed attack and is beaten anyway; "second" = the
			# first time it goes to the bottom turned sideways, a sideways shield that fails is a wound.
			_emit(Ev.ATTACK_FAILED, {"attack": atk, "shield": aneed})
			var mode := failed_shield_mode()
			var wound := mode == "wound"
			if mode == "second":
				for e in shields:
					if e.turned:
						wound = true
			if wound:
				var miss := aneed - atk
				var dmg := miss_lives(miss)
				_emit(Ev.DAMAGE_TAKEN, {"block": atk, "attack": aneed, "miss": miss, "lives": dmg})
				if _lose_lives(dmg, "damage"):
					return true
				for e in shields:
					_beat(e, null)
			else:
				for e in shields:
					e.turned = true
					state.enemy_pile.append(e)
	for c in state.played:
		if not c.temp and not c.burned:
			state.discard.append(c)
	state.played = []
	state.current = []
	if keep_hand():
		# Unplayed cards stay in hand; draw back up to the hand size next round. With `hand_max`,
		# a bigger hand is discarded down to that many (your choice) before the next round.
		if hand_max() > 0 and state.hand.size() > hand_max() and not state.enemy_pile.is_empty():
			state.phase = Phase.RETAIN
			return true
		_next_round()
		return true
	state.phase = Phase.RETAIN
	# Nothing to keep when the floor is over (piles reset at the next floor).
	if retain_limit() <= 0 or state.hand.is_empty() or state.enemy_pile.is_empty():
		retain([])
	return true


## What happens to a shield you fail to break: "return", "wound" or "second" (see _do_resolve).
func failed_shield_mode() -> String:
	return str(state.balance.get("failed_shield", "return"))


## A miss of `graded_threshold` or more costs 2 lives, a smaller one 1 (threshold 0 = always 1).
func graded_threshold() -> int:
	var g := int(state.balance.get("graded_threshold", 0))
	return g if g > 0 else 1 << 20


func miss_lives(miss: int) -> int:
	return 2 if miss >= graded_threshold() else 1


## ♥ `heart_mode` "wall": stored shield lasts until an attack uses it and grows, up to the cap.
func _heart_wall() -> bool:
	return str(state.balance.get("heart_mode", "carry")) == "wall"


## Most shield a wall can store: `heart_wall_cap`, 0 = the floor's rank.
func _wall_cap() -> int:
	var cap := int(state.balance.get("heart_wall_cap", 0))
	return cap if cap > 0 else state.floor_num


## True when unplayed cards stay in hand between rounds (no discard, no keep step).
func keep_hand() -> bool:
	return bool(state.balance.get("keep_hand", false))


func hand_max() -> int:
	return int(state.balance.get("hand_max", 0))


func retain(ids: Array) -> bool:
	return _act("retain", [ids])


func _do_retain(ids: Array) -> bool:
	if state.phase != Phase.RETAIN:
		return false
	if ids.size() > retain_limit():
		return false
	var keep: Array = []
	for id in ids:
		var c = state.find_in(state.hand, id)
		if c == null:
			return false
		keep.append(c)
	for c in state.hand:
		if not keep.has(c):
			state.discard.append(c)
	state.hand = []
	state.retained = keep
	if keep_hand():
		state.hand = keep  # hand_max: discarded down, the rest stays in hand
		state.retained = []
	_emit(Ev.RETAINED, {"cards": _labels(keep), "ids": _ids(keep)})
	_next_round()
	return true


## Perfect block / attack (exactly the enemy value): extra card(s) in the next hand.
func _perfect(kind: String) -> void:
	var n := int(state.balance.get("perfect_draw", 0))
	if n <= 0:
		return
	state.bonus_draw += n
	_emit(Ev.PERFECT, {"kind": kind, "draw": n})


## `by`: the player card that beat it (the last card played that counted), null if none did.
func _beat(e, by = null) -> void:
	state.beaten.append(e)
	state.last_beaten = e
	state.last_used = by
	_emit(Ev.ENEMY_DEFEATED, {"card": e.label(), "id": e.id, "suit": e.suit})


## The last of `played` (in play order) that is in `counted` (the block or attack cards).
static func _last_counting(played: Array, counted: Array):
	for i in range(played.size() - 1, -1, -1):
		if counted.has(played[i]):
			return played[i]
	return null


## The card that would set the reward if `cards` beat the floor's final enemy card now:
## the last one counting for the block (attack card) or the attack (shield card). Null if none.
func reward_card(cards: Array):
	if state.current.is_empty():
		return null
	var t := compute(cards)
	var key := "block_cards"
	if int(t["attack_need"]) > 0 and int(t["attack"]) >= int(t["attack_need"]):
		key = "attack_cards"
	return _last_counting(cards, t[key])


## Returns true if the run ended.
func _lose_lives(n: int, cause: String) -> bool:
	for i in n:
		if state.lives.is_empty():
			break
		var a = state.lives.pop_back()
		state.lost_lives.append(a)
		_emit(Ev.LIFE_LOST, {"card": a.label(), "id": a.id, "lives": state.lives.size(), "cause": cause})
	if state.lives.is_empty():
		state.result = "dead"
		state.phase = Phase.LOST
		_emit(Ev.RUN_LOST, {"floor": state.floor_num})
		return true
	return false


# ---------------------------------------------------------------- rewards

func _floor_cleared() -> void:
	# The reward follows the last player card that counted against the final enemy card
	# (falls back to that enemy card when nothing did, e.g. a stored ♥ shield blocked it alone).
	var last = state.last_used if state.last_used != null else state.last_beaten
	_emit(Ev.FLOOR_CLEARED, {"floor": state.floor_num, "last": last.label() if last else "",
		"suit": last.suit if last else "",
		"enemy": state.last_beaten.label() if state.last_beaten else "", "by_player": state.last_used != null})
	if state.is_boss():
		state.result = "win"
		state.phase = Phase.WON
		_emit(Ev.RUN_WON, {})
		return
	var pool: Array = []
	for c in state.beaten:
		pool.append(_new_card(c.rank, c.suit))
	rng.shuffle(pool)
	var suit: String = last.suit if last and Card.SUITS.has(last.suit) else "S"
	if menu_rewards():
		_offer_menu(pool, suit)
		return
	# `reward_mode` "choice": choose the reward of your finishing card's suit or of the beaten enemy card's suit.
	var esuit: String = state.last_beaten.suit if state.last_beaten else suit
	if str(state.balance.get("reward_mode", "suit")) == "choice" and esuit != suit:
		state.reward = {"choose": [suit, esuit], "pool": pool, "suit": suit, "options": [], "picks": 0}
		state.phase = Phase.REWARD
		_emit(Ev.REWARD_OFFERED, {"suit": suit, "choose": [suit, esuit], "options": [], "ids": [],
			"picks": 0, "remove": false, "healed": 0, "pool": pool.size()})
		return
	_offer_suit_reward(pool, suit)


## Reward choice: take the reward of `suit` (one of the two offered suits).
func reward_suit(suit: String) -> bool:
	return _act("reward_suit", [suit])


func _do_reward_suit(suit: String) -> bool:
	if state.phase != Phase.REWARD or not state.reward.has("choose") or not state.reward["choose"].has(suit):
		return false
	_offer_suit_reward(state.reward["pool"], suit)
	return true


func _offer_suit_reward(pool: Array, suit: String) -> void:
	var r := reward_rules(suit)
	if suit == "H" and (state.lost_lives.is_empty() or not bool(state.balance.get("heart_heal", true))):
		r["heal"] = 0
	var healed := 0
	while healed < int(r["heal"]) and not state.lost_lives.is_empty():
		var a = state.lost_lives.pop_back()
		state.lives.append(a)
		healed += 1
		_emit(Ev.LIFE_RESTORED, {"card": a.label(), "id": a.id, "lives": state.lives.size()})
	if healed > 0:
		r["picks"] = 0
	var options: Array = pool if r["all"] else pool.slice(0, int(r["reveal"]))
	r["picks"] = mini(int(r["picks"]), options.size())
	r["options"] = options
	state.reward = r
	state.phase = Phase.REWARD
	_emit(Ev.REWARD_OFFERED, {"suit": suit, "options": _labels(options), "ids": _ids(options),
		"picks": r["picks"], "remove": r["remove"], "healed": healed, "pool": pool.size()})
	_after_pick()


# ---- reward menu (`reward_mode` "menu"): instead of the finishing suit, choose one of
#   take  - add up to `menu_take` of the floor's beaten cards
#   trade - add up to 1 beaten card and remove 1 card from your deck
#   cull  - remove up to `menu_cull` cards from your deck
#   heal  - get one lost life back

func menu_rewards() -> bool:
	return str(state.balance.get("reward_mode", "suit")) == "menu"


func _offer_menu(pool: Array, suit: String) -> void:
	# `reward_max_rank` > 0: higher cards (the face cards) are never added to your deck.
	var top := int(state.balance.get("reward_max_rank", 0))
	if top > 0:
		pool = pool.filter(func(c): return c.rank <= top)
	var r := {"suit": suit, "menu": true, "heal": 0, "picks": int(state.balance.get("menu_take", 2)),
		"cull": int(state.balance.get("menu_cull", 2)), "remove": false, "all": true, "reveal": pool.size()}
	mod.modify_menu(r)
	r["options"] = pool
	state.reward = r
	state.phase = Phase.REWARD
	_emit(Ev.REWARD_OFFERED, {"suit": suit, "options": _labels(pool), "ids": _ids(pool),
		"picks": r["picks"], "remove": false, "healed": 0, "pool": pool.size(), "menu": true})


func menu_can(kind: String) -> bool:
	if state.phase != Phase.REWARD or not state.reward.get("menu", false):
		return false
	match kind:
		"take", "trade":
			return not state.reward.get("options", []).is_empty()
		"cull":
			return state.deck.size() > int(state.balance["deck_min"])
		"heal":
			return not state.lost_lives.is_empty()
	return false


func reward_menu(kind: String, take_ids: Array = [], remove_ids: Array = []) -> bool:
	return _act("reward_menu", [kind, take_ids, remove_ids])


func _do_reward_menu(kind: String, take_ids: Array = [], remove_ids: Array = []) -> bool:
	if not menu_can(kind):
		return false
	var r: Dictionary = state.reward
	var opts: Array = r["options"]
	var max_take := 0
	var max_remove := 0
	match kind:
		"take":
			max_take = int(r["picks"])
		"trade":
			max_take = 1
			max_remove = 1
		"cull":
			max_remove = int(r["cull"])
	var takes: Array = []
	for id in take_ids:
		var c = state.find_in(opts, id)
		if c == null or takes.has(c):
			return false
		takes.append(c)
	var rems: Array = []
	for id in remove_ids:
		var c = state.find_in(state.deck, id)
		if c == null or rems.has(c):
			return false
		rems.append(c)
	if takes.size() > max_take or rems.size() > max_remove:
		return false
	if not rems.is_empty() and state.deck.size() + takes.size() - rems.size() < int(state.balance["deck_min"]):
		return false
	if kind == "heal":
		var a = state.lost_lives.pop_back()
		state.lives.append(a)
		_emit(Ev.LIFE_RESTORED, {"card": a.label(), "id": a.id, "lives": state.lives.size()})
	for c in takes:
		state.deck.append(c)
		opts.erase(c)
		_emit(Ev.REWARD_TAKEN, {"card": c.label(), "id": c.id, "replaced": "", "replaced_id": -1})
	for c in rems:
		state.deck.erase(c)
		_emit(Ev.CARD_REMOVED, {"card": c.label(), "id": c.id})
	if takes.is_empty() and kind != "heal":
		_emit(Ev.REWARD_SKIPPED, {})
	_finish_reward()
	return true


## deck_cap 0 = no cap.
func deck_full() -> bool:
	var cap := int(state.balance["deck_cap"])
	return cap > 0 and state.deck.size() >= cap


## Take a reward option. When the deck is full, `replace_id` names the deck card to swap out.
func reward_take(option_id: int, replace_id: int = -1) -> bool:
	return _act("reward_take", [option_id, replace_id])


func _do_reward_take(option_id: int, replace_id: int = -1) -> bool:
	if state.phase != Phase.REWARD:
		return false
	var opts: Array = state.reward["options"]
	var c = state.find_in(opts, option_id)
	if c == null:
		return false
	var replaced = null
	if deck_full():
		replaced = state.find_in(state.deck, replace_id)
		if replaced == null:
			return false
		state.deck.erase(replaced)
	state.deck.append(c)
	opts.erase(c)
	state.reward["picks"] = int(state.reward["picks"]) - 1
	_emit(Ev.REWARD_TAKEN, {"card": c.label(), "id": c.id, "replaced": replaced.label() if replaced else "",
		"replaced_id": replaced.id if replaced else -1})
	_after_pick()
	return true


## Declining is only allowed when the deck is full (spec: swap or decline).
func can_decline() -> bool:
	return deck_full() or bool(state.balance.get("reward_optional", false))


## Decline the rest of the reward.
func reward_skip() -> bool:
	return _act("reward_skip", [])


func _do_reward_skip() -> bool:
	if state.phase != Phase.REWARD or not can_decline():
		return false
	state.reward["picks"] = 0
	_emit(Ev.REWARD_SKIPPED, {})
	_after_pick()
	return true


## Decline a single option (uses up one pick), e.g. one of the two ♦ cards.
func reward_decline(option_id: int) -> bool:
	return _act("reward_decline", [option_id])


func _do_reward_decline(option_id: int) -> bool:
	if state.phase != Phase.REWARD or not can_decline():
		return false
	var c = state.find_in(state.reward["options"], option_id)
	if c == null:
		return false
	state.reward["options"].erase(c)
	state.reward["picks"] = int(state.reward["picks"]) - 1
	_emit(Ev.REWARD_SKIPPED, {"card": c.label()})
	_after_pick()
	return true


## The whole reward as one action: take `take_ids` (when the deck is full, `replace_ids[i]` is swapped out
## for `take_ids[i]`), decline the other picks, and for ♣ remove `remove_id` from the deck (an old card).
func reward_resolve(take_ids: Array, remove_id: int = -1, replace_ids: Array = []) -> bool:
	return _act("reward_resolve", [take_ids, remove_id, replace_ids])


func _do_reward_resolve(take_ids: Array, remove_id: int = -1, replace_ids: Array = []) -> bool:
	if state.phase != Phase.REWARD:
		return false
	if state.reward.has("choose"):
		return false  # choose the suit first (reward_suit)
	if state.reward.get("menu", false):
		return _do_reward_menu("take" if remove_id < 0 else "trade", take_ids, [] if remove_id < 0 else [remove_id])
	var r: Dictionary = state.reward
	var opts: Array = r["options"]
	var picks := mini(int(r["picks"]), opts.size())
	var takes: Array = []
	for id in take_ids:
		var c = state.find_in(opts, id)
		if c == null or takes.has(c):
			return false
		takes.append(c)
	if takes.size() > picks or (takes.size() < picks and not can_decline()):
		return false
	var replaced: Array = []
	var size := state.deck.size()
	var cap := int(state.balance["deck_cap"])
	for i in takes.size():
		if cap > 0 and size >= cap:
			var rep = state.find_in(state.deck, int(replace_ids[i]) if i < replace_ids.size() else -1)
			if rep == null or replaced.has(rep):
				return false
			replaced.append(rep)
		else:
			replaced.append(null)
			size += 1
	var need_remove: bool = r.get("remove", false) and size > int(state.balance["deck_min"])
	var removed = null
	if need_remove:
		removed = state.find_in(state.deck, remove_id)
		if removed == null or replaced.has(removed):
			return false
	for i in takes.size():
		var c = takes[i]
		var rep = replaced[i]
		if rep != null:
			state.deck.erase(rep)
		state.deck.append(c)
		opts.erase(c)
		_emit(Ev.REWARD_TAKEN, {"card": c.label(), "id": c.id, "replaced": rep.label() if rep else "",
			"replaced_id": rep.id if rep else -1})
	if takes.size() < picks:
		_emit(Ev.REWARD_SKIPPED, {})
	if removed != null:
		state.deck.erase(removed)
		_emit(Ev.CARD_REMOVED, {"card": removed.label(), "id": removed.id})
	_finish_reward()
	return true


## Rest (`rest_heal`): instead of the floor's reward, get one lost life back.
func can_rest() -> bool:
	return bool(state.balance.get("rest_heal", false)) and not state.lost_lives.is_empty() \
		and (state.phase == Phase.REWARD or state.phase == Phase.REWARD_REMOVE)


func rest() -> bool:
	return _act("rest", [])


func _do_rest() -> bool:
	if not can_rest():
		return false
	var a = state.lost_lives.pop_back()
	state.lives.append(a)
	_emit(Ev.LIFE_RESTORED, {"card": a.label(), "id": a.id, "lives": state.lives.size()})
	state.reward["picks"] = 0
	_emit(Ev.REWARD_SKIPPED, {})
	_finish_reward()
	return true


## Trim (`reward_mode` "camp"): instead of the floor's reward, remove a card from your deck for good.
func can_trim() -> bool:
	return str(state.balance.get("reward_mode", "suit")) == "camp" and state.phase == Phase.REWARD \
		and state.deck.size() > int(state.balance["deck_min"])


func trim(card_id: int) -> bool:
	return _act("trim", [card_id])


func _do_trim(card_id: int) -> bool:
	if not can_trim():
		return false
	var c = state.find_in(state.deck, card_id)
	if c == null:
		return false
	state.deck.erase(c)
	_emit(Ev.CARD_REMOVED, {"card": c.label(), "id": c.id})
	state.reward["picks"] = 0
	_finish_reward()
	return true


## True when the ♣ reward still requires removing a card after taking `n_takes` cards.
func removal_needed(n_takes: int) -> bool:
	if state.phase != Phase.REWARD or not state.reward.get("remove", false):
		return false
	var size := state.deck.size() + (0 if deck_full() else n_takes)
	return size > int(state.balance["deck_min"])


func reward_remove(card_id: int) -> bool:
	return _act("reward_remove", [card_id])


func _do_reward_remove(card_id: int) -> bool:
	if state.phase != Phase.REWARD_REMOVE:
		return false
	var c = state.find_in(state.deck, card_id)
	if c == null or state.deck.size() <= int(state.balance["deck_min"]):
		return false
	state.deck.erase(c)
	_emit(Ev.CARD_REMOVED, {"card": c.label(), "id": c.id})
	_finish_reward()
	return true


func _after_pick() -> void:
	if int(state.reward["picks"]) > 0 and not state.reward["options"].is_empty():
		return
	if state.reward.get("remove", false) and state.deck.size() > int(state.balance["deck_min"]):
		state.phase = Phase.REWARD_REMOVE
		return
	_finish_reward()


func _finish_reward() -> void:
	state.reward = {}
	_start_floor(state.floor_num + 1)


# ---------------------------------------------------------------- debug

func debug_jump_to_floor(f: int) -> void:
	_act("debug_jump_to_floor", [f])


func _do_debug_jump_to_floor(f: int) -> void:
	_emit(Ev.DEBUG, {"msg": "jumping to floor %d" % f})
	state.reward = {}
	_start_floor(clampi(f, first_floor(), GameState.BOSS_FLOOR))


func debug_give_life() -> void:
	_act("debug_give_life", [])


func _do_debug_give_life() -> void:
	if not state.lost_lives.is_empty():
		var a = state.lost_lives.pop_back()
		state.lives.append(a)
		_emit(Ev.LIFE_RESTORED, {"card": a.label(), "id": a.id, "lives": state.lives.size()})
	else:
		_emit(Ev.DEBUG, {"msg": "no lost lives to restore"})


# ---------------------------------------------------------------- save & resume

## Runs action `name` (the body is `_do_<name>`) and journals it when it succeeded.
func _act(name: String, args: Array) -> bool:
	_depth += 1
	var r = callv("_do_" + name, args)
	_depth -= 1
	var ok := r == null or bool(r)  # debug actions return nothing
	if ok and _depth == 0:
		journal.append([name, args.duplicate(true)])
	return ok


## Everything needed to rebuild this run: start arguments, the action journal and a check value.
func snapshot() -> Dictionary:
	return {"version": SAVE_VERSION, "seed": _start.get("seed", 0), "balance": _start.get("balance", {}),
		"options": _start.get("options", {}), "journal": journal.duplicate(true), "check": fingerprint()}


## Rebuilds a run from snapshot() by replaying it. False (and the engine is unusable) when the
## snapshot doesn't replay to the same state, e.g. after a rules change.
func restore(snap: Dictionary) -> bool:
	if int(snap.get("version", 0)) != SAVE_VERSION or typeof(snap.get("journal")) != TYPE_ARRAY \
			or typeof(snap.get("balance")) != TYPE_DICTIONARY or typeof(snap.get("options")) != TYPE_DICTIONARY:
		return false
	start_run(int(snap.get("seed", 0)), snap.get("balance", {}), snap.get("options", {}))
	for step in snap["journal"]:
		if typeof(step) != TYPE_ARRAY or step.size() != 2 or typeof(step[1]) != TYPE_ARRAY:
			return false
		if not has_method("_do_" + str(step[0])) or not _act(str(step[0]), step[1]):
			return false
	return fingerprint() == str(snap.get("check", ""))


## A short summary of the state, to verify a replayed run.
func fingerprint() -> String:
	var s := state
	return "%d|%d|%d|%d|%d|%s|%s|%s|%s" % [s.phase, s.floor_num, s.round_num, s.next_id, s.lives.size(),
		str(_ids(s.hand)), str(_ids(s.deck)), str(_ids(s.current)), str(_ids(s.draw_pile))]


# ---------------------------------------------------------------- helpers

func _new_card(rank: int, suit: String):
	var c = Card.new(state.next_id, rank, suit)
	state.next_id += 1
	return c


func _force_front(arr: Array, suit: String) -> void:
	if suit == "":
		return
	for i in arr.size():
		if arr[i].suit == suit:
			var c = arr[i]
			arr.remove_at(i)
			arr.push_front(c)
			return


func _emit(type: String, data: Dictionary) -> void:
	if not record_events:
		return
	data["type"] = type
	state.events.append(data)
	event_emitted.emit(data)


static func _labels(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c.describe())
	return out


static func _ids(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c.id)
	return out
