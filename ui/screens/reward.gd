extends Control
## Between floors: reward pick (with swap when the deck is full), card removal (♣) and red joker attach.

const Style := preload("res://ui/style.gd")
const CardView := preload("res://ui/card_view.gd")
const GameState := preload("res://engine/game_state.gd")
const Ev := preload("res://engine/events.gd")
const Phase := GameState.Phase

const RULE_TEXT := {
	"S": "Välj fritt bland alla besegrade kort",
	"C": "Vänd upp 2, ta 1 – ta sedan bort 1 kort ur leken",
	"H": "Få tillbaka ett liv (alla liv: vänd upp 2, ta 1)",
	"D": "Vänd upp 2 och ta båda",
}

var main
var _e
var _v: VBoxContainer
var _title: Label
var _sub: Label
var _prompt: Label
var _opts: HFlowContainer
var _deck_label: Label
var _deck: HFlowContainer
var _skip: Button
var _swap_for := -1  # option id waiting for a deck card to replace


func enter() -> void:
	_e = main.engine
	var m := Style.full(MarginContainer.new())
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 24)
	m.add_theme_constant_override("margin_top", 40)
	m.add_theme_constant_override("margin_bottom", 30)
	add_child(m)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	m.add_child(scroll)
	_v = VBoxContainer.new()
	_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_v.add_theme_constant_override("separation", 16)
	scroll.add_child(_v)
	_title = Style.label("", 52, Style.GOLD)
	_title.add_theme_constant_override("outline_size", 12)
	_v.add_child(_title)
	_sub = Style.label("", 26, Style.WHITE)
	_v.add_child(_sub)
	_prompt = Style.label("", 28, Style.GOLD)
	_v.add_child(_prompt)
	_opts = HFlowContainer.new()
	_opts.alignment = FlowContainer.ALIGNMENT_CENTER
	_opts.add_theme_constant_override("h_separation", 16)
	_opts.add_theme_constant_override("v_separation", 16)
	_v.add_child(_opts)
	_skip = Style.button("Avstå", Style.BLACK, 28)
	_skip.pressed.connect(_on_skip)
	_v.add_child(_skip)
	_deck_label = Style.label("", 26, Style.MUTED)
	_v.add_child(_deck_label)
	_deck = HFlowContainer.new()
	_deck.alignment = FlowContainer.ALIGNMENT_CENTER
	_deck.add_theme_constant_override("h_separation", 10)
	_deck.add_theme_constant_override("v_separation", 10)
	_v.add_child(_deck)
	refresh()


func refresh() -> void:
	if _e == null:
		return
	var s = _e.state
	for c in _opts.get_children():
		c.queue_free()
	for c in _deck.get_children():
		c.queue_free()
	_title.text = "VÅNING %s KLAR" % Style.floor_text(s.floor_num)
	_skip.visible = false
	var deck_tap := Callable()
	match s.phase:
		Phase.REWARD:
			var r: Dictionary = s.reward
			var suit: String = r.get("suit", "S")
			_sub.text = "Sista kortet %s → %s" % [Style.SUIT_SYM[suit], RULE_TEXT[suit]]
			var healed: int = int(_last_offer().get("healed", 0))
			if healed > 0:
				_sub.text += "\nDu fick tillbaka %d liv!" % healed
			var picks := int(r.get("picks", 0))
			if _swap_for >= 0 and s.find_in(r["options"], _swap_for) != null:
				_prompt.text = "Leken är full: tryck på kortet som ska bytas ut"
				deck_tap = func(card): _take(_swap_for, card.id)
			else:
				_swap_for = -1
				_prompt.text = "Välj %d kort" % picks if picks > 1 else "Välj ett kort"
			for i in r["options"].size():
				var o = r["options"][i]
				var cv := CardView.new()
				cv.setup(o, Vector2(150, 210))
				cv.highlight = Style.GOLD if o.id == _swap_for else Color(0, 0, 0, 0)
				cv.tapped.connect(func(_x): _on_option(o))
				_opts.add_child(cv)
				cv.land(i * 0.08)
			_skip.visible = _e.can_decline()
			_skip.text = "Avstå" if _swap_for < 0 else "Avstå det här kortet"
		Phase.REWARD_REMOVE:
			_sub.text = "Klöverbelöning"
			_prompt.text = "Ta bort ett kort ur leken"
			deck_tap = func(card): main.act(func(): _e.reward_remove(card.id))
		Phase.JOKER_ATTACH:
			_title.text = "RÖD JOKER"
			_sub.text = _joker_desc()
			_prompt.text = "Fäst jokern under ett kort i leken"
			var jv := CardView.new()
			jv.set_interactive(false)
			jv.rank = 0
			jv.suit = "J"
			jv.setup(null, Vector2(150, 210))
			_opts.add_child(jv)
			jv.land()
			deck_tap = func(card): main.act(func(): _e.attach_joker(card.id))
	_deck_label.text = "Din lek (%d/%d)" % [s.deck.size(), int(s.balance["deck_cap"])]
	var sorted: Array = s.deck.duplicate()
	sorted.sort_custom(func(a, b): return a.suit < b.suit or (a.suit == b.suit and a.rank < b.rank))
	for c in sorted:
		var cv := CardView.new()
		cv.setup(c, Vector2(110, 154))
		cv.breathing = false
		if deck_tap.is_valid():
			var cb := deck_tap
			cv.tapped.connect(func(_x): cb.call(c))
			cv.highlight = Color(Style.GOLD, 0.6)
		else:
			cv.set_interactive(false)
		_deck.add_child(cv)


func _on_option(o) -> void:
	if main.is_busy():
		return
	main.sfx.play("select")
	if _e.deck_full():
		_swap_for = o.id
		refresh()
	else:
		_take(o.id, -1)


func _take(opt_id: int, replace_id: int) -> void:
	_swap_for = -1
	main.sfx.play("reward")
	main.act(func(): _e.reward_take(opt_id, replace_id))


func _on_skip() -> void:
	if _swap_for >= 0:
		var id := _swap_for
		_swap_for = -1
		main.act(func(): _e.reward_decline(id))
	else:
		main.act(func(): _e.reward_skip())


func _last_offer() -> Dictionary:
	var evs: Array = _e.state.events
	for i in range(evs.size() - 1, -1, -1):
		if evs[i]["type"] == Ev.REWARD_OFFERED:
			return evs[i]
	return {}


func _joker_desc() -> String:
	for e in _e.state.events:
		if e["type"] == Ev.JOKER_OFFERED:
			return e.get("desc", "")
	return ""


func play_event(ev: Dictionary) -> float:
	match ev["type"]:
		Ev.REWARD_TAKEN, Ev.CARD_REMOVED, Ev.JOKER_ATTACHED:
			main.sfx.play("reward")
			return 0.2
		Ev.LIFE_RESTORED:
			main.toast("+1 LIV", Style.RED, 400)
			return 0.4
	return 0.0
