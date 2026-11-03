extends RefCounted
## The simple playtest bot from the spec (mirrors sim/reference/balance_sim.py):
## - plays every card of the right colour
## - keeps the highest unplayed card
## - reward: colour the deck has the least of, then highest rank; swaps out the lowest same-colour card
## - sacrifices an ace only when blocking and a miss would cost 2 lives
## - attaches the red joker to its highest card

const GameState := preload("res://engine/game_state.gd")
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
		Phase.JOKER_ATTACH:
			var best = null
			for c in s.deck:
				if c.joker == "" and (best == null or c.value() > best.value()):
					best = c
			if best == null:
				best = s.deck[0]
			e.attach_joker(best.id)
		_:
			return false
	return true


func play_run(e) -> void:
	var guard := 0
	while step(e):
		guard += 1
		if guard > 5000:
			push_warning("bot: run did not terminate, seed %d" % e.state.seed_value)
			e.state.result = "loop"
			return


func _play(e) -> void:
	# Play all usable cards; repeat while ♦ / draw2 bring in new usable cards.
	while true:
		var p: Array = e.playable_cards()
		if p.is_empty():
			break
		e.play_cards(_ids(p))
	var need: int = e.block_need()
	if need > 0:
		var t: Dictionary = e.compute(e.state.played)
		var miss: int = need - int(t["block"])
		if miss >= int(e.state.balance["graded_threshold"]):
			for a in e.sacrificable_aces():
				if a.base_red() or not e.state.balance["ace_sac_own_color"]:
					e.sacrifice_ace(a.id)
					break
	e.resolve()


func _reward(e) -> void:
	var s = e.state
	var opts: Array = s.reward["options"]
	var c = opts[0] if s.reward["suit"] == "D" and int(s.reward["picks"]) >= 2 else _best(s, opts)
	if not e.deck_full():
		e.reward_take(c.id)
		return
	var same: Array = []
	for d in s.deck:
		if d.joker == "" and d.is_red() == c.base_red():
			same.append(d)
	if same.is_empty():
		for d in s.deck:
			if d.joker == "":
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
	var pool: Array = []
	for d in deck:
		if d.joker == "":
			pool.append(d)
	if pool.is_empty():
		pool = deck
	var w = pool[0]
	for d in pool:
		if d.value() < w.value():
			w = d
	return w


static func _ids(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append(c.id)
	return out
