extends "res://tests/test_base.gd"
## Save & resume: a run is rebuilt from its seed and action journal.

const Bot := preload("res://engine/bot.gd")


func test_replay_matches_every_step() -> void:
	for seed in [3, 41, 977]:
		var e := GameEngine.new()
		e.start_run(seed)
		var bot := Bot.new()
		var steps := 0
		while e.state.result == "" and steps < 300:
			bot.step(e)
			steps += 1
			if steps % 7 == 0 or e.state.result != "":
				var copy := GameEngine.new()
				check(copy.restore(e.snapshot()), "seed %d step %d replays" % [seed, steps])
				eq(copy.fingerprint(), e.fingerprint(), "seed %d step %d" % [seed, steps])
				eq(copy.state.events.size(), e.state.events.size(), "event log restored")
		check(e.state.result != "", "seed %d finished" % seed)


func test_nested_actions_are_journaled_once() -> void:
	var e := GameEngine.new()
	e.start_run(5)
	while e.state.phase == Phase.SETUP_PICK:
		e.setup_pick(e.state.setup_options[0].id)
	e.ack_reveal()
	var n := e.journal.size()
	e.resolve()  # may call retain() itself
	eq(e.journal.size(), n + 1, "one entry for resolve")
	check(not e.play_cards([99999]), "bad action fails")
	eq(e.journal.size(), n + 1, "failed actions are not journaled")


func test_snapshot_survives_text_round_trip() -> void:
	var e := GameEngine.new()
	e.start_run(12, classic({"lives": 2}), {"force_mod": "S"})
	while e.state.phase == Phase.SETUP_PICK:
		e.setup_pick(e.state.setup_options[0].id)
	e.ack_reveal()
	var snap = str_to_var(var_to_str(e.snapshot()))
	var copy := GameEngine.new()
	check(copy.restore(snap), "restores from text")
	eq(copy.fingerprint(), e.fingerprint())
	eq(copy.state.mod_suit, "S", "options kept")


func test_bad_snapshot_is_rejected() -> void:
	var e := GameEngine.new()
	e.start_run(8)
	var snap := e.snapshot()
	snap["check"] = "nope"
	check(not GameEngine.new().restore(snap), "wrong check value")
	check(not GameEngine.new().restore({}), "empty")
	var s2 := e.snapshot()
	s2["journal"] = [["_finish_reward", []]]
	check(not GameEngine.new().restore(s2), "unknown action")
