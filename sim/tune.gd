extends SceneTree
## Sweeps tabletop-visible balance knobs and lists configs whose bot win rate lands in the target band.
##   godot --headless --script res://sim/tune.gd -- --runs 600 --final-runs 5000
## Only knobs a player can see on the table are swept (see RULES.md "Tabletop constraint").

const SimLib := preload("res://sim/sim_lib.gd")
const Balance := preload("res://engine/balance.gd")

const GRID := {
	"burn_mode": ["double", "swap"],
	"burn_limit": [0, 1],
	"perfect_draw": [0, 1],
	"overpower_draw": [0, 1],
	"lives": [2, 3],
}


func _init() -> void:
	var args := SimLib.parse_args(OS.get_cmdline_user_args())
	var runs := int(args.get("runs", "600"))
	var final_runs := int(args.get("final-runs", "5000"))
	var top_n := int(args.get("top", "6"))
	# Sweeps around the current balance.json ("base"); --preset compares against another file.
	var spec_raw := Balance.load_json(args.get("preset", Balance.BALANCE_PATH))
	var spec := Balance.make(spec_raw)
	var band: Array = spec["target"]["bot_win_rate_band"]
	var lo := float(band[0]) * 100.0
	var hi := float(band[1]) * 100.0
	var mid := (lo + hi) / 2.0

	var combos: Array = [{}]
	for k in GRID:
		var next: Array = []
		for c in combos:
			for v in GRID[k]:
				var d: Dictionary = c.duplicate()
				d[k] = v
				next.append(d)
		combos = next
	print("Sweeping %d configs x %d runs, band %.0f-%.0f %%" % [combos.size(), runs, lo, hi])

	var scored: Array = []
	for c in combos:
		var st := SimLib.run_batch(Balance.make(_merge(spec_raw, c)), runs, 100000)
		var w := SimLib.win_rate(st)
		var changes := 0
		for k in c:
			if str(c[k]) != str(spec[k]):
				changes += 1
		scored.append({"cfg": c, "win": w, "changes": changes, "score": absf(w - mid) + 1.5 * changes})
	scored.sort_custom(func(a, b): return a["score"] < b["score"])

	var lines: Array = ["# Tuning sweep", "", "Band: %.0f-%.0f %% (bot, all mods on). Stage 1: %d runs/config." % [lo, hi, runs], ""]
	lines.append("| win % (stage 1) | changes | config |")
	lines.append("|---|---|---|")
	for r in scored.slice(0, 15):
		lines.append("| %.1f | %d | %s |" % [r["win"], r["changes"], _diff(r["cfg"], spec)])
	lines.append("")
	lines.append("## Final check (%d runs each)" % final_runs)
	var best = null
	for r in scored.slice(0, top_n):
		var st := SimLib.run_batch(Balance.make(_merge(spec_raw, r["cfg"])), final_runs, 1)
		var w := SimLib.win_rate(st)
		var min_mod := 100.0
		for s in SimLib.SUITS:
			min_mod = minf(min_mod, SimLib.pct(st["mod"][s][0], st["mod"][s][1]))
		var ok := w >= lo and w <= hi and min_mod >= 10.0
		lines.append("")
		lines.append(SimLib.format_report("%s %s" % ["✅" if ok else "❌", _diff(r["cfg"], spec)], st))
		if ok and best == null:
			best = r["cfg"]
	lines.append("")
	lines.append("**Recommended:** " + (_diff(best, spec) if best != null else "none in band — widen GRID"))
	var text := "\n".join(lines)
	print(text)
	if args.has("out"):
		var f := FileAccess.open(args["out"], FileAccess.WRITE)
		if f:
			f.store_string(text + "\n")
	quit(0)


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate(true)
	for k in b:
		out[k] = b[k]
	return out


func _diff(c: Dictionary, spec: Dictionary) -> String:
	var parts: Array = []
	for k in c:
		if str(c[k]) != str(spec[k]):
			parts.append("%s=%s" % [k, JSON.stringify(c[k])])
	return "base values" if parts.is_empty() else ", ".join(parts)
