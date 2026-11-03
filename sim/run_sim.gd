extends SceneTree
## Headless simulation with the spec bot.
##   godot --headless --script res://sim/run_sim.gd -- --runs 20000
## Options:
##   --runs N            number of runs (default 20000)
##   --seed S            first seed (default 1)
##   --no-mods / --no-jokers
##   --heart-carry next_round|next_attack
##   --set key=value     override any balance key (repeatable), e.g. --set deck_cap=6
##   --preset path       load a balance JSON (e.g. res://config/presets/spec.json)
##   --parity            settings that match sim/reference/balance_sim.py and print its numbers
##   --all               default report + parity report
##   --out path          also write the report (markdown) to a file

const SimLib := preload("res://sim/sim_lib.gd")
const Balance := preload("res://engine/balance.gd")


func _init() -> void:
	var args := SimLib.parse_args(OS.get_cmdline_user_args())
	var runs := int(args.get("runs", "20000"))
	var seed0 := int(args.get("seed", "1"))
	var base := {}
	if args.has("preset"):
		base = Balance.load_json(args["preset"])
	var reports: Array = []
	var t0 := Time.get_ticks_msec()

	if not args.has("parity") or args.has("all"):
		var ov := base.duplicate(true)
		if args.has("no-mods"):
			ov["mods_enabled"] = false
		if args.has("no-jokers"):
			ov["jokers_enabled"] = false
		if args.has("heart-carry"):
			ov["heart_carry_mode"] = args["heart-carry"]
		SimLib.apply_sets(ov, args["set"])
		var bal := Balance.make(ov)
		var st := SimLib.run_batch(bal, runs, seed0)
		reports.append(SimLib.format_report("Current balance" + (" (" + str(ov) + ")" if not ov.is_empty() else ""), st))

	if args.has("parity") or args.has("all"):
		var ov2 := base.duplicate(true)
		for k in SimLib.PARITY:
			ov2[k] = SimLib.PARITY[k]
		SimLib.apply_sets(ov2, args["set"])
		var st2 := SimLib.run_batch(Balance.make(ov2), runs, seed0)
		reports.append(SimLib.format_report("Parity with Python reference (no mods, ♥ carry until next attack, any-colour ace)", st2, true))

	var text := "\n\n".join(reports)
	text += "\n\n(%d ms)" % (Time.get_ticks_msec() - t0)
	print(text)
	if args.has("out"):
		var f := FileAccess.open(args["out"], FileAccess.WRITE)
		if f:
			f.store_string(text + "\n")
	quit(0)
