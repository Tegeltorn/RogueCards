extends SceneTree
## Headless simulation with the playtest bot.
##   godot --headless --script res://sim/run_sim.gd -- --runs 20000
## Options:
##   --runs N            number of runs (default 20000)
##   --seed S            first seed (default 1)
##   --no-mods
##   --heart-carry next_round|next_attack
##   --set key=value     override any balance key (repeatable), e.g. --set burn_mode="swap"
##   --preset path       load a balance JSON (e.g. res://config/presets/spec.json)
##   --out path          also write the report (markdown) to a file
##   --force-mod S       every run uses the mod ace of suit S (H, D, S, C)
##   --mods path         load mods from another JSON file (for tuning mod parameters)

const SimLib := preload("res://sim/sim_lib.gd")
const Balance := preload("res://engine/balance.gd")


func _init() -> void:
	var args := SimLib.parse_args(OS.get_cmdline_user_args())
	var runs := int(args.get("runs", "20000"))
	var seed0 := int(args.get("seed", "1"))
	var ov := {}
	var run_opts := {}
	if args.has("force-mod"):
		run_opts["force_mod"] = args["force-mod"]
	if args.has("mods"):
		Balance.mods_path = args["mods"]
	if args.has("preset"):
		ov = Balance.load_json(args["preset"])
	var t0 := Time.get_ticks_msec()
	if args.has("no-mods"):
		ov["mods_enabled"] = false
	if args.has("heart-carry"):
		ov["heart_carry_mode"] = args["heart-carry"]
	SimLib.apply_sets(ov, args["set"])
	var st := SimLib.run_batch(Balance.make(ov), runs, seed0, run_opts)
	var text := SimLib.format_report("Current balance" + (" (" + str(ov) + ")" if not ov.is_empty() else ""), st)
	text += "\n\n(%d ms)" % (Time.get_ticks_msec() - t0)
	print(text)
	if args.has("out"):
		var f := FileAccess.open(args["out"], FileAccess.WRITE)
		if f:
			f.store_string(text + "\n")
	quit(0)
