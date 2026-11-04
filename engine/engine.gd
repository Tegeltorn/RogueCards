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
var _excluded: Dictionary = {}  # rank -> Array of suits removed from enemy floors (Rich mod)
var _boss_pile: Array = []


# ---------------------------------------------------------------- setup

## options: force_mod ("H".."C"), force_theme ("H".."C"), start_floor (int)
func start_run(p_seed: int, balance: Dictionary = {}, options: Dictionary = {}) -> void:
	state = GameState.new()
	rng = Rng.new(p_seed)
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
	state.max_lives = state.lives.size()

	# Theme king.
	var kings: Array = []
	for s in Card.SUITS:
		kings.append(_new_card(13, s))
	rng.shuffle(kings)
	_force_front(kings, options.get("force_theme", ""))
	state.theme_king = kings.pop_front()
	state.theme_suit = state.theme_king.suit
	_boss_pile = kings
	var jdata: Dictionary = Balance.jokers().get(state.theme_suit, {})
	if b["jokers_enabled"]:
		_boss_pile.append(_new_card(0, "J"))
		state.red_joker_effect = jdata.get("red", {}).get("effect", "")
		state.black_joker_effect = jdata.get("black", {}).get("effect", "")

	# Mod.
	var mdata: Dictionary = Balance.mods().get(state.mod_suit, {})
	if b["mods_enabled"] and MOD_SCRIPTS.has(mdata.get("id", "")):
		mod = MOD_SCRIPTS[mdata["id"]].new()
	else:
		mod = ModBase.new()
	if b["mods_enabled"]:
		mod.setup(state.mod_suit, mdata)

	# Starting deck: the four twos.
	for s in Card.SUITS:
		state.deck.append(_new_card(2, s))

	_emit(Ev.MOD_REVEALED, {"suit": state.mod_suit, "name": mod.name, "desc": mod.desc, "active": b["mods_enabled"]})
	_emit(Ev.THEME_REVEALED, {"suit": state.theme_suit,
		"red": jdata.get("red", {}).get("desc", ""), "black": jdata.get("black", {}).get("desc", ""),
		"active": b["jokers_enabled"]})

	state.floor_num = int(options.get("start_floor", GameState.FIRST_FLOOR))
	var pick_rank := mod.setup_pick_rank()
	if pick_rank > 0:
		for s in Card.SUITS:
			state.setup_options.append(_new_card(pick_rank, s))
		state.phase = Phase.SETUP_PICK
		_emit(Ev.SETUP_PICK, {"options": _labels(state.setup_options)})
	else:
		state.phase = Phase.REVEAL


func setup_pick(card_id: int) -> bool:
	if state.phase != Phase.SETUP_PICK:
		return false
	var c = state.find_in(state.setup_options, card_id)
	if c == null:
		return false
	state.deck.append(c)
	_excluded[c.rank] = _excluded.get(c.rank, []) + [c.suit]
	state.setup_options.clear()
	state.phase = Phase.REVEAL
	_emit(Ev.SETUP_PICKED, {"card": c.label()})
	return true


func ack_reveal() -> bool:
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
	if f >= GameState.BOSS_FLOOR:
		state.floor_num = GameState.BOSS_FLOOR
		state.enemy_pile = _boss_pile.duplicate()
		rng.shuffle(state.enemy_pile)
	else:
		var cards: Array = []
		var removed: Array = _excluded.get(f, [])
		for s in Card.SUITS:
			if not removed.has(s):
				cards.append(_new_card(f, s))
		rng.shuffle(cards)
		if state.balance["short_floors"].has(f) and cards.size() > 3:
			cards.resize(3)
		state.enemy_pile = cards
	# Piles reset every floor: whole deck shuffled, innate (red joker) cards on top.
	state.draw_pile = state.deck.duplicate()
	rng.shuffle(state.draw_pile)
	var innate: Array = []
	for c in state.draw_pile:
		if c.joker == "innate":
			innate.append(c)
	for c in innate:
		state.draw_pile.erase(c)
		state.draw_pile.append(c)
	state.discard = []
	state.hand = []
	state.played = []
	state.retained = []
	state.carry_shield = 0
	_emit(Ev.FLOOR_STARTED, {"floor": state.floor_num, "count": state.enemy_pile.size()})
	_next_round()


func _next_round() -> void:
	state.current = []
	while state.current.is_empty():
		if state.enemy_pile.is_empty():
			_floor_cleared()
			return
		var c = state.enemy_pile.pop_front()
		if c.suit == "J":
			state.current = _black_joker(c)
		else:
			state.current = [c]
	state.round_num += 1
	state.floor_round += 1
	for c in state.current:
		_emit(Ev.ENEMY_REVEALED, {"card": c.label(), "id": c.id, "rank": c.rank, "suit": c.suit,
			"intent": "attack" if c.base_black() else "shield", "value": enemy_value(c),
			"left": state.enemy_pile.size(), "total_left": state.enemy_pile.size() + state.current.size(),
			"virtual": c.from_joker})
	# Fill the hand.
	state.hand = state.retained
	state.retained = []
	var limit := int(state.balance["boss_hand_size"] if state.is_boss() else state.balance["hand_size"])
	while state.hand.size() < limit:
		var d = _draw_one()
		if d == null:
			break
		state.hand.append(d)
	state.phase = Phase.PLAY
	_emit(Ev.HAND_FILLED, {"hand": _labels(state.hand), "ids": _ids(state.hand)})


func _draw_one():
	if state.draw_pile.is_empty():
		if state.discard.is_empty():
			return null
		state.draw_pile = state.discard
		state.discard = []
		rng.shuffle(state.draw_pile)
		_emit(Ev.DECK_RESHUFFLED, {"count": state.draw_pile.size()})
	return state.draw_pile.pop_back()


func _black_joker(j) -> Array:
	state.beaten.append(j)
	var eff := state.black_joker_effect
	var desc: String = Balance.jokers().get(state.theme_suit, {}).get("black", {}).get("desc", eff)
	_emit(Ev.JOKER_TRIGGERED, {"effect": eff, "desc": desc})
	var curse := int(state.balance["joker_curse_value"])
	match eff:
		"return_king":
			for i in range(state.beaten.size() - 1, -1, -1):
				var k = state.beaten[i]
				if k.suit != "J" and not k.from_joker:
					state.beaten.remove_at(i)
					state.enemy_pile.append(k)
					break
			return []
		"shield":
			return [_virtual(curse, "D")]
		"attack":
			return [_virtual(curse, "S")]
		"double_reveal":
			var out: Array = []
			while out.size() < 2 and not state.enemy_pile.is_empty():
				out.append(state.enemy_pile.pop_front())
			return out
	return []


func _virtual(rank: int, suit: String):
	var v = _new_card(rank, suit)
	v.temp = true
	v.from_joker = true
	return v


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


## True when a shield is revealed and no black enemy cards are left in the pile:
## failing to break it costs a life (the "locked" rule).
func lockout_risk() -> bool:
	if attack_need() <= 0:
		return false
	for e in state.enemy_pile:
		if e.base_black():
			return false
	return true


func retain_limit() -> int:
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
		if not state.balance["ace_sac_own_color"]:
			out.append(a)
		elif (a.base_red() and block_need() > 0) or (a.base_black() and attack_need() > 0):
			out.append(a)
	return out


func preview_enemies() -> Array:
	return state.enemy_pile.slice(0, mod.preview_count())


func _block_val(c) -> int:
	if c.temp and not state.balance["ace_sac_suit_effects"]:
		return c.rank
	return c.value()


func _attack_val(c) -> int:
	if c.temp and not state.balance["ace_sac_suit_effects"]:
		return c.rank
	if c.suit == "S":
		return int(floor(c.value() * float(state.balance["spade_multiplier"])))
	return c.value()


## Totals for a set of played cards (used for the live counter and for resolution).
func compute(cards: Array) -> Dictionary:
	var bneed := block_need()
	var aneed := attack_need()
	var carry := state.carry_shield if bneed > 0 else 0
	var reds: Array = []
	var blacks: Array = []
	var duals: Array = []
	for c in cards:
		if c.joker == "dual":
			duals.append(c)
		elif c.is_red():
			reds.append(c)
		else:
			blacks.append(c)
	for d in duals:
		var cur := carry
		for r in reds:
			cur += _block_val(r)
		if bneed > cur:
			reds.append(d)
		elif aneed > 0:
			blacks.append(d)
		else:
			reds.append(d)
	var block := carry
	var hearts := 0
	for c in reds:
		block += _block_val(c)
		if c.suit == "H" and (not c.temp or state.balance["ace_sac_suit_effects"]):
			hearts += _block_val(c)
	var attack := 0
	var clubs := 0
	for c in blacks:
		attack += _attack_val(c)
		if c.suit == "C" and (not c.temp or state.balance["ace_sac_suit_effects"]):
			clubs += 1
	if clubs >= 2:
		attack += int(state.balance["club_pair_bonus"])
	if not blacks.is_empty():
		attack = mod.modify_player_attack(attack)
	return {"block": block, "attack": attack, "block_need": bneed, "attack_need": aneed,
		"hearts": hearts, "carry": carry, "block_cards": reds, "attack_cards": blacks}


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
	var draws := 0
	for c in cards:
		if c.suit == "D":
			draws += 1
		if c.joker == "draw2":
			draws += 2
	for i in draws:
		var d = _draw_one()
		if d == null:
			break
		state.hand.append(d)
		_emit(Ev.CARD_DRAWN, {"card": d.label(), "id": d.id})
	return true


func sacrifice_ace(ace_id: int) -> bool:
	var a = state.find_in(sacrificable_aces(), ace_id)
	if a == null:
		return false
	state.lives.erase(a)
	state.lost_lives.append(a)
	var t = _new_card(int(state.balance["ace_value"]), a.suit)
	t.temp = true
	if not state.balance["ace_sac_own_color"]:
		t.joker = "dual"
	state.played.append(t)
	_emit(Ev.ACE_SACRIFICED, {"card": a.label(), "id": a.id, "value": t.rank, "temp_id": t.id})
	_emit(Ev.LIFE_LOST, {"card": a.label(), "id": a.id, "lives": state.lives.size(), "cause": "sacrifice"})
	return true


## Ends the play step and resolves the round.
func resolve() -> bool:
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
			new_carry = mini(blk - bneed, t["hearts"])
		else:
			var miss := bneed - blk
			var dmg := 2 if miss >= int(b["graded_threshold"]) else 1
			_emit(Ev.DAMAGE_TAKEN, {"block": blk, "attack": bneed, "miss": miss, "lives": dmg})
			if _lose_lives(dmg, "damage"):
				return true
		for e in state.enemy_attack_cards():
			_beat(e)
		state.carry_shield = new_carry
		if new_carry > 0:
			_emit(Ev.SHIELD_STORED, {"amount": new_carry})
	elif int(t["hearts"]) > 0:
		# ♥ played with no attack to block: the whole heart value is stored (replaces older shield).
		state.carry_shield = int(t["hearts"])
		_emit(Ev.SHIELD_STORED, {"amount": state.carry_shield})
	elif b["heart_carry_mode"] == "next_round":
		state.carry_shield = 0
	if aneed > 0:
		var atk: int = t["attack"]
		var shields := state.enemy_shield_cards()
		if atk >= aneed:
			_emit(Ev.ATTACK_SUCCEEDED, {"attack": atk, "shield": aneed, "exact": atk == aneed})
			for e in shields:
				_beat(e)
		else:
			var black_left := false
			for e in state.enemy_pile:
				if e.base_black():
					black_left = true
					break
			if not black_left:
				_emit(Ev.LOCKOUT, {"attack": atk, "shield": aneed})
				if _lose_lives(1, "lockout"):
					return true
				for e in shields:
					_beat(e)
			else:
				_emit(Ev.ATTACK_FAILED, {"attack": atk, "shield": aneed})
				for e in shields:
					state.enemy_pile.append(e)
	for c in state.played:
		if not c.temp:
			state.discard.append(c)
	state.played = []
	state.current = []
	state.phase = Phase.RETAIN
	# Nothing to keep when the floor is over (piles reset at the next floor).
	if retain_limit() <= 0 or state.hand.is_empty() or state.enemy_pile.is_empty():
		retain([])
	return true


func retain(ids: Array) -> bool:
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
	_emit(Ev.RETAINED, {"cards": _labels(keep), "ids": _ids(keep)})
	_next_round()
	return true


func _beat(e) -> void:
	state.beaten.append(e)
	state.last_beaten = e
	_emit(Ev.ENEMY_DEFEATED, {"card": e.label(), "id": e.id, "suit": e.suit})


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
	var last = state.last_beaten
	_emit(Ev.FLOOR_CLEARED, {"floor": state.floor_num, "last": last.label() if last else "",
		"suit": last.suit if last else ""})
	if state.is_boss():
		state.result = "win"
		state.phase = Phase.WON
		_emit(Ev.RUN_WON, {})
		return
	var pool: Array = []
	for c in state.beaten:
		if c.suit != "J" and not c.from_joker:
			pool.append(_new_card(c.rank, c.suit))
	rng.shuffle(pool)
	var suit: String = last.suit if last and Card.SUITS.has(last.suit) else "S"
	var r := {"suit": suit, "heal": 0, "picks": 1, "reveal": 2, "remove": false, "all": false}
	match suit:
		"S": r["all"] = true
		"C": r["remove"] = true
		"H": r["heal"] = 1
		"D": r["picks"] = 2
	mod.modify_reward(r)
	if suit == "H" and state.lost_lives.is_empty():
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


func deck_full() -> bool:
	return state.deck.size() >= int(state.balance["deck_cap"])


## Take a reward option. When the deck is full, `replace_id` names the deck card to swap out.
func reward_take(option_id: int, replace_id: int = -1) -> bool:
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
	return deck_full()


## Decline the rest of the reward.
func reward_skip() -> bool:
	if state.phase != Phase.REWARD or not can_decline():
		return false
	state.reward["picks"] = 0
	_emit(Ev.REWARD_SKIPPED, {})
	_after_pick()
	return true


## Decline a single option (uses up one pick), e.g. one of the two ♦ cards.
func reward_decline(option_id: int) -> bool:
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


func reward_remove(card_id: int) -> bool:
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
	if state.balance["jokers_enabled"] and not state.joker_attached \
			and state.floor_num == int(state.balance["red_joker_after_floor"]):
		state.phase = Phase.JOKER_ATTACH
		var desc: String = Balance.jokers().get(state.theme_suit, {}).get("red", {}).get("desc", "")
		_emit(Ev.JOKER_OFFERED, {"effect": state.red_joker_effect, "desc": desc})
		return
	_start_floor(state.floor_num + 1)


func attach_joker(card_id: int) -> bool:
	if state.phase != Phase.JOKER_ATTACH:
		return false
	var c = state.find_in(state.deck, card_id)
	if c == null:
		return false
	c.joker = state.red_joker_effect
	state.joker_attached = true
	_emit(Ev.JOKER_ATTACHED, {"card": c.label(), "id": c.id, "effect": c.joker})
	_start_floor(state.floor_num + 1)
	return true


# ---------------------------------------------------------------- debug

func debug_jump_to_floor(f: int) -> void:
	_emit(Ev.DEBUG, {"msg": "jumping to floor %d" % f})
	state.reward = {}
	_start_floor(clampi(f, GameState.FIRST_FLOOR, GameState.BOSS_FLOOR))


func debug_give_life() -> void:
	if not state.lost_lives.is_empty():
		var a = state.lost_lives.pop_back()
		state.lives.append(a)
		_emit(Ev.LIFE_RESTORED, {"card": a.label(), "id": a.id, "lives": state.lives.size()})
	else:
		_emit(Ev.DEBUG, {"msg": "no lost lives to restore"})


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
