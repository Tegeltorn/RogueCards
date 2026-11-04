extends RefCounted
## Minimal test base: methods named test_* are run by tests/run_tests.gd.

const GameEngine := preload("res://engine/engine.gd")
const Card := preload("res://engine/card.gd")
const Balance := preload("res://engine/balance.gd")
const GameState := preload("res://engine/game_state.gd")
const Ev := preload("res://engine/events.gd")
const Phase := GameState.Phase

var failures: Array = []
var current_test := ""


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current_test, msg])


func eq(actual, expected, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: %s expected %s, got %s" % [current_test, msg, str(expected), str(actual)])


## Engine started with mods off (unless given) and a scripted round. The tests pin a few values
## (3 lives, overpower draws 1, deck minimum 4) so they don't move with balance tuning.
## Card specs are strings like "7S", "12H", "2D".
func scenario(hand: Array, enemies: Array, over: Dictionary = {}, opts: Dictionary = {}) -> GameEngine:
	var b := {"mods_enabled": false, "lives": 3, "overpower_draw": 1, "deck_min": 4}
	for k in over:
		b[k] = over[k]
	var e := GameEngine.new()
	e.start_run(int(opts.get("seed", 1)), Balance.make(b), opts)
	while e.state.phase == Phase.SETUP_PICK:
		e.setup_pick(e.state.setup_options[0].id)
	e.ack_reveal()
	set_round(e, hand, enemies, opts.get("pile", []))
	return e


func set_round(e: GameEngine, hand: Array, enemies: Array, pile: Array = []) -> void:
	var s := e.state
	s.hand = cards(e, hand)
	s.deck = s.hand.duplicate()
	s.draw_pile = []
	s.discard = []
	s.played = []
	s.current = cards(e, enemies)
	s.enemy_pile = cards(e, pile)
	s.phase = Phase.PLAY


func card(e: GameEngine, spec: String):
	var c = e._new_card(int(spec.left(spec.length() - 1)), spec.right(1))
	return c


func cards(e: GameEngine, specs: Array) -> Array:
	var out: Array = []
	for s in specs:
		out.append(card(e, s))
	return out


func ids(arr: Array) -> Array:
	var out: Array = []
	for c in arr:
		out.append(c.id)
	return out


func has_event(e: GameEngine, type: String) -> bool:
	for ev in e.state.events:
		if ev["type"] == type:
			return true
	return false
