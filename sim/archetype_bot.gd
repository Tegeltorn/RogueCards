extends "res://engine/bot.gd"
## Playtest bot with a deck-building plan, to check that several builds are viable.
##   "smart"            the normal bot (colour it lacks)
##   "HS" "HC" "DS" "DC" suit pair: take the colour the deck lacks, in the build's suit when offered
##   "thin"             keep the deck small: trade/cull, take only clearly better cards
##   "fat"              take every card it can
##   "random"           random reward choices

var arch := "smart"
var rnd := RandomNumberGenerator.new()


func _init(p_arch: String = "smart", p_seed: int = 7) -> void:
	arch = p_arch
	rnd.seed = p_seed


func _pick_from(s, deck: Array, opts: Array):
	if arch == "random":
		return opts[rnd.randi() % opts.size()]
	if arch.length() == 2:
		# Suit pair (one red, one black suit): take the colour the deck lacks, in the build's suit.
		var redv := 0
		var blkv := 0
		for d in deck:
			if d.base_red():
				redv += d.value()
			else:
				blkv += d.value()
		var want_red := redv <= blkv
		var best = null
		for c in opts:
			if arch.contains(c.suit) and (best == null or (c.base_red() == want_red and not best.base_red() == want_red) \
					or (c.base_red() == best.base_red() and c.rank > best.rank)):
				best = c
		if best != null and best.base_red() == want_red:
			return best
		var pool: Array = opts.filter(func(c): return c.base_red() == want_red)
		if pool.is_empty() and best != null:
			return best
	return super._pick_from(s, deck, opts)


func _suit_order(s) -> Array:
	match arch:
		"thin":
			return ["H", "C", "S", "D"] if s.lives.size() <= 1 else ["C", "S", "H", "D"]
		"fat":
			return ["H", "D", "S", "C"] if s.lives.size() <= 1 else ["D", "S", "H", "C"]
		"random":
			var o: Array = ["H", "D", "S", "C"]
			o.shuffle()
			return o
	return super._suit_order(s)


func _thin_target() -> int:
	match arch:
		"thin":
			return 0
		"fat":
			return 99
	return super._thin_target()


func _worth(s, opts: Array) -> Array:
	var w: Array = super._worth(s, opts)
	if arch == "fat":
		w = []
		var left: Array = opts.duplicate()
		var deck: Array = s.deck.duplicate()
		while not left.is_empty():
			var c = super._pick_from(s, deck, left)
			w.append(c)
			left.erase(c)
			deck.append(c)
	if arch == "thin":
		w = w.filter(func(c): return c.rank >= _deck_avg(s) + 2)
	return w


func _reward(e) -> void:
	var s = e.state
	if s.reward.has("choose"):
		super._reward(e)
		return
	if arch == "random" and not s.reward.get("menu", false):
		var opts: Array = s.reward["options"]
		var c = opts[rnd.randi() % opts.size()]
		if rnd.randf() < 0.3 and e.can_decline():
			e.reward_decline(c.id)
		else:
			e.reward_take(c.id)
		return
	if arch == "random" and s.reward.get("menu", false):
		var kinds: Array = ["take", "trade", "cull", "heal"].filter(func(k): return e.menu_can(k))
		var k: String = kinds[rnd.randi() % kinds.size()]
		var opts2: Array = s.reward["options"].duplicate()
		opts2.shuffle()
		if k != "take" and s.deck.size() <= int(s.balance["deck_min"]):
			k = "take"
		match k:
			"take":
				e.reward_menu(k, _ids(opts2.slice(0, int(s.reward["picks"]))))
			"trade":
				e.reward_menu(k, [opts2[0].id], [s.deck[rnd.randi() % s.deck.size()].id])
			"cull":
				e.reward_menu(k, [], [s.deck[rnd.randi() % s.deck.size()].id])
			_:
				e.reward_menu(k)
		return
	if arch == "fat" and not s.reward.get("menu", false) and not e.deck_full():
		var opts3: Array = s.reward["options"]
		var c3 = _pick_from(s, s.deck, opts3)
		var keep: bool = true
		if not keep and e.can_decline():
			e.reward_decline(c3.id)
		else:
			e.reward_take(c3.id)
		return
	if arch == "thin" and not s.reward.get("menu", false) and not e.deck_full():
		var opts4: Array = s.reward["options"]
		var c4 = _pick_from(s, s.deck, opts4)
		if c4.rank < _deck_avg(s) + 2 and e.can_decline():
			e.reward_decline(c4.id)
		else:
			e.reward_take(c4.id)
		return
	super._reward(e)
