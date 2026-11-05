extends RefCounted
## The simple playtest bot from the spec (mirrors sim/reference/balance_sim.py):
## - plays every card of the right colour
## - keeps the highest unplayed card
## - reward: colour the deck has the least of, then highest rank; swaps out the lowest same-colour card
## - sacrifices an ace only when blocking and a miss would cost 2 lives
## - burns a card only when that is the only way to beat the enemy card (or to soften a big miss)

const GameState := preload("res://engine/game_state.gd")
const EXACT_BONUS := 25  # cost units (10 per card value point) a perfect hit is worth to the bot
const BURN_COST := 30    # extra cost units for burning a card (it leaves the deck for good)
const STUCK_ROUNDS := 80  # a floor this long means the run is stuck (an unbreakable shield): give up
const Phase := GameState.Phase
const REST_AT := 1  # rest (heal instead of a reward) at this many lives or fewer


## Advance the engine by one decision. Returns false when the run is over.
func step(e) -> bool:
	var s = e.state
	match s.phase:
		Phase.SETUP_PICK:
			e.setup_pick(_best(s, s.setup_options).id)
		Phase.REVEAL:
			e.ack_reveal()
		Phase.PLAY:
			_play(e)
		Phase.RETAIN:
			var n: int = e.retain_limit()
			var rest: Array = s.hand.duplicate()
			rest.sort_custom(func(a, b): return a.value() > b.value())
			e.retain(_ids(rest.slice(0, n)))
		Phase.REWARD:
			_reward(e)
		Phase.REWARD_REMOVE:
			e.reward_remove(_lowest(s.deck).id)
		_:
			return false
	return true


func play_run(e) -> void:
	var guard := 0
	while step(e):
		guard += 1
		if e.state.floor_round > STUCK_ROUNDS:
			e.state.result = "stuck"  # a player would restart here
			return
		if guard > 20000:
			push_warning("bot: run did not terminate, seed %d" % e.state.seed_value)
			e.state.result = "loop"
			return


func _play(e) -> void:
	if e.keep_hand():
		_play_thrifty(e)
	elif int(e.state.balance.get("retain", 0)) > 0 or e.continuous_refill():
		_play_thrifty(e, true)
	else:
		_play_all(e)


## Redraw (mulligan) before playing: when the hand can't beat the enemy card, throw the cards that
## don't count against it (and the low ones of the right colour) and draw new ones.
func _maybe_redraw(e) -> void:
	var s = e.state
	if not e.can_redraw() or s.hand.is_empty():
		return
	if str(s.balance.get("redraw_scope", "round")) == "floor" and e.block_need() <= 0:
		return  # a scarce redraw is kept for attacks (a missed shield only costs a round)
	if not _cheapest_plan(e, true, _burns_left(e)).is_empty():
		return
	var avg := _deck_avg(s)
	var toss: Array = []
	for c in s.hand:
		if not e.is_effective(c) or c.value() < avg:
			toss.append(c)
	if toss.is_empty():
		return
	var spare: int = s.draw_pile.size() + (s.discard.size() if e.continuous_refill() else 0)
	if spare <= 0:
		return
	e.redraw(_ids(toss.slice(0, spare)))


## Dig burn: when the hand can't do the job, burn the weakest card that doesn't count (or the
## weakest card) for `burn_draw` new ones. Returns true if it burned.
func _dig_burn(e) -> bool:
	var s = e.state
	if e.burn_mode() != "dig" or not e.can_burn() or s.draw_pile.is_empty():
		return false
	var cands: Array = s.hand.filter(func(c): return _can_spare(e, c, []))
	if cands.is_empty():
		return false
	cands.sort_custom(func(a, b):
		var ea: bool = e.is_effective(a)
		var eb: bool = e.is_effective(b)
		if ea != eb:
			return not ea
		return a.value() < b.value())
	if cands[0].value() > _deck_avg(s) + 1:
		return false  # never burn a good card
	return e.burn_card(cands[0].id)


## Cards stay in hand between rounds: play the cheapest set that does the job, ♦ first (they draw),
## save the rest. Burn a card only when nothing else does the job. If the enemy can't be stopped,
## only play enough to avoid the 2-life miss.
func _play_thrifty(e, fresh := false) -> void:
	var s = e.state
	var graded: int = e.graded_threshold()
	_maybe_redraw(e)
	for _guard in 16:
		var bneed: int = e.block_need()
		var aneed: int = e.attack_need()
		var t: Dictionary = e.compute(s.played)
		var short_block: bool = bneed > 0 and int(t["block"]) < bneed
		var short_atk: bool = aneed > 0 and int(t["attack"]) < aneed
		if not short_block and not short_atk:
			break
		var plan := _cheapest_plan(e, true, 0)
		if plan.is_empty():
			# Can't make it with this hand: try to dig for better cards first.
			var blacks: Array = s.hand.filter(func(c): return c.is_black())
			if short_block and not s.overpowered and e.overpower_value(s.played + blacks) > 0:
				e.play_cards(_ids(blacks))  # overpower: unclog the black cards, draw 1
				continue
			var dias: Array = s.hand.filter(func(c): return c.suit == "D")
			if not dias.is_empty() and not s.draw_pile.is_empty() and e._diamond_draws():
				e.play_cards([dias[0].id])  # ♦ draws while the draw pile has cards
				continue
			if _dig_burn(e):
				continue
			plan = _cheapest_plan(e, true, _burns_left(e))
			if plan.is_empty() and (short_block or _shield_wounds(e)):
				plan = _cheapest_plan(e, false, _burns_left(e))
		if plan.is_empty():
			break
		var play: Array = plan["play"]
		var burn: Array = plan["burn"]
		var drawers: Array = play.filter(func(c): return c.suit == "D")
		if not drawers.is_empty() and play.size() + burn.size() > 1:
			e.play_cards([drawers[0].id])  # draw first, then re-plan with the new card
			continue
		for c in burn:
			e.burn_card(c.id)
		if not play.is_empty():
			e.play_cards(_ids(play))
		if not drawers.is_empty():
			continue  # the drawn card may help
		break
	# A shield it can't break goes to the bottom and comes back: cycle the hand (play everything,
	# ♥ store shield, ♦ draw) so the next try starts from fresh cards instead of the same ones.
	var aneed2: int = e.attack_need()
	if aneed2 > 0 and int(e.compute(s.played)["attack"]) < aneed2:
		if not _shield_wounds(e):
			if not s.hand.is_empty():
				e.play_cards(_ids(s.hand))
		elif aneed2 - int(e.compute(s.played)["attack"]) >= graded:
			for a in e.sacrificable_aces():
				if a.base_black():
					e.sacrifice_ace(a.id)
					break
	var need: int = e.block_need()
	if need > 0:
		var miss: int = need - int(e.compute(s.played)["block"])
		# A graded miss always warrants an ace; with returning attacks any miss does
		# (an ace costs 1 life once, a miss costs a life and the attack comes back).
		if miss >= graded or (miss > 0 and bool(s.balance.get("failed_attack_returns", false))):
			for a in e.sacrificable_aces():
				if a.base_red():
					e.sacrifice_ace(a.id)
					break
	# Fresh hands: unplayed cards are discarded anyway, so play the leftover ♥ (stored shield)
	# and ♦ (a draw while it still draws), keeping the best card for the keep step.
	if fresh:
		var keep_n: int = e.retain_limit()
		var rest: Array = s.hand.duplicate()
		rest.sort_custom(func(a, b): return a.value() > b.value())
		var extra: Array = []
		for c in rest.slice(keep_n):
			if c.suit == "H":
				extra.append(c)
		if not extra.is_empty():
			e.play_cards(_ids(extra))
	# Free discard: drop below-average unplayed cards so the refill can bring better ones.
	if e.can_discard():
		var avg := _deck_avg(s)
		for c in s.hand.duplicate():
			if c.value() < avg:
				e.discard_card(c.id)
	e.resolve()


## How many cards the bot may still burn this round (an unlimited burn is capped at 2 per plan).
static func _burns_left(e) -> int:
	if not e.can_burn() or e.burn_mode() == "dig":
		return 0
	var lim := int(e.state.balance.get("burn_limit", 0))
	var left: int = 2 if lim <= 0 else lim - int(e.state.burns_this_round)
	return clampi(left, 0, maxi(0, e.state.deck.size() - int(e.state.balance.get("burn_min_deck", 0)) + 1))


static func _deck_avg(s) -> float:
	if s.deck.is_empty():
		return 0.0
	var t := 0
	for d in s.deck:
		t += d.value()
	return float(t) / s.deck.size()


## Cheapest {play: [cards], burn: [cards]} from the hand that reaches the need (full = true) or that
## keeps a block miss below the graded threshold (full = false), burning at most `max_burns` cards.
## Returns {} if none does.
static func _cheapest_plan(e, full: bool, max_burns: int) -> Dictionary:
	var s = e.state
	var hand: Array = s.hand.slice(0, 8)
	var ctx := {"best": {}, "cost": 1 << 30}
	_search(e, hand, 0, [], [], 0, max_burns, full, ctx)
	return ctx["best"]


static func _search(e, hand: Array, i: int, play: Array, burn: Array, cost: int, max_burns: int, full: bool, ctx: Dictionary) -> void:
	if cost - EXACT_BONUS >= int(ctx["cost"]):
		return
	if i == hand.size():
		if play.is_empty() and burn.is_empty():
			return
		var c := _plan_cost(e, play, burn, cost, full)
		if c >= 0 and c < int(ctx["cost"]):
			ctx["cost"] = c
			ctx["best"] = {"play": play.duplicate(), "burn": burn.duplicate()}
		return
	var card = hand[i]
	_search(e, hand, i + 1, play, burn, cost, max_burns, full, ctx)
	if e.is_effective(card):
		play.append(card)
		_search(e, hand, i + 1, play, burn, cost + card.value() * 10 + 1, max_burns, full, ctx)
		play.pop_back()
	if burn.size() < max_burns and _can_spare(e, card, burn):
		burn.append(card)
		card.burned = true  # so compute() values it as burned
		_search(e, hand, i + 1, play, burn, cost + card.value() * 10 + BURN_COST, max_burns, full, ctx)
		card.burned = false
		burn.pop_back()


## Burning must leave the deck at least BURN_KEEP cards of the card's colour, or later shields
## (black needed) or attacks (red needed) can become impossible.
const BURN_KEEP := 2


static func _can_spare(e, card, burning: Array) -> bool:
	var left := 0
	for d in e.state.deck:
		if d != card and not burning.has(d) and d.base_red() == card.base_red():
			left += 1
	return left >= BURN_KEEP


## Cost of a finished plan, or -1 if it doesn't do the job.
static func _plan_cost(e, play: Array, burn: Array, cost: int, full: bool) -> int:
	var s = e.state
	var bneed: int = e.block_need()
	var aneed: int = e.attack_need()
	for c in burn:
		c.burned = true
	var t: Dictionary = e.compute(s.played + play + burn)
	for c in burn:
		c.burned = false
	var ok: bool
	if full:
		ok = int(t["block"]) >= bneed and int(t["attack"]) >= aneed
	else:
		ok = maxi(bneed - int(t["block"]), aneed - int(t["attack"])) < int(e.graded_threshold())
	if not ok:
		return -1
	if full and int(s.balance.get("perfect_draw", 0)) > 0:
		# A perfect hit (exactly the enemy value) draws an extra card: worth a little overspend.
		var exact_b: bool = bneed <= 0 or int(t["block"]) == bneed
		var exact_a: bool = aneed <= 0 or int(t["attack"]) == aneed
		if exact_b and exact_a:
			cost -= EXACT_BONUS
	return cost


## Old rules (unplayed cards are discarded): play every card that counts.
func _play_all(e) -> void:
	# Play all usable cards; repeat while ♦ bring in new usable cards.
	while true:
		var p: Array = e.playable_cards()
		if p.is_empty():
			break
		e.play_cards(_ids(p))
	var need: int = e.block_need()
	if need > 0:
		var t: Dictionary = e.compute(e.state.played)
		var miss: int = need - int(t["block"])
		if miss >= int(e.graded_threshold()) or (miss > 0 and bool(e.state.balance.get("failed_attack_returns", false))):
			for a in e.sacrificable_aces():
				if a.base_red():
					e.sacrifice_ace(a.id)
					break
	e.resolve()


## True when failing the revealed shield costs lives (failed_shield "wound", or "second" on a turned shield).
static func _shield_wounds(e) -> bool:
	if e.attack_need() <= 0 or not e.has_method("failed_shield_mode"):
		return false
	match e.failed_shield_mode():
		"wound":
			return true
		"second":
			for c in e.state.enemy_shield_cards():
				if c.turned:
					return true
	return false


func _reward(e) -> void:
	var s = e.state
	if s.reward.get("menu", false):
		_reward_menu(e)
		return
	if s.reward.has("choose"):
		e.reward_suit(_choose_suit(s, s.reward["choose"]))
		return  # the chosen reward (or the next floor) is handled on the next step
	if e.has_method("can_rest") and e.can_rest() and s.lives.size() <= int(s.balance.get("bot_rest_at", REST_AT)):
		e.rest()
		return
	var opts: Array = s.reward["options"]
	var c = opts[0] if s.reward["suit"] == "D" and int(s.reward["picks"]) >= 2 else _pick_from(s, s.deck, opts)
	if not e.deck_full():
		# Optional rewards: only add cards that raise the deck's average value.
		if e.can_decline() and c.rank < _deck_avg(s):
			# Camp: rather than nothing, thin the deck by its lowest card.
			if e.has_method("can_trim") and e.can_trim() and _lowest(s.deck).value() < _deck_avg(s):
				e.trim(_lowest(s.deck).id)
				return
			e.reward_decline(c.id)
		else:
			e.reward_take(c.id)
		return
	var same: Array = []
	for d in s.deck:
		if d.is_red() == c.base_red():
			same.append(d)
	if same.is_empty():
		same = s.deck
	var w = same[0]
	for d in same:
		if d.value() < w.value():
			w = d
	if w.value() < c.rank:
		e.reward_take(c.id, w.id)
	else:
		e.reward_decline(c.id)


## Reward choice between two suits: heal on the last life, else ♣ (take 1, remove 1) once the deck
## has cards to spare, else ♦ (take 2), else heal, else ♠ (pick any).
func _choose_suit(s, suits: Array) -> String:
	var order: Array = _suit_order(s)
	for x in order:
		if suits.has(x):
			return x
	return suits[0]


func _suit_order(s) -> Array:
	if s.lives.size() <= 1 and not s.lost_lives.is_empty():
		return ["H", "C", "D", "S"]
	if s.deck.size() >= MENU_THIN:
		return ["C", "D", "H", "S"] if s.lost_lives.is_empty() else ["C", "H", "D", "S"]
	return ["D", "C", "H", "S"] if s.lost_lives.is_empty() else ["D", "H", "C", "S"]


## Reward menu: heal when on the last life, trade (add 1, remove the lowest) once the deck is big,
## otherwise take the cards that raise the deck average; cull when nothing is worth taking.
const MENU_THIN := 8  # deck size from which the bot trades instead of taking 2


func _reward_menu(e) -> void:
	var s = e.state
	var opts: Array = s.reward["options"]
	var worth := _worth(s, opts)
	if e.menu_can("heal") and (s.lives.size() <= 1 or (worth.is_empty() and s.lives.size() < s.max_lives)):
		e.reward_menu("heal")
		return
	if worth.is_empty():
		var cut := _lowest_n(s.deck, mini(int(s.reward["cull"]), s.deck.size() - int(s.balance["deck_min"])))
		if not (e.menu_can("cull") and not cut.is_empty() and e.reward_menu("cull", [], _ids(cut))):
			if not e.reward_menu("take"):
				if not (e.menu_can("heal") and e.reward_menu("heal")):
					e.reward_skip()
		return
	if s.deck.size() >= _thin_target() and e.menu_can("trade"):
		var lows := _lowest_n(s.deck + [worth[0]], 1)
		var low = lows[0] if not lows.is_empty() else worth[0]
		if low != worth[0] and low.value() < worth[0].rank and e.reward_menu("trade", [worth[0].id], [low.id]):
			return
	if not e.reward_menu("take", _ids(worth.slice(0, int(s.reward["picks"])))):
		e.reward_menu("take")


func _thin_target() -> int:
	return MENU_THIN


## Reward options worth adding (rank above the deck average), best first.
func _worth(s, opts: Array) -> Array:
	var left: Array = opts.filter(func(c): return c.rank > _deck_avg(s))
	var out: Array = []
	var deck: Array = s.deck.duplicate()
	while not left.is_empty():
		var c = _pick_from(s, deck, left)
		out.append(c)
		left.erase(c)
		deck.append(c)
	return out


## Which option the bot likes best given a (hypothetical) deck: archetype bots override this.
func _pick_from(_s, deck: Array, opts: Array):
	return _best_for(deck, opts)


## The n lowest cards, never leaving fewer than BURN_KEEP cards of a colour.
static func _lowest_n(deck: Array, n: int) -> Array:
	var d: Array = deck.duplicate()
	d.sort_custom(func(a, b): return a.value() < b.value())
	var out: Array = []
	var reds := deck.filter(func(c): return c.base_red()).size()
	var blacks := deck.size() - reds
	for c in d:
		if out.size() >= n:
			break
		if c.base_red() and reds > BURN_KEEP:
			reds -= 1
			out.append(c)
		elif not c.base_red() and blacks > BURN_KEEP:
			blacks -= 1
			out.append(c)
	return out


## Prefer the colour with the lowest deck sum, then the highest rank (first max wins).
static func _best(s, opts: Array):
	return _best_for(s.deck, opts)


static func _best_for(deck: Array, opts: Array):
	var redv := 0
	var blkv := 0
	for d in deck:
		if d.is_red():
			redv += d.value()
		if d.is_black():
			blkv += d.value()
	var want_red := redv <= blkv
	var pool: Array = []
	for c in opts:
		if c.base_red() == want_red:
			pool.append(c)
	if pool.is_empty():
		pool = opts
	var best = pool[0]
	for c in pool:
		if c.rank > best.rank:
			best = c
	return best


static func _lowest(deck: Array):
	var w = deck[0]
	for d in deck:
		if d.value() < w.value():
			w = d
	return w


static func _ids(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c.id)
	return out
