extends RefCounted
## Help texts and info overlays: short rules ("?"), card effect tooltip text,
## the aces overlay (lives + sacrifice) and the modifiers overlay (mod ace + theme king).

const Style := preload("res://ui/style.gd")
const CardView := preload("res://ui/card_view.gd")
const Balance := preload("res://engine/balance.gd")

const JOKER_TEXT := {
	"dual": "Joker: counts as both colours.",
	"innate": "Joker: always in your first hand of a floor.",
	"double": "Joker: worth double.",
	"draw2": "Joker: draw 2 cards when played.",
}


## Everything a card does, without fight context (reward and start-pick screens).
static func card_info(b: Dictionary, c) -> String:
	var v: int = c.value()
	var lines: Array = []
	match c.suit:
		"H":
			lines.append("Block %d. Leftover block is stored as shield for the next round; with no attack to block, all %d is stored." % [v, v])
		"D":
			lines.append("Block %d and draw 1 card (also when played against a shield)." % v)
		"S":
			lines.append("Attack %d (%d × %s, rounded down)." % [int(floor(v * float(b["spade_multiplier"]))), v, str(b["spade_multiplier"])])
		"C":
			lines.append("Attack %d. +%d if you play 2 or more clubs in a round." % [v, int(b["club_pair_bonus"])])
	if c.suit == "S" or c.suit == "C":
		lines.append("Against an attack it doesn't block, but counts toward overpower (%d× the attack: discard, draw 1)." % int(b.get("overpower_multiplier", 2)))
	if c.joker != "":
		lines.append(JOKER_TEXT.get(c.joker, ""))
	return "\n".join(lines)


## A tooltip box (panel + label) for screens that list cards.
static func tip_box() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Style.box(Color(0.06, 0.04, 0.1, 0.96), Style.GOLD, 3, 12))
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
			lines.append("Block %d and draw 1 card." % v)
		"S":
			lines.append("Attack %d (%d × %s, rounded down)." % [int(floor(v * float(b["spade_multiplier"]))), v, str(b["spade_multiplier"])])
		"C":
			lines.append("Attack %d. +%d if you play 2 or more clubs this round." % [v, int(b["club_pair_bonus"])])
	if c.joker != "":
		lines.append(JOKER_TEXT.get(c.joker, ""))
	var bneed: int = e.block_need()
	var aneed: int = e.attack_need()
	if not e.is_effective(c):
		if c.suit == "H":
			lines.append("No attack to block: stores %d shield for the next round." % v)
		elif c.suit == "D":
			lines.append("No attack to block: it only draws a card.")
		elif bneed > 0 and aneed == 0:
			lines.append("No shield to break. Black cards worth %d× the attack overpower: discarded, draw 1." % int(b.get("overpower_multiplier", 2)))
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
	var txt := """%s  An enemy card is revealed. [color=%s]Black = attack[/color], [color=%s]red = shield[/color]. Its value is its rank.
• Your hand is filled up to %d cards. Cards you don't play stay in your hand.
• Drag a card onto the enemy to play it. Its effect happens at once (♦ draws a card). Only the right colour counts (green outline): red cards block attacks, black cards break shields. Tap a card to see what it does.
• Press End turn: the enemy acts and the round is resolved.

%s
♥ Block. Leftover block is stored as shield for the next round (with no attack: the full value).
♦ Block and draw 1 card (also against a shield).
♠ Attack × %s (rounded down).
♣ Attack. +%d if you play 2 or more clubs.
Tip: select a single card to see what it does.

%s  If your block is too low you lose a life (a miss of %d or more costs 2). The attack card is beaten either way.
%s  Once per round, black cards played against an attack worth %d× its value: they are discarded and you draw 1 card. The enemy still attacks at End turn.
%s  Break it with enough attack, or it goes to the bottom of the enemy pile and comes back.
%s  Your aces at the bottom. Tap them to see them, or to sacrifice one: you lose that life and it counts as %d this round.

%s  A shield with no black enemy cards left behind it is a last stand: fail to break it and you lose a life.
%s  The suit of the last beaten card decides: ♠ pick any beaten card · ♣ reveal 2, take 1, remove 1 · ♥ heal a life · ♦ reveal 2, take both. %s
%s  Floors go %d to Queen, then the three kings (%d cards in hand). Tap the king at the top to see your mod and the jokers (the red joker arrives after the Jack floor).""" % [
		H % "EACH ROUND", Style.hex(Style.RED), Style.hex(Style.BLUE), int(b["hand_size"]),
		H % "SUITS", str(b["spade_multiplier"]), int(b["club_pair_bonus"]),
		H % "ATTACK", int(b["graded_threshold"]),
		H % "OVERPOWER", int(b.get("overpower_multiplier", 2)),
		H % "SHIELD",
		H % "LIVES", int(b["ace_value"]),
		H % "LAST STAND",
		H % "REWARDS", ("You may decline any card to keep your deck lean." if int(b["deck_cap"]) <= 0 else "Your deck holds up to %d cards; when it is full you swap or decline." % int(b["deck_cap"])),
		H % "THE ROAD", int(b.get("first_floor", 4)), int(b["boss_hand_size"])]
	var v := VBoxContainer.new()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 820)
	var rt := _text(txt, 24)
	scroll.add_child(rt)
	v.add_child(scroll)
	return _panel_with_close(v, "How to play")


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


## Modifiers overlay: the mod ace and the theme king's jokers.
static func mods_overlay(main) -> Control:
	var e = main.engine
	var s = e.state
	var jd: Dictionary = Balance.jokers().get(s.theme_suit, {})
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
	var king_row := HBoxContainer.new()
	var kv := CardView.new()
	kv.set_interactive(false)
	kv.breathing = false
	kv.setup(s.theme_king, Vector2(90, 126))
	king_row.add_child(kv)
	var kt := "[b]Theme king: %s[/b]\n" % Style.SUIT_NAME.get(s.theme_suit, "")
	if s.balance["jokers_enabled"]:
		var red_state := "Comes after the Jack floor."
		for c in s.deck:
			if c.joker != "":
				red_state = "Attached under %s." % c.label()
		kt += "[color=" + Style.hex(Style.RED) + "]Red joker:[/color] %s %s\n" % [jd.get("red", {}).get("desc", ""), red_state]
		kt += "[b]Black joker[/b] (in the boss pile): %s" % jd.get("black", {}).get("desc", "")
	else:
		kt += "Jokers are disabled."
	king_row.add_child(_text(kt, 24))
	v.add_child(king_row)
	return _panel_with_close(v, "Modifiers")
