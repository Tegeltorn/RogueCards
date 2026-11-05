extends SceneTree
## Shared design metrics for RogueCards rule experiments (read-only: does not change the project).
##   godot --headless --path . --script res://sim/design_metrics.gd -- --runs 2000 [--preset res://config/presets/combo.json] [--set key=value ...] [--bot res://engine/bot.gd]
## Reports, with the bot playing:
##   win %, stuck %, rounds per run
##   decision space at the first look of each round: hopeless (no way to beat the enemy card),
##     forced (exactly one way), choice (2+ ways) -> "dead" = hopeless, "no real choice" = hopeless + forced
##   deck-building weight: win % with the bot's reward picks vs random picks vs never taking a card
##   tension: % of losses on the Queen/King floors (near misses), % of runs dying on floors <= 6 (early deaths)
## The plan counter tries every hand card as skip / play (if it counts) / burn (if allowed), at most
## 2 burns; extend `count_plans` if a variant adds new per-card actions.

const Balance := preload("res://engine/balance.gd")
const SimLib := preload("res://sim/sim_lib.gd")
const Phase := preload("res://engine/game_state.gd").Phase

var rnd := RandomNumberGenerator.new()


func _init() -> void:
	var args := SimLib.parse_args(OS.get_cmdline_user_args())
	var runs := int(args.get("runs", "2000"))
	var ov := {}
	if args.has("preset"):
		ov = Balance.load_json(args["preset"])
		ov.erase("_note")
	SimLib.apply_sets(ov, args["set"])
	var bal := Balance.make(ov)
	var Bot = load(args.get("bot", "res://engine/bot.gd"))
	var Eng = load(args.get("engine", "res://engine/engine.gd"))
	print("## Metrics %s (%d runs)" % [str(ov), runs])
	var m := detailed(Eng, Bot, bal, runs)
	print("win %.1f %%  stuck %.1f %%  rounds/run %.1f" % [m["win"], m["stuck"], m["rounds"]])
	print("rounds: hopeless(dead) %.1f %%  forced %.1f %%  choice %.1f %%  -> no real choice %.1f %%" % [m["hopeless"], m["forced"], m["choice"], m["hopeless"] + m["forced"]])
	print("A-extra: failed rounds (enemy card not beaten) %.1f %%  real choice (2+ minimal plans) %.1f %%  lives lost/run %.2f  digs/run %.2f" % [m["failed"], m["minchoice"], m["lost"], m["digs"]])
	print("tension: losses on Q/K %.1f %% of losses  early deaths (floor <= 6) %.1f %% of runs" % [m["late_loss"], m["early"]])
	var rand_w := variant(Eng, Bot, bal, runs / 2, "random")
	var never_w := variant(Eng, Bot, bal, runs / 2, "never")
	print("deck building: smart picks %.1f %%  random picks %.1f %%  never take %.1f %%  (spread %.1f)" % [m["win"], rand_w, never_w, m["win"] - minf(rand_w, never_w)])
	quit(0)


func detailed(Eng, Bot, bal: Dictionary, runs: int) -> Dictionary:
	var bot = Bot.new()
	var c := {"wins": 0, "stuck": 0, "rounds": 0, "hopeless": 0, "forced": 0, "choice": 0, "looks": 0,
		"losses": 0, "late": 0, "early": 0, "beaten": 0, "minchoice": 0, "lost": 0, "digs": 0}
	for i in runs:
		var e = Eng.new()
		e.record_events = false
		e.start_run(500000 + i, bal)
		var last := ""
		var guard := 0
		var pf := -1
		var pb := 0
		while guard < 20000:
			guard += 1
			var s = e.state
			if s.floor_num != pf:
				pf = s.floor_num
				pb = 0
			if s.beaten.size() > pb:
				c["beaten"] += s.beaten.size() - pb
				pb = s.beaten.size()
			elif s.beaten.size() < pb:
				pb = s.beaten.size()
			if s.phase == Phase.PLAY and s.played.is_empty():
				var key := "%d:%d" % [s.floor_num, s.round_num]
				if key != last:
					last = key
					var n := count_plans(e)
					if minimal_plans(e) >= 2:
						c["minchoice"] += 1
					c["looks"] += 1
					c["hopeless" if n == 0 else ("forced" if n == 1 else "choice")] += 1
			if not bot.step(e) or s.floor_round > 80:
				if s.floor_round > 80 and s.result == "":
					s.result = "stuck"
				break
		var s = e.state
		if s.beaten.size() > pb:
			c["beaten"] += s.beaten.size() - pb
		c["rounds"] += s.round_num
		c["lost"] += s.lost_lives.size()
		c["digs"] += s.burned_total
		if s.result == "win":
			c["wins"] += 1
		else:
			c["losses"] += 1
			if s.result == "stuck":
				c["stuck"] += 1
			if s.floor_num >= 12:
				c["late"] += 1
			if s.floor_num <= 6:
				c["early"] += 1
	var L: float = maxf(1.0, c["looks"])
	return {"win": 100.0 * c["wins"] / runs, "stuck": 100.0 * c["stuck"] / runs, "rounds": float(c["rounds"]) / runs,
		"hopeless": 100.0 * c["hopeless"] / L, "forced": 100.0 * c["forced"] / L, "choice": 100.0 * c["choice"] / L,
		"failed": 100.0 * (c["rounds"] - c["beaten"]) / maxf(1.0, c["rounds"]), "minchoice": 100.0 * c["minchoice"] / L,
		"lost": float(c["lost"]) / runs, "digs": float(c["digs"]) / runs,
		"late_loss": 100.0 * c["late"] / maxf(1.0, c["losses"]), "early": 100.0 * c["early"] / runs}


## Win % when reward choices are random ("random") or always declined ("never").
func variant(Eng, Bot, bal: Dictionary, runs: int, mode: String) -> float:
	var bot = Bot.new()
	var wins := 0
	rnd.seed = 99
	for i in runs:
		var e = Eng.new()
		e.record_events = false
		e.start_run(600000 + i, bal)
		var guard := 0
		while guard < 20000:
			guard += 1
			var s = e.state
			if s.phase == Phase.WON or s.phase == Phase.LOST or s.floor_round > 80:
				break
			if s.phase == Phase.REWARD and e.has_method("reward_resolve"):
				var opts: Array = s.reward.get("options", [])
				var picks: int = mini(int(s.reward.get("picks", 0)), opts.size())
				var take: Array = []
				if mode == "random":
					var o2 := opts.duplicate()
					o2.shuffle()
					for k in picks:
						if rnd.randf() < 0.7:
							take.append(o2[k].id)
				var rem := -1
				if e.removal_needed(take.size()):
					rem = s.deck[rnd.randi() % s.deck.size()].id
				if e.reward_resolve(take, rem):
					continue
			if not bot.step(e):
				break
		if e.state.result == "win":
			wins += 1
	return 100.0 * wins / maxf(1.0, runs)


## Distinct ways to fully beat the revealed enemy card(s) with the current hand.
func count_plans(e) -> int:
	var hand: Array = e.state.hand.slice(0, 8)
	var maxb := 0
	if e.has_method("can_burn") and e.can_burn() and e.burn_mode() != "dig":
		var lim := int(e.state.balance.get("burn_limit", 0))
		maxb = lim if lim > 0 else 2
	return _rec(e, hand, 0, [], 0, maxb)


func _rec(e, hand: Array, i: int, chosen: Array, burns: int, maxb: int) -> int:
	if i == hand.size():
		if chosen.is_empty():
			return 0
		var t: Dictionary = e.compute(chosen)
		return 1 if int(t["block"]) >= int(t["block_need"]) and int(t["attack"]) >= int(t["attack_need"]) else 0
	var c = hand[i]
	var n := _rec(e, hand, i + 1, chosen, burns, maxb)
	if e.is_effective(c):
		chosen.append(c)
		n += _rec(e, hand, i + 1, chosen, burns, maxb)
		chosen.pop_back()
	if burns < maxb and "burned" in c:
		c.burned = true
		chosen.append(c)
		n += _rec(e, hand, i + 1, chosen, burns + 1, maxb)
		chosen.pop_back()
		c.burned = false
	return n


## Distinct minimal ways (no card can be left out) to beat the enemy card with the hand, no burns.
func minimal_plans(e) -> int:
	var hand: Array = e.state.hand.slice(0, 8)
	var eff: Array = hand.filter(func(x): return e.is_effective(x))
	var n := 0
	for mask in range(1, 1 << eff.size()):
		var chosen: Array = []
		for i in eff.size():
			if mask & (1 << i):
				chosen.append(eff[i])
		if not _ok(e, chosen):
			continue
		var minimal := true
		for i in chosen.size():
			var less := chosen.duplicate()
			less.remove_at(i)
			if not less.is_empty() and _ok(e, less):
				minimal = false
				break
		if minimal:
			n += 1
	return n


func _ok(e, chosen: Array) -> bool:
	var t: Dictionary = e.compute(chosen)
	return int(t["block"]) >= int(t["block_need"]) and int(t["attack"]) >= int(t["attack_need"])
