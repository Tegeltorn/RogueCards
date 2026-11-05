extends Control
## Between floors: reward pick (with swap when the deck is full) and card removal (♣).

const Style := preload("res://ui/style.gd")
const CardView := preload("res://ui/card_view.gd")
const Help := preload("res://ui/screens/help.gd")
const GameState := preload("res://engine/game_state.gd")
const Ev := preload("res://engine/events.gd")
const Phase := GameState.Phase

const RULE_TEXT := {
	"S": "Pick any of the beaten cards",
	"C": "Reveal 2, take 1 and remove 1 card from your deck",
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
var _opt_sels: Array = []  # selected reward options (card ids), up to the number of picks
var _deck_sel := -1  # selected deck card (swap target or card to remove)
var _opt_views: Dictionary = {}
var _deck_views: Dictionary = {}
var _fresh_id := -1  # card that just landed in the deck (gets a pop + glow after refresh)
var _animating := false
var _tip: PanelContainer
var _last_tapped := -1  # card shown in the tooltip
const TIP_H := 196.0  # height of the card info slot
const OPT_GAP := 16
const DECK_CARD := Vector2(100, 140)


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
	_v.add_theme_constant_override("separation", 10)
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
	_opts.add_theme_constant_override("h_separation", OPT_GAP)
	_opts.add_theme_constant_override("v_separation", 16)
	# Room above the options so a selected (lifted) card doesn't cover the prompt.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 30)
	pad.add_child(_opts)
	_v.add_child(pad)
	# The card info sits in a fixed-height slot, so tapping a card never makes the page longer.
	var tip_slot := Control.new()
	tip_slot.custom_minimum_size.y = TIP_H
	tip_slot.clip_contents = true
	_v.add_child(tip_slot)
	_tip = Help.tip_box()
	_tip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	(_tip.get_node("Text") as Label).add_theme_font_size_override("font_size", 20)
	(_tip.get_node("Text") as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_slot.add_child(_tip)
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
	# Room above the deck so a selected (lifted) card doesn't cover the "Your deck" label.
	var deck_pad := MarginContainer.new()
	deck_pad.add_theme_constant_override("margin_top", 30)
	deck_pad.add_child(_deck)
	_v.add_child(deck_pad)
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
			_sub.text = "Finished with %s: %s" % [Style.SUIT_SYM[suit], RULE_TEXT[suit]]
			var healed: int = int(_last_offer().get("healed", 0))
			if healed > 0:
				_sub.text += "\nYou got %d life back!" % healed
			_opt_sels = _opt_sels.filter(func(id): return s.find_in(r["options"], id) != null)
			var picks: int = mini(int(r.get("picks", 0)), r["options"].size())
			if _opt_sels.is_empty() and picks > 1 and picks == r["options"].size():
				# ♦: you take them all, so they start selected (tap one to leave it).
				_opt_sels = r["options"].map(func(c): return c.id)
			for i in r["options"].size():
				var o = r["options"][i]
				var cv := CardView.new()
				cv.setup(o, _opt_size(r["options"].size()))
				cv.tapped.connect(func(_x): _on_option(o.id))
				_opts.add_child(cv)
				_opt_views[o.id] = cv
				cv.land(i * 0.08)
		Phase.REWARD_REMOVE:
			_sub.text = "Clubs reward"
	if s.find_in(s.deck, _deck_sel) == null:
		_deck_sel = -1
	var cap := int(s.balance["deck_cap"])
	_deck_label.text = "Your deck (%d/%d)" % [s.deck.size(), cap] if cap > 0 else "Your deck (%d cards)" % s.deck.size()
	var sorted: Array = s.deck.duplicate()
	sorted.sort_custom(func(a, b): return a.suit < b.suit or (a.suit == b.suit and a.rank < b.rank))
	for c in sorted:
		var cv := CardView.new()
		cv.setup(c, DECK_CARD)
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


## Reward cards shrink so they always fit on one row (4 options with Rich, all beaten cards with ♠).
func _opt_size(n: int) -> Vector2:
	var avail := maxf(300.0, size.x - 48.0 - 40.0)  # margins and room for a scrollbar
	var w := minf(136.0, floorf((avail - OPT_GAP * (n - 1)) / maxf(1.0, n)))
	return Vector2(w, roundf(w * 1.4))


## Deck cards can be picked when swapping (full deck) or removing (♣).
func _deck_pickable() -> bool:
	var s = _e.state
	match s.phase:
		Phase.REWARD:
			return _e.removal_needed(_opt_sels.size()) or (_e.deck_full() and not _opt_sels.is_empty())
		Phase.REWARD_REMOVE:
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
		cv.set_selected(_opt_sels.has(id))
		cv.highlight = Style.GOLD if _opt_sels.has(id) else Color(0, 0, 0, 0)
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
	var dk = s.find_in(s.deck, _deck_sel)
	if not pickable:
		dk = null
	_skip.visible = false
	match s.phase:
		Phase.REWARD:
			_update_reward_buttons(dk)
		Phase.REWARD_REMOVE:
			_prompt.text = "Tap a card in your deck to remove"
			_set_confirm("Remove %s" % dk.label() if dk != null else "Pick a card to remove", dk != null)


## One action for the whole reward: the cards to take, plus the ♣ removal (or the swap when full).
func _update_reward_buttons(dk) -> void:
	var s = _e.state
	var opts: Array = s.reward.get("options", [])
	var picks: int = mini(int(s.reward.get("picks", 0)), opts.size())
	var takes: Array = []
	for id in _opt_sels:
		var c = s.find_in(opts, id)
		if c != null:
			takes.append(c.label())
	var n := takes.size()
	var full: bool = _e.deck_full() and n > 0
	var remove: bool = _e.removal_needed(n)
	var ok: bool = n <= picks and (n == picks or _e.can_decline())
	var parts: Array = []
	if full:
		parts.append("Swap %s for %s" % [dk.label() if dk else "?", takes[0]])
	elif n > 0:
		parts.append("Take " + " + ".join(takes))
	if remove:
		parts.append(("remove %s" if n > 0 else "Remove %s") % (dk.label() if dk else "?"))
	if (full or remove) and dk == null:
		ok = false
	if n == 0 and not remove:
		ok = false
	if picks > 1:
		_prompt.text = "Take up to %d cards" % picks if _e.can_decline() else "Take %d cards" % picks
	else:
		_prompt.text = "Tap a card to take"
	if remove:
		_prompt.text += " and tap a card in your deck to remove"
	elif full:
		_prompt.text = "Your deck is full: tap a card in your deck to swap out"
	_set_confirm(", ".join(parts) if not parts.is_empty() else "Pick a card", ok)
	# Declining everything is a separate button (not offered while ♣ still demands a removal).
	_skip.visible = _e.can_decline() and not _e.removal_needed(0)
	_skip.text = "Decline the reward"


func _set_confirm(text: String, enabled: bool) -> void:
	_confirm.text = text
	_confirm.disabled = not enabled


func _on_option(id: int) -> void:
	if main.is_busy() or _animating:
		return
	var picks: int = mini(int(_e.state.reward.get("picks", 1)), _e.state.reward.get("options", []).size())
	if _opt_sels.has(id):
		_opt_sels.erase(id)
	else:
		if _opt_sels.size() >= picks:
			_opt_sels.pop_front()
		_opt_sels.append(id)
	_last_tapped = id
	main.sfx.play("card")
	_update_sel()


func _on_deck(id: int) -> void:
	if main.is_busy() or _animating or not _deck_pickable():
		return
	_deck_sel = -1 if _deck_sel == id else id
	_last_tapped = _deck_sel if _deck_sel >= 0 else (_opt_sels[-1] if not _opt_sels.is_empty() else -1)
	main.sfx.play("card")
	_update_sel()


func _on_confirm() -> void:
	if main.is_busy() or _animating or _confirm.disabled:
		return
	_animating = true
	var s = _e.state
	var takes := _opt_sels.duplicate()
	var dk := _deck_sel
	_opt_sels.clear()
	_deck_sel = -1
	_confirm.disabled = true
	main.sfx.play("reward")
	match s.phase:
		Phase.REWARD:
			var full: bool = _e.deck_full() and not takes.is_empty()
			var remove: bool = _e.removal_needed(takes.size())
			if dk >= 0 and (full or remove):
				await _animate_out(dk)
			for i in takes.size():
				await _animate_take(takes[i], -1, i)
			_fresh_id = takes[0] if not takes.is_empty() else -1
			main.act(func(): _e.reward_resolve(takes, dk if remove else -1, [dk] if full else []))
		Phase.REWARD_REMOVE:
			await _animate_out(dk)
			main.act(func(): _e.reward_remove(dk))
	_animating = false


## The picked reward card flies down into the deck (and a swapped-out card leaves first).
func _animate_take(opt_id: int, out_id: int, index: int = 0) -> void:
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
		target = last.position + Vector2((DECK_CARD.x + 10) * (index + 1), 0)
		if target.x + DECK_CARD.x > size.x:
			target = Vector2(_deck.get_global_rect().position.x + 20, last.position.y + DECK_CARD.y + 10)
	src.visible = false
	await main.fly_card(card, src.get_global_rect(), target, DECK_CARD, 0.5).finished


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
	_opt_sels.clear()
	_deck_sel = -1
	main.act(func(): _e.reward_resolve([]))


func _last_offer() -> Dictionary:
	var evs: Array = _e.state.events
	for i in range(evs.size() - 1, -1, -1):
		if evs[i]["type"] == Ev.REWARD_OFFERED:
			return evs[i]
	return {}


func play_event(ev: Dictionary) -> float:
	match ev["type"]:
		Ev.REWARD_TAKEN, Ev.CARD_REMOVED:
			main.sfx.play("reward")
			return 0.2
		Ev.LIFE_RESTORED:
			main.toast("+1 LIFE", Style.RED, 400)
			return 0.4
	return 0.0
