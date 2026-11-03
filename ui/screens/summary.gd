extends Control
## End of run: floor reached, lives left, theme king, mod ace, seed and final deck.

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
	var t := Style.label("SEGER!" if won else "FÖRLUST", 88, Style.GOLD if won else Style.RED)
	t.add_theme_constant_override("outline_size", 16)
	v.add_child(t)
	var rows := [
		["Våning", "Kungen (vann)" if won else Style.floor_text(s.floor_num)],
		["Liv kvar", str(s.lives.size())],
		["Temakung", Style.SUIT_SYM[s.theme_suit] + " " + Style.SUIT_NAME[s.theme_suit]],
		["Modess", Style.SUIT_SYM[s.mod_suit] + " " + _mod_name()],
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
	v.add_child(Style.label("Slutlek", 28, Style.MUTED))
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
	var again := Style.button("Ny omgång", Style.RED, 36)
	again.custom_minimum_size.y = 92
	again.pressed.connect(func(): main.new_run())
	v.add_child(again)
	var h := HBoxContainer.new()
	var same := Style.button("Samma seed", Style.BLUE, 26)
	same.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	same.pressed.connect(func(): main.new_run(s.seed_value))
	h.add_child(same)
	var log := Style.button("Logg", Style.BLACK, 26)
	log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log.pressed.connect(func(): main.open_log())
	h.add_child(log)
	var menu := Style.button("Meny", Style.BLACK, 26)
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.pressed.connect(func(): main.quit_to_menu())
	h.add_child(menu)
	v.add_child(h)


func _mod_name() -> String:
	for e in main.engine.state.events:
		if e["type"] == "mod_revealed":
			return e.get("name", "")
	return ""
