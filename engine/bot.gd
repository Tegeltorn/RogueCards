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
	else:
		_play_all(e)


## Cards stay in hand between rounds: play the cheapest set that does the job, ♦ first (they draw),
## save the rest. Burn a card only when nothing else does the job. If the enemy can't be stopped,
## only play enough to avoid the 2-life miss.
func _play_thrifty(e) -> void:
	var s = e.state
	var graded := int(s.balance["graded_threshold"])
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
			if not dias.is_empty():
				e.play_cards([dias[0].id])  # ♦ always draws
				continue
			plan = _cheapest_plan(e, true, _burns_left(e))
			if plan.is_empty() and short_block:
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
	if aneed2 > 0 and int(e.compute(s.played)["attack"]) < aneed2 and not s.hand.is_empty():
		e.play_cards(_ids(s.hand))
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
	# Free discard: drop below-average unplayed cards so the refill can bring better ones.
	if e.can_discard():
		var avg := _deck_avg(s)
		for c in s.hand.duplicate():
			if c.value() < avg:
				e.discard_card(c.id)
	e.resolve()


## How many cards the bot may still burn this round (an unlimited burn is capped at 2 per plan).
static func _burns_left(e) -> int:
	if not e.can_burn():
		return 0
	var lim := int(e.state.balance.get("burn_limit", 0))
	var left: int = 2 if lim <= 0 else lim - int(e.state.burns_this_round)
	return clampi(left, 0, maxi(0, e.state.deck.size() - int(e.state.balance["deck_min"])))


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
	if burn.size() < max_burns:
		burn.append(card)
		card.burned = true  # so compute() values it as burned
		_search(e, hand, i + 1, play, burn, cost + card.value() * 10 + BURN_COST, max_burns, full, ctx)
		card.burned = false
		burn.pop_back()


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
		ok = bneed - int(t["block"]) < int(s.balance["graded_threshold"])
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
		if miss >= int(e.state.balance["graded_threshold"]) or (miss > 0 and bool(e.state.balance.get("failed_attack_returns", false))):
			for a in e.sacrificable_aces():
				if a.base_red():
					e.sacrifice_ace(a.id)
					break
	e.resolve()


func _reward(e) -> void:
	var s = e.state
	var opts: Array = s.reward["options"]
	var c = opts[0] if s.reward["suit"] == "D" and int(s.reward["picks"]) >= 2 else _best(s, opts)
	if not e.deck_full():
		# Optional rewards: only add cards that raise the deck's average value.
		if e.can_decline() and c.rank < _deck_avg(s):
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


## Prefer the colour with the lowest deck sum, then the highest rank (first max wins).
static func _best(s, opts: Array):
	var redv := 0
	var blkv := 0
	for d in s.deck:
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
