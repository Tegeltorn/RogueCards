extends RefCounted
## Batch simulation helpers shared by run_sim.gd and tune.gd.

const GameEngine := preload("res://engine/engine.gd")
const Bot := preload("res://engine/bot.gd")
const Balance := preload("res://engine/balance.gd")
const SUITS := ["H", "D", "S", "C"]
const SYM := {"H": "♥", "D": "♦", "S": "♠", "C": "♣"}


static func run_batch(balance: Dictionary, runs: int, seed0: int = 1, options: Dictionary = {}) -> Dictionary:
	var bot := Bot.new()
	var st := {"runs": runs, "wins": 0, "loops": 0, "stuck": 0, "loss_floor": {},
		"mod": {}, "lives_left": 0, "burns": 0, "rounds": 0}
	for s in SUITS:
		st["mod"][s] = [0, 0]
	for i in runs:
		var e := GameEngine.new()
		e.record_events = false
		e.start_run(seed0 + i, balance, options)
		bot.play_run(e)
		var res: String = e.state.result
		var md: String = e.state.mod_suit
		st["mod"][md][1] += 1
		st["burns"] += e.state.burned_total
		st["rounds"] += e.state.round_num
		if res == "win":
			st["wins"] += 1
			st["mod"][md][0] += 1
			st["lives_left"] += e.state.lives.size()
		else:
			if res == "loop":
				st["loops"] += 1
			elif res == "stuck":
				st["stuck"] += 1
			var f: int = e.state.floor_num
			st["loss_floor"][f] = st["loss_floor"].get(f, 0) + 1
	return st


static func pct(a: int, b: int) -> float:
	return 0.0 if b == 0 else snappedf(100.0 * a / b, 0.1)


static func win_rate(st: Dictionary) -> float:
	return pct(st["wins"], st["runs"])


static func format_report(title: String, st: Dictionary) -> String:
	var n: int = st["runs"]
	var lines: Array = []
	lines.append("### " + title)
	lines.append("Runs: %d   Win: %.1f %%   Stuck (unbreakable shield): %.1f %%   Loops: %d" % [n, win_rate(st), pct(st["stuck"], n), st["loops"]])
	lines.append("Per run: %.1f rounds, %.2f burns" % [float(st["rounds"]) / maxi(n, 1), float(st["burns"]) / maxi(n, 1)])
	var md := "Win per mod:  "
	for s in SUITS:
		var v: Array = st["mod"][s]
		md += "  %s %.1f" % [SYM[s], pct(v[0], v[1])]
	lines.append(md)
	var lf := "Losses per floor (% of all runs):"
	for f in range(3, 14):
		var c: int = st["loss_floor"].get(f, 0)
		if c == 0:
			continue
		lf += "  %s:%.1f" % [_floor_name(f), pct(c, n)]
	lines.append(lf)
	return "\n".join(lines)


static func _floor_name(f: int) -> String:
	return {11: "J", 12: "Q", 13: "K"}.get(f, str(f))


## Parses "--key value" / "--flag" style user args into a dictionary. Repeated --set accumulate.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {"set": []}
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			var val := "true"
			if i + 1 < args.size() and not args[i + 1].begins_with("--"):
				val = args[i + 1]
				i += 1
			if key == "set":
				out["set"].append(val)
			else:
				out[key] = val
		i += 1
	return out


## "key=value" → typed override using JSON parsing for the value.
static func apply_sets(overrides: Dictionary, sets: Array) -> void:
	for s in sets:
		var parts: PackedStringArray = String(s).split("=", true, 1)
		if parts.size() != 2:
			continue
		var v = JSON.parse_string(parts[1])
		overrides[parts[0]] = v if v != null else parts[1]
