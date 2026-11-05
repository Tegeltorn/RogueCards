extends RefCounted
## Help texts and info overlays: short rules ("?"), card effect tooltip text,
## the aces overlay (lives + sacrifice) and the modifiers overlay (mod ace).

const Style := preload("res://ui/style.gd")
const CardView := preload("res://ui/card_view.gd")
const Balance := preload("res://engine/balance.gd")


## Everything a card does, without fight context (reward and start-pick screens).
static func card_info(b: Dictionary, c) -> String:
	var v: int = c.value()
	var lines: Array = []
	match c.suit:
		"H":
			lines.append("Block %d. Leftover block is stored as shield for the next round; with no attack to block, all %d is stored." % [v, v])
		"D":
			lines.append("Block %d and draw 1 card from the draw pile, if it has any (also against a shield)%s." % [v, _diamond_note(b)])
		"S":
			lines.append("Attack %d (%d × %s, rounded down)." % [int(floor(v * float(b["spade_multiplier"]))), v, str(b["spade_multiplier"])])
		"C":
			lines.append("Attack %d. +%d if you play 2 or more clubs in a round." % [v, int(b["club_pair_bonus"])])
	if c.suit == "S" or c.suit == "C":
		lines.append("Against an attack it doesn't block, but counts toward overpower (%d× the attack: %s)." % [int(b.get("overpower_multiplier", 2)), _overpower_effect(b)])
	var burn := burn_text(b, c)
	if burn != "":
		lines.append(burn)
	return "\n".join(lines)


static func _diamond_note(b: Dictionary) -> String:
	match str(b.get("diamond_draw", "always")):
		"once": return "; only the first ♦ each round draws"
		"block": return "; only while blocking an attack"
	return ""


static func _no_refill(b: Dictionary) -> String:
	return " (no refill next round)" if bool(b.get("burn_no_refill", false)) else ""


## What overpowering does with the current balance.
static func _overpower_effect(b: Dictionary) -> String:
	var n := int(b.get("overpower_draw", 0))
	return "discard them" + (", draw %d" % n if n > 0 else "")


## What burning this card would do ("" when burning is off).
static func burn_text(b: Dictionary, c) -> String:
	match str(b.get("burn_mode", "off")):
		"double":
			return "Burn: %s %d this round, then it is gone for good%s." % ["blocks" if c.base_red() else "attacks", c.rank * 2, _no_refill(b)]
		"swap":
			return "Burn: %s %d this round, then it is gone for good%s." % ["attacks" if c.base_red() else "blocks", c.rank, _no_refill(b)]
	return ""


## A tooltip box (panel + label) for screens that list cards.
static func tip_box() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.box(Color(Style.PANEL, 0.97), Color(Style.GOLD, 0.7), 2, 12))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Style.label("", 22, Style.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	l.name = "Text"
	p.add_child(l)
	p.visible = false
	return p


static func show_tip(p: PanelContainer, b: Dictionary, c) -> void:
	if c == null:
		p.visible = false
		return
	(p.get_node("Text") as Label).text = c.label() + ":  " + card_info(b, c)
	p.visible = true


## One or two lines describing what a hand card does right now.
static func card_effect(e, c) -> String:
	var b: Dictionary = e.state.balance
	var v: int = c.value()
	var lines: Array = []
	match c.suit:
		"H":
			lines.append("Block %d. Leftover block is stored as shield for the next round." % v)
		"D":
			if e.state.draw_pile.is_empty():
				lines.append("Block %d. The draw pile is empty: no card to draw." % v)
			elif not e._diamond_draws():
				lines.append("Block %d. A ♦ already drew this round: no card to draw." % v)
			else:
				lines.append("Block %d and draw 1 card." % v)
		"S":
			lines.append("Attack %d (%d × %s, rounded down)." % [int(floor(v * float(b["spade_multiplier"]))), v, str(b["spade_multiplier"])])
		"C":
			lines.append("Attack %d. +%d if you play 2 or more clubs this round." % [v, int(b["club_pair_bonus"])])
	var bneed: int = e.block_need()
	var aneed: int = e.attack_need()
	if not e.is_effective(c):
		if c.suit == "H":
			lines.append("No attack to block: stores %d shield for the next round." % v)
		elif c.suit == "D":
			lines.append("No attack to block: it only draws a card." if not e.state.draw_pile.is_empty() else "No attack to block, and the draw pile is empty: it does nothing now.")
		elif bneed > 0 and aneed == 0:
			lines.append("No shield to break. Black cards worth %d× the attack overpower: %s." % [int(b.get("overpower_multiplier", 2)), _overpower_effect(b)])
	var burn := burn_text(b, c)
	if burn != "" and e.can_burn(c):
		lines.append(burn)
	return "\n".join(lines)


static func _panel_with_close(v: VBoxContainer, title: String) -> PanelContainer:
	var p := Style.panel(v)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var t := Style.label(title, 38, Style.GOLD)
	v.add_child(t)
	v.move_child(t, 0)
	var orn := Style.ornament()
	v.add_child(orn)
	v.move_child(orn, 1)
	var close := Style.button("Close", Style.BLACK, 26)
	close.pressed.connect(p.queue_free)
	v.add_child(close)
	return p


static func _text(bb: String, size: int = 24) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.text = bb
	rt.add_theme_font_size_override("normal_font_size", size)
	rt.add_theme_font_size_override("bold_font_size", size)
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return rt


## The "?" overlay: short rules with the current balance values.
static func rules_overlay(main) -> Control:
	var b: Dictionary = main.engine.state.balance if main.engine != null else main.balance()
	var H := "[color=" + Style.hex(Style.GOLD) + "]%s[/color]"
	var lines: Array = []
	lines.append("%s  An enemy card is revealed. [color=%s]Black = attack[/color], [color=%s]red = shield[/color]. Its value is its rank." % [H % "EACH ROUND", Style.hex(Style.RED), Style.hex(Style.BLUE)])
	lines.append("• Your hand is filled up to %d cards. Cards you don't play stay in your hand." % int(b["hand_size"]))
	lines.append("• Drag a card onto the enemy to play it. Its effect happens at once (♦ draws a card). Only the right colour counts (green outline): red cards block attacks, black cards break shields. Tap a card to see what it does.")
	lines.append("• Press End turn: the enemy acts and the round is resolved.")
	lines.append("")
	lines.append(H % "SUITS")
	lines.append("♥ Block. Leftover block is stored as shield for the next round (with no attack: the full value).")
	lines.append("♦ Block and draw 1 card (also against a shield), if the draw pile has cards%s. The discard pile is only shuffled back when your hand is refilled." % _diamond_note(b))
	lines.append("♠ Attack × %s (rounded down)." % str(b["spade_multiplier"]))
	lines.append("♣ Attack. +%d if you play 2 or more clubs." % int(b["club_pair_bonus"]))
	lines.append("")
	lines.append("%s  If your block is too low you lose a life (a miss of %d or more costs 2). %s" % [H % "ATTACK", int(b["graded_threshold"]),
		("An attack you don't block goes to the bottom of the enemy pile and comes back: sacrificing an ace to block it can be worth it." if bool(b.get("failed_attack_returns", false)) else "The attack card is beaten either way.")])
	lines.append("%s  Break it with enough attack, or it goes to the bottom of the enemy pile and comes back. Cards that can't break it still cycle your hand: play them to draw fresh ones next round." % (H % "SHIELD"))
	match str(b.get("burn_mode", "off")):
		"double":
			lines.append("%s  Drag a card onto the fire: it burns up and leaves your deck for good. This round it counts double its rank in its own colour (no suit effect). %s" % [H % "BURN", _burn_limits(b)])
		"swap":
			lines.append("%s  Drag a card onto the fire: it burns up and leaves your deck for good. This round it counts its rank in the other colour (no suit effect). %s" % [H % "BURN", _burn_limits(b)])
	if int(b.get("perfect_draw", 0)) > 0:
		lines.append("%s  Block exactly the attack, or break a shield with exactly its value: draw %d extra card in your next hand." % [H % "PERFECT", int(b["perfect_draw"])])
	if int(b.get("overpower_multiplier", 0)) > 0:
		lines.append("%s  Once per round, black cards played against an attack worth %d× its value: %s. The enemy still attacks at End turn." % [H % "OVERPOWER", int(b["overpower_multiplier"]), _overpower_effect(b)])
	lines.append("%s  Your aces at the bottom. Tap them to see them, or to sacrifice one: you lose that life and it counts as %d this round." % [H % "LIVES", int(b["ace_value"])])
	lines.append("")
	lines.append("%s  The suit of your last card that counted against the floor's final enemy card decides: ♠ pick any beaten card · ♣ reveal 2, take 1, remove 1 · ♥ heal a life · ♦ reveal 2, take both. %s" % [H % "REWARDS",
		("You may decline any card to keep your deck lean." if int(b["deck_cap"]) <= 0 else "Your deck holds up to %d cards; when it is full you swap or decline." % int(b["deck_cap"]))])
	lines.append("%s  Every floor has 4 enemy cards: %d up to Queen, then the four kings. The face cards (Jack, Queen, King) demand tribute: only %d cards in hand. Tap the ace at the top to see your mod." % [H % "THE ROAD", int(b.get("first_floor", 4)), int(b["face_hand_size"])])
	var txt := "\n".join(lines)
	var v := VBoxContainer.new()
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER  # scrolls by dragging, no bar
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 820)
	var rt := _text(txt, 24)
	scroll.add_child(rt)
	v.add_child(scroll)
	return _panel_with_close(v, "How to play")


static func _burn_limits(b: Dictionary) -> String:
	var lim := int(b.get("burn_limit", 0))
	var t := ("Once per round. " if lim == 1 else ("Up to %d per round. " % lim if lim > 1 else "As many as you like. "))
	t += "Only while your deck has %d or more cards." % int(b.get("burn_min_deck", 0))
	if bool(b.get("burn_no_refill", false)):
		t += " The price: after a round you burned in, your hand is not refilled."
	return t


## Lives overlay: remaining and lost aces, and the sacrifice buttons.
static func aces_overlay(main) -> Control:
	var e = main.engine
	var s = e.state
	var v := VBoxContainer.new()
	var why := "Each ace is one life. Lose them all and the run ends.\n"
	why += "Sacrifice: lose that life, and the ace counts as a %d this round (red blocks, black attacks)." % int(s.balance["ace_value"])
	if not s.balance["ace_sac_enabled"] or not e.mod.can_ace_sac():
		why += "\n[color=" + Style.hex(Style.RED) + "]Sacrifice is disabled this run.[/color]"
	elif s.lives.size() < 2:
		why += "\n[color=" + Style.hex(Style.RED) + "]You need at least 2 lives to sacrifice.[/color]"
	v.add_child(_text(why, 22))
	var usable: Array = e.sacrificable_aces()
	var holder: Array = [null]  # lambdas capture by value; the array lets them reach the panel
	for a in s.lives + s.lost_lives:
		var lost: bool = s.lost_lives.has(a)
		var row := HBoxContainer.new()
		var cv := CardView.new()
		cv.set_interactive(false)
		cv.breathing = false
		cv.setup(a, Vector2(70, 98))
		if lost:
			cv.face_up = false
			cv.modulate.a = 0.4
		row.add_child(cv)
		var desc := "Lost" if lost else ("Blocks %d" % int(s.balance["ace_value"]) if a.base_red() else "Attacks %d" % int(s.balance["ace_value"]))
		var l := Style.label(desc, 26, Style.MUTED if lost else Style.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if not lost:
			var btn := Style.button("Sacrifice", Style.PLUM, 24)
			btn.custom_minimum_size = Vector2(190, 70)
			btn.disabled = not usable.has(a)
			var ace = a
			btn.pressed.connect(func():
				if holder[0]:
					holder[0].queue_free()
				main.confirm("Sacrifice %s?\nYou lose this life. It counts as %d this round." % [ace.label(), int(s.balance["ace_value"])],
					[["Sacrifice", func(): main.act(func(): e.sacrifice_ace(ace.id)), Style.PLUM],
					["Cancel", Callable(), Style.BLACK]]))
			row.add_child(btn)
		v.add_child(row)
	holder[0] = _panel_with_close(v, "Your aces (%d lives)" % s.lives.size())
	return holder[0]


## Modifiers overlay: the mod ace.
static func mods_overlay(main) -> Control:
	var e = main.engine
	var s = e.state
	var v := VBoxContainer.new()
	var mod_row := HBoxContainer.new()
	var mv := CardView.new()
	mv.set_interactive(false)
	mv.breathing = false
	mv.setup(s.mod_ace, Vector2(90, 126))
	mod_row.add_child(mv)
	var mt := "[b]Mod ace: %s[/b]\n%s" % [e.mod.name, e.mod.desc] if s.balance["mods_enabled"] else "[b]Mod ace[/b]\nMods are disabled."
	mod_row.add_child(_text(mt, 24))
	v.add_child(mod_row)
	return _panel_with_close(v, "Modifier")
