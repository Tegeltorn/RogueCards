extends Control
## End of run: a comment on how close it was and the best run so far, then floor reached,
## lives left, mod ace, seed and final deck.

const Style := preload("res://ui/style.gd")
const CardView := preload("res://ui/card_view.gd")

var main


func enter() -> void:
	var s = main.engine.state
	var won: bool = s.result == "win"
	var m := Style.full(MarginContainer.new())
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 30)
	m.add_theme_constant_override("margin_top", 60)
	m.add_theme_constant_override("margin_bottom", 40)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	m.add_child(v)
	var t := Style.label("VICTORY!" if won else "DEFEAT", 88, Style.GOLD if won else Style.RED)
	t.add_theme_constant_override("outline_size", 10)
	v.add_child(t)
	for line in comments(s, main.last_record):
		var c := Style.label(line, 30, Style.GOLD if won else Style.WHITE)
		c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(c)
	var rows := [
		["Floor", "King (won)" if won else Style.floor_text(s.floor_num)],
		["Lives left", str(s.lives.size())],
		["Mod ace", Style.SUIT_SYM[s.mod_suit] + " " + _mod_name()],
		["Seed", str(s.seed_value)],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	for r in rows:
		for part in [[r[0], Style.MUTED, HORIZONTAL_ALIGNMENT_RIGHT], [r[1], Style.WHITE, HORIZONTAL_ALIGNMENT_LEFT]]:
			var l := Style.label(part[0], 30, part[1], part[2])
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			grid.add_child(l)
	var center := CenterContainer.new()
	center.add_child(grid)
	v.add_child(center)
	v.add_child(Style.label("Final deck", 28, Style.MUTED))
	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	var i := 0
	for c in s.deck:
		var cv := CardView.new()
		cv.set_interactive(false)
		cv.setup(c, Vector2(100, 140))
		flow.add_child(cv)
		cv.land(0.3 + i * 0.06)
		i += 1
	v.add_child(flow)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var again := Style.button("New run", Style.RED, 36)
	again.custom_minimum_size.y = 92
	again.pressed.connect(func(): main.new_run())
	v.add_child(again)
	var h := HBoxContainer.new()
	var same := Style.button("Same seed", Style.BLUE, 26)
	same.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	same.pressed.connect(func(): main.new_run(s.seed_value))
	h.add_child(same)
	var log := Style.button("Log", Style.BLACK, 26)
	log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log.pressed.connect(func(): main.open_log())
	h.add_child(log)
	var menu := Style.button("Menu", Style.BLACK, 26)
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.pressed.connect(func(): main.quit_to_menu())
	h.add_child(menu)
	v.add_child(h)


## "floor 9" / "the Queen floor".
static func floor_phrase(f: int) -> String:
	return "the %s floor" % {11: "Jack", 12: "Queen", 13: "King"}[f] if f >= 11 else "floor %d" % f


## End-of-run comments: how close a loss came, and the run against the best one so far.
## `rec` is Store.record_run()'s result ({prev_best, best}); empty when it wasn't recorded.
static func comments(s, rec: Dictionary) -> Array:
	var out: Array = []
	var won: bool = s.result == "win"
	if not won:
		# Enemy cards still to beat: the rest of this floor plus four on every floor after it.
		var left: int = s.enemy_pile.size() + s.current.size() + 4 * (13 - int(s.floor_num))
		if s.floor_num == 13:
			out.append("So close! Only %d %s left to beat." % [left, "king" if left == 1 else "kings"])
		else:
			out.append("%d enemy cards from victory." % left)
	if not rec.is_empty():
		var prog: int = 14 if won else int(s.floor_num)
		var prev: int = int(rec.get("prev_best", 0))
		if prev > 0 and prog > prev:
			out.append("New best! " + ("Your first win." if won and prev < 14 else "Furthest you have ever come."))
		elif prev > 0 and not won:
			out.append("Best so far: " + ("a win" if prev >= 14 else floor_phrase(prev)) + ".")
	return out


func _mod_name() -> String:
	for e in main.engine.state.events:
		if e["type"] == "mod_revealed":
			return e.get("name", "")
	return ""
