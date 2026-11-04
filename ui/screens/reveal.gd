extends Control
## Run start: the mod ace and the theme king are flipped face up and explained.
## With the Rik mod the player also picks an extra three here.

const Style := preload("res://ui/style.gd")
const CardView := preload("res://ui/card_view.gd")
const GameState := preload("res://engine/game_state.gd")
const Phase := GameState.Phase

var main
var _v: VBoxContainer
var _pick_row: HBoxContainer
var _start: Button
var _pick_id := -1  # Rich mod: the three tapped so far (confirmed with the main button)
var _pick_label: Label


func enter() -> void:
	var s = main.engine.state
	var m := Style.full(MarginContainer.new())
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 28)
	m.add_theme_constant_override("margin_top", 50)
	m.add_theme_constant_override("margin_bottom", 40)
	add_child(m)
	_v = VBoxContainer.new()
	_v.add_theme_constant_override("separation", 14)
	m.add_child(_v)
	_v.add_child(Style.label("Seed %d" % s.seed_value, 22, Style.MUTED))

	var mod_ev := _find_event("mod_revealed")
	var theme_ev := _find_event("theme_revealed")
	_v.add_child(_reveal_block(s.mod_ace, "MOD ACE", mod_ev.get("name", "") if mod_ev.get("active", true) else "Mods disabled",
		mod_ev.get("desc", "") if mod_ev.get("active", true) else "", 0.3))
	var jt := ""
	if theme_ev.get("active", true):
		jt = "Red joker (after the Jack floor): %s\nBlack joker (boss): %s" % [theme_ev.get("red", ""), theme_ev.get("black", "")]
	else:
		jt = "Jokers disabled"
	_v.add_child(_reveal_block(s.theme_king, "THEME KING", "King of " + Style.SUIT_NAME.get(s.theme_suit, ""), jt, 0.9))

	var lives := "Lives: " + "  ".join(s.lives.map(func(a): return "A" + Style.SUIT_SYM[a.suit]))
	_v.add_child(Style.label(lives, 26, Style.WHITE))

	_pick_label = Style.label("Rich: pick an extra three for your starting deck", 26, Style.GOLD)
	_v.add_child(_pick_label)
	_pick_row = HBoxContainer.new()
	_pick_row.alignment = BoxContainer.ALIGNMENT_CENTER
	# Room above the cards so the selected (lifted) card doesn't cover the caption.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 44)
	pad.add_child(_pick_row)
	_v.add_child(pad)

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
	_update_pick()


## Tapping a three selects it (lifted + gold, like in a fight); the main button confirms.
func _on_pick(id: int) -> void:
	_pick_id = -1 if _pick_id == id else id
	main.sfx.play("select")
	_update_pick()


func _update_pick() -> void:
	var s = main.engine.state
	if s.phase != Phase.SETUP_PICK:
		_start.text = "To battle!"
		_start.disabled = false
		return
	for c in _pick_row.get_children():
		var cv := c as CardView
		if cv:
			cv.set_selected(cv.card_id == _pick_id)
			cv.highlight = Style.GOLD if cv.card_id == _pick_id else Color(0, 0, 0, 0)
	var picked = s.find_in(s.setup_options, _pick_id)
	_start.disabled = picked == null
	_start.text = "Take %s" % picked.label() if picked != null else "Pick a three"


func _on_start() -> void:
	var s = main.engine.state
	if s.phase == Phase.SETUP_PICK:
		if _pick_id < 0:
			return
		var id := _pick_id
		_pick_id = -1
		main.sfx.play("reward")
		main.act(func(): main.engine.setup_pick(id))
		return
	main.sfx.play("play")
	main.act(func(): main.engine.ack_reveal())


func _reveal_block(card, title: String, name: String, desc: String, delay: float) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	var cv := CardView.new()
	cv.set_interactive(false)
	cv.setup(card, Vector2(170, 238))
	cv.face_up = false
	h.add_child(cv)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(Style.label(title, 24, Style.MUTED, HORIZONTAL_ALIGNMENT_LEFT))
	var nl := Style.label(name, 40, Style.GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	tv.add_child(nl)
	var dl := Style.label(desc, 22, Style.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
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
