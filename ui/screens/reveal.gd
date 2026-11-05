extends Control
## Run start: the mod ace is flipped face up and explained.
## With the Rik mod the player also picks an extra three here.

const Style := preload("res://ui/style.gd")
const CardView := preload("res://ui/card_view.gd")
const Help := preload("res://ui/screens/help.gd")
const GameState := preload("res://engine/game_state.gd")
const Phase := GameState.Phase

var main
var _v: VBoxContainer
var _pick_row: HBoxContainer
var _start: Button
var _pick_ids: Array = []  # start pick: threes tapped so far (confirmed with the main button)
var _deck_row: HBoxContainer
var _tip: PanelContainer
var _deck_label: Label
var _pick_label: Label


func enter() -> void:
	var s = main.engine.state
	var m := Style.full(MarginContainer.new())
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 28)
	m.add_theme_constant_override("margin_top", 24)
	m.add_theme_constant_override("margin_bottom", 24)
	add_child(m)
	_v = VBoxContainer.new()
	_v.add_theme_constant_override("separation", 8)
	m.add_child(_v)
	_v.add_child(Style.label("Seed %d" % s.seed_value, 22, Style.MUTED))

	var mod_ev := _find_event("mod_revealed")
	_v.add_child(_reveal_block(s.mod_ace, "MOD ACE", mod_ev.get("name", "") if mod_ev.get("active", true) else "Mods disabled",
		mod_ev.get("desc", "") if mod_ev.get("active", true) else "", 0.3))

	var lives := "Lives: " + "  ".join(s.lives.map(func(a): return "A" + Style.SUIT_SYM[a.suit]))
	_v.add_child(Style.label(lives, 26, Style.WHITE))

	_pick_label = Style.label("", 26, Style.GOLD)
	_v.add_child(_pick_label)
	_pick_row = HBoxContainer.new()
	_pick_row.alignment = BoxContainer.ALIGNMENT_CENTER
	# Room above the cards so the selected (lifted) card doesn't cover the caption.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 44)
	pad.add_child(_pick_row)
	_v.add_child(pad)
	_tip = Help.tip_box()
	_v.add_child(_tip)
	var extra := int(s.balance.get("start_random", 0))
	_deck_label = Style.label("Your deck: the four twos" + ((" and %d threes dealt at random" % extra) if extra > 0 else ""), 22, Style.MUTED)
	_v.add_child(_deck_label)
	_deck_row = HBoxContainer.new()
	_deck_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_deck_row.add_theme_constant_override("separation", 8)
	_v.add_child(_deck_row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_v.add_child(spacer)
	_start = Style.button("To battle!", Style.RED, 36)
	_start.custom_minimum_size.y = 96
	_start.pressed.connect(_on_start)
	_v.add_child(_start)
	refresh()


func refresh() -> void:
	var s = main.engine.state
	var picking: bool = s.phase == Phase.SETUP_PICK
	_pick_label.visible = picking
	_pick_row.visible = picking
	if picking:
		_pick_label.text = "Pick a three for your starting deck" if s.setup_picks == 1 \
			else "Rich: keep %d threes for your starting deck" % s.setup_picks
	for c in _pick_row.get_children():
		c.queue_free()
	if picking:
		for i in s.setup_options.size():
			var card = s.setup_options[i]
			var cv := CardView.new()
			cv.setup(card, Vector2(120, 168))
			cv.tapped.connect(func(_v2): _on_pick(card.id))
			_pick_row.add_child(cv)
			cv.land(0.8 + i * 0.08)
	for c in _deck_row.get_children():
		c.queue_free()
	for c in s.deck:
		var cv := CardView.new()
		cv.set_interactive(false)
		cv.breathing = false
		cv.setup(c, Vector2(70, 98))
		_deck_row.add_child(cv)
	_update_pick()


## Tapping a three selects it (lifted + gold, like in a fight); the main button confirms.
func _on_pick(id: int) -> void:
	var picks: int = main.engine.state.setup_picks
	if _pick_ids.has(id):
		_pick_ids.erase(id)
	else:
		if _pick_ids.size() >= picks:
			_pick_ids.pop_front()
		_pick_ids.append(id)
	main.sfx.play("card")
	_update_pick()


func _update_pick() -> void:
	var s = main.engine.state
	var shown = s.find_in(s.setup_options, _pick_ids[-1]) if not _pick_ids.is_empty() else null
	Help.show_tip(_tip, s.balance, shown if s.phase == Phase.SETUP_PICK else null)
	if s.phase != Phase.SETUP_PICK:
		_start.text = "To battle!"
		_start.disabled = false
		return
	for c in _pick_row.get_children():
		var cv := c as CardView
		if cv:
			cv.set_selected(_pick_ids.has(cv.card_id))
			cv.highlight = Style.GOLD if _pick_ids.has(cv.card_id) else Color(0, 0, 0, 0)
	var labels: Array = []
	for id in _pick_ids:
		var c = s.find_in(s.setup_options, id)
		if c != null:
			labels.append(c.label())
	var need: int = s.setup_picks
	_start.disabled = labels.size() != need
	if labels.size() == need:
		_start.text = "Take " + " + ".join(labels)
	else:
		_start.text = "Pick a three" if need == 1 else "Pick %d threes" % need


func _on_start() -> void:
	var s = main.engine.state
	if main.is_busy():
		return
	if s.phase == Phase.SETUP_PICK:
		if _start.disabled:
			return
		var ids := _pick_ids.duplicate()
		_pick_ids.clear()
		main.sfx.play("reward")
		# Fly the chosen threes into the deck row, then apply.
		var kids := _deck_row.get_children()
		var target: Vector2 = kids[-1].get_global_rect().position + Vector2(78, 0) if not kids.is_empty() else _deck_row.get_global_rect().get_center()
		for i in ids.size():
			for c in _pick_row.get_children():
				var cv := c as CardView
				if cv and cv.card_id == ids[i]:
					cv.visible = false
					main.fly_card(s.find_in(s.setup_options, ids[i]), cv.get_global_rect(), target + Vector2(i * 78, 0), Vector2(70, 98))
		_start.disabled = true
		await get_tree().create_timer(0.5).timeout
		# The fight starts right after the pick.
		main.act(func():
			for id in ids:
				main.engine.setup_pick(id)
			if main.engine.state.phase == Phase.REVEAL:
				main.engine.ack_reveal())
		return
	main.sfx.play("play")
	main.act(func(): main.engine.ack_reveal())


func _reveal_block(card, title: String, name: String, desc: String, delay: float) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	var cv := CardView.new()
	cv.set_interactive(false)
	cv.setup(card, Vector2(140, 196))
	cv.face_up = false
	h.add_child(cv)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(Style.label(title, 24, Style.MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	var nl := Style.label(name, 40, Style.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	tv.add_child(nl)
	var dl := Style.label(desc, 20, Style.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	tv.add_child(dl)
	h.add_child(tv)
	tv.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		cv.flip_to(true, 0.4)
		main.sfx.play("flip"))
	tw.tween_interval(0.25)
	tw.tween_property(tv, "modulate:a", 1.0, 0.25)
	return h


func _find_event(type: String) -> Dictionary:
	for e in main.engine.state.events:
		if e["type"] == type:
			return e
	return {}
