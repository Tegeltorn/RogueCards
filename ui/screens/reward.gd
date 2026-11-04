extends Control
## Between floors: reward pick (with swap when the deck is full), card removal (♣) and red joker attach.

const Style := preload("res://ui/style.gd")
const CardView := preload("res://ui/card_view.gd")
const Help := preload("res://ui/screens/help.gd")
const GameState := preload("res://engine/game_state.gd")
const Ev := preload("res://engine/events.gd")
const Phase := GameState.Phase

const RULE_TEXT := {
	"S": "Pick any of the beaten cards",
	"C": "Reveal 2, take 1 – then remove 1 card from your deck",
	"H": "Get a life back (all lives: reveal 2, take 1)",
	"D": "Reveal 2 and take both",
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
var _confirm: Button
var _opt_sel := -1   # selected reward option (card id)
var _deck_sel := -1  # selected deck card (swap target, card to remove, or joker target)
var _opt_views: Dictionary = {}
var _deck_views: Dictionary = {}
var _fresh_id := -1  # card that just landed in the deck (gets a pop + glow after refresh)
var _animating := false
var _tip: PanelContainer
var _last_tapped := -1  # card shown in the tooltip


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
	_title.add_theme_constant_override("outline_size", 10)
	_v.add_child(_title)
	_sub = Style.label("", 26, Style.WHITE)
	_v.add_child(_sub)
	_prompt = Style.label("", 28, Style.GOLD)
	_v.add_child(_prompt)
	_opts = HFlowContainer.new()
	_opts.alignment = FlowContainer.ALIGNMENT_CENTER
	_opts.add_theme_constant_override("h_separation", 16)
	_opts.add_theme_constant_override("v_separation", 16)
	# Room above the options so a selected (lifted) card doesn't cover the prompt.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 40)
	pad.add_child(_opts)
	_v.add_child(pad)
	_tip = Help.tip_box()
	_v.add_child(_tip)
	_confirm = Style.button("", Style.RED, 32)
	_confirm.custom_minimum_size.y = 90
	_confirm.pressed.connect(_on_confirm)
	_v.add_child(_confirm)
	_skip = Style.button("Decline", Style.BLACK, 26)
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


## Rebuilds the cards for the current phase (selection changes only call _update_sel).
func refresh() -> void:
	if _e == null:
		return
	var s = _e.state
	for c in _opts.get_children():
		c.queue_free()
	for c in _deck.get_children():
		c.queue_free()
	_opt_views.clear()
	_deck_views.clear()
	_title.text = "FLOOR %s CLEARED" % Style.floor_text(s.floor_num)
	match s.phase:
		Phase.REWARD:
			var r: Dictionary = s.reward
			var suit: String = r.get("suit", "S")
			_sub.text = "Last card %s: %s" % [Style.SUIT_SYM[suit], RULE_TEXT[suit]]
			var healed: int = int(_last_offer().get("healed", 0))
			if healed > 0:
				_sub.text += "\nYou got %d life back!" % healed
			if s.find_in(r["options"], _opt_sel) == null:
				_opt_sel = -1
				_deck_sel = -1
			for i in r["options"].size():
				var o = r["options"][i]
				var cv := CardView.new()
				cv.setup(o, Vector2(150, 210))
				cv.tapped.connect(func(_x): _on_option(o.id))
				_opts.add_child(cv)
				_opt_views[o.id] = cv
				cv.land(i * 0.08)
		Phase.REWARD_REMOVE:
			_sub.text = "Clubs reward"
		Phase.JOKER_ATTACH:
			_title.text = "RED JOKER"
			_sub.text = _joker_desc()
			var jv := CardView.new()
			jv.set_interactive(false)
			jv.rank = 0
			jv.suit = "J"
			jv.setup(null, Vector2(150, 210))
			_opts.add_child(jv)
			jv.land()
	if s.find_in(s.deck, _deck_sel) == null:
		_deck_sel = -1
	var cap := int(s.balance["deck_cap"])
	_deck_label.text = "Your deck (%d/%d)" % [s.deck.size(), cap] if cap > 0 else "Your deck (%d cards)" % s.deck.size()
	var sorted: Array = s.deck.duplicate()
	sorted.sort_custom(func(a, b): return a.suit < b.suit or (a.suit == b.suit and a.rank < b.rank))
	for c in sorted:
		var cv := CardView.new()
		cv.setup(c, Vector2(110, 154))
		cv.breathing = false
		cv.tapped.connect(func(_x): _on_deck(c.id))
		_deck.add_child(cv)
		_deck_views[c.id] = cv
		if c.id == _fresh_id:
			cv.pop(0.2)
			cv.highlight = Style.COUNT
			var tw := cv.create_tween()
			tw.tween_interval(0.8)
			tw.tween_callback(func():
				if is_instance_valid(cv):
					cv.highlight = Color(0, 0, 0, 0))
			_fresh_id = -1
	_update_sel()


## Deck cards can be picked when swapping (full deck), removing (♣) or attaching the red joker.
func _deck_pickable() -> bool:
	var s = _e.state
	match s.phase:
		Phase.REWARD:
			return _opt_sel >= 0 and _e.deck_full()
		Phase.REWARD_REMOVE, Phase.JOKER_ATTACH:
			return true
	return false


## Highlights the selection (lifted + gold, like in a fight) and sets the confirm button.
func _update_sel() -> void:
	var s = _e.state
	var tip_card = s.find_in(s.reward.get("options", []), _last_tapped)
	if tip_card == null:
		tip_card = s.find_in(s.deck, _last_tapped)
	Help.show_tip(_tip, s.balance, tip_card)
	for id in _opt_views:
		var cv: CardView = _opt_views[id]
		cv.set_selected(id == _opt_sel)
		cv.highlight = Style.GOLD if id == _opt_sel else Color(0, 0, 0, 0)
	var pickable := _deck_pickable()
	for id in _deck_views:
		var cv: CardView = _deck_views[id]
		cv.set_interactive(pickable)
		cv.set_selected(pickable and id == _deck_sel)
		if pickable and id == _deck_sel:
			cv.highlight = Style.GOLD
		elif pickable:
			cv.highlight = Color(Style.GOLD, 0.3)
		else:
			cv.highlight = Color(0, 0, 0, 0)
	var opt = s.find_in(s.reward.get("options", []), _opt_sel) if s.phase == Phase.REWARD else null
	var dk = s.find_in(s.deck, _deck_sel)
	_skip.visible = false
	match s.phase:
		Phase.REWARD:
			var picks := int(s.reward.get("picks", 0))
			if opt == null:
				_prompt.text = "Tap a card to take (%d left)" % picks if picks > 1 else "Tap a card to take"
				_set_confirm("Pick a card", false)
			elif not _e.deck_full():
				_prompt.text = "Take %s?" % opt.label()
				_set_confirm("Take %s" % opt.label(), true)
			elif dk == null:
				_prompt.text = "Your deck is full: tap a card in your deck to swap out"
				_set_confirm("Pick a card to swap out", false)
			else:
				_prompt.text = "Swap %s for %s?" % [dk.label(), opt.label()]
				_set_confirm("Swap %s for %s" % [dk.label(), opt.label()], true)
			_skip.visible = _e.can_decline()
			_skip.text = "Decline %s" % opt.label() if opt != null else "Decline the reward"
		Phase.REWARD_REMOVE:
			_prompt.text = "Tap a card in your deck to remove"
			_set_confirm("Remove %s" % dk.label() if dk != null else "Pick a card to remove", dk != null)
		Phase.JOKER_ATTACH:
			_prompt.text = "Tap a card in your deck to attach the joker to"
			_set_confirm("Attach to %s" % dk.label() if dk != null else "Pick a card", dk != null)


func _set_confirm(text: String, enabled: bool) -> void:
	_confirm.text = text
	_confirm.disabled = not enabled


func _on_option(id: int) -> void:
	if main.is_busy() or _animating:
		return
	_opt_sel = -1 if _opt_sel == id else id
	_last_tapped = _opt_sel
	main.sfx.play("card")
	_update_sel()


func _on_deck(id: int) -> void:
	if main.is_busy() or _animating or not _deck_pickable():
		return
	_deck_sel = -1 if _deck_sel == id else id
	_last_tapped = _deck_sel if _deck_sel >= 0 else _opt_sel
	main.sfx.play("card")
	_update_sel()


func _on_confirm() -> void:
	if main.is_busy() or _animating or _confirm.disabled:
		return
	_animating = true
	var s = _e.state
	var opt := _opt_sel
	var dk := _deck_sel
	_opt_sel = -1
	_deck_sel = -1
	_confirm.disabled = true
	main.sfx.play("reward")
	match s.phase:
		Phase.REWARD:
			var full: bool = _e.deck_full()
			await _animate_take(opt, dk if full else -1)
			_fresh_id = opt
			main.act(func(): _e.reward_take(opt, dk if full else -1))
		Phase.REWARD_REMOVE:
			await _animate_out(dk)
			main.act(func(): _e.reward_remove(dk))
		Phase.JOKER_ATTACH:
			_fresh_id = dk
			if _deck_views.has(dk) and _opts.get_child_count() > 0:
				var jv: Control = _opts.get_child(0)
				jv.visible = false
				await main.fly_card(null, jv.get_global_rect(), _deck_views[dk].get_global_rect().position, Vector2(110, 154)).finished
			main.act(func(): _e.attach_joker(dk))
	_animating = false


## The picked reward card flies down into the deck (and a swapped-out card leaves first).
func _animate_take(opt_id: int, out_id: int) -> void:
	if out_id >= 0:
		await _animate_out(out_id)
	if not _opt_views.has(opt_id):
		return
	var src: CardView = _opt_views[opt_id]
	var card = _e.state.find_in(_e.state.reward["options"], opt_id)
	var target := _deck.get_global_rect().position
	var kids := _deck.get_children().filter(func(k): return k.visible)
	if not kids.is_empty():
		var last: Rect2 = kids[-1].get_global_rect()
		target = last.position + Vector2(120, 0)
		if target.x + 110 > size.x:
			target = Vector2(_deck.get_global_rect().position.x + 20, last.position.y + 164)
	src.visible = false
	await main.fly_card(card, src.get_global_rect(), target, Vector2(110, 154), 0.5).finished


## A deck card leaves (swap or ♣ removal): pops, rises and fades.
func _animate_out(id: int) -> void:
	if not _deck_views.has(id):
		return
	var cv: CardView = _deck_views[id]
	main.burst(cv.get_global_rect().get_center(), Style.MUTED, 18)
	var tw := cv.create_tween()
	tw.tween_property(cv, "scale", Vector2(1.15, 1.15), 0.08)
	tw.tween_property(cv, "position:y", cv.position.y - 80, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(cv, "modulate:a", 0.0, 0.3)
	await tw.finished


func _on_skip() -> void:
	if main.is_busy() or _animating:
		return
	var opt := _opt_sel
	_opt_sel = -1
	_deck_sel = -1
	if opt >= 0:
		main.act(func(): _e.reward_decline(opt))
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
			main.toast("+1 LIFE", Style.RED, 400)
			return 0.4
	return 0.0
