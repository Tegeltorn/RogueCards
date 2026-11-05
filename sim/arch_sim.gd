extends SceneTree
## Win rate per deck-building archetype (see sim/archetype_bot.gd).
##   godot --headless --path . --script res://sim/arch_sim.gd -- --runs 2000 [--archs smart,H,D,S,C,thin,fat,random] [--preset path] [--set key=value]

const SimLib := preload("res://sim/sim_lib.gd")
const Balance := preload("res://engine/balance.gd")
const GameEngine := preload("res://engine/engine.gd")
const ArchBot := preload("res://sim/archetype_bot.gd")


func _init() -> void:
	var args := SimLib.parse_args(OS.get_cmdline_user_args())
	var runs := int(args.get("runs", "2000"))
	var archs: PackedStringArray = str(args.get("archs", "smart,H,D,S,C,thin,fat,random")).split(",")
	var ov := {}
	if args.has("preset"):
		ov = Balance.load_json(args["preset"])
		ov.erase("_note")
	SimLib.apply_sets(ov, args["set"])
	var bal := Balance.make(ov)
	var line := "%s |" % str(ov)
	for a in archs:
		var bot := ArchBot.new(a)
		var wins := 0
		var deck := 0
		for i in runs:
			var e := GameEngine.new()
			e.record_events = false
			e.start_run(700000 + i, bal)
			bot.play_run(e)
			if e.state.result == "win":
				wins += 1
			deck += e.state.deck.size()
		line += " %s %.1f (deck %.1f) |" % [a, 100.0 * wins / runs, float(deck) / runs]
	print(line)
	quit(0)
