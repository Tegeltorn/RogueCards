extends RefCounted
## Batch simulation helpers shared by run_sim.gd and tune.gd.

const GameEngine := preload("res://engine/engine.gd")
const Bot := preload("res://engine/bot.gd")
const Balance := preload("res://engine/balance.gd")
const SUITS := ["H", "D", "S", "C"]
const SYM := {"H": "♥", "D": "♦", "S": "♠", "C": "♣"}

## Reference numbers from sim/reference/balance_sim_fixed.py (20 000 runs, CURRENT rules, no mods).
## The original balance_sim.py reported 34.8 %, but it lost black cards drawn by diamonds (see the fixed copy).
const PY_REFERENCE := {
	"win": 65.0,
	"theme": {"H": 67.5, "D": 60.3, "S": 63.5, "C": 68.6},
	"loss_floor": {5: 2.4, 6: 5.9, 7: 7.6, 8: 3.9, 9: 3.5, 10: 2.9, 11: 2.6, 12: 1.5, 13: 4.6},
}

## Balance overrides that make the GDScript engine match the Python model.
const PARITY := {"mods_enabled": false, "heart_carry_mode": "next_attack", "ace_sac_own_color": false}


static func run_batch(balance: Dictionary, runs: int, seed0: int = 1, options: Dictionary = {}) -> Dictionary:
	var bot := Bot.new()
	var st := {"runs": runs, "wins": 0, "loops": 0, "loss_floor": {},
		"theme": {}, "mod": {}, "lives_left": 0, "sacs": 0}
	for s in SUITS:
		st["theme"][s] = [0, 0]
		st["mod"][s] = [0, 0]
	for i in runs:
		var e := GameEngine.new()
		e.record_events = false
		e.start_run(seed0 + i, balance, options)
		bot.play_run(e)
		var res: String = e.state.result
		var th: String = e.state.theme_suit
		var md: String = e.state.mod_suit
		st["theme"][th][1] += 1
		st["mod"][md][1] += 1
		if res == "win":
			st["wins"] += 1
			st["theme"][th][0] += 1
			st["mod"][md][0] += 1
			st["lives_left"] += e.state.lives.size()
		else:
			if res == "loop":
				st["loops"] += 1
			var f: int = e.state.floor_num
			st["loss_floor"][f] = st["loss_floor"].get(f, 0) + 1
	return st


static func pct(a: int, b: int) -> float:
	return 0.0 if b == 0 else snappedf(100.0 * a / b, 0.1)


static func win_rate(st: Dictionary) -> float:
	return pct(st["wins"], st["runs"])


static func format_report(title: String, st: Dictionary, show_reference: bool = false) -> String:
	var n: int = st["runs"]
	var lines: Array = []
	lines.append("### " + title)
	lines.append("Runs: %d   Win: %.1f %%   Loops: %d" % [n, win_rate(st), st["loops"]])
	if show_reference:
		lines.append("Python reference: %.1f %%" % PY_REFERENCE["win"])
	var th := "Win per theme:"
	for s in SUITS:
		var v: Array = st["theme"][s]
		th += "  %s %.1f" % [SYM[s], pct(v[0], v[1])]
		if show_reference:
			th += " (py %.1f)" % PY_REFERENCE["theme"][s]
	lines.append(th)
	var md := "Win per mod:  "
	for s in SUITS:
		var v: Array = st["mod"][s]
		md += "  %s %.1f" % [SYM[s], pct(v[0], v[1])]
	lines.append(md)
	var lf := "Losses per floor (% of all runs):"
	for f in range(3, 14):
		var c: int = st["loss_floor"].get(f, 0)
		if c == 0 and not (show_reference and PY_REFERENCE["loss_floor"].has(f)):
			continue
		lf += "  %s:%.1f" % [_floor_name(f), pct(c, n)]
		if show_reference and PY_REFERENCE["loss_floor"].has(f):
			lf += "(py %.1f)" % PY_REFERENCE["loss_floor"][f]
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
