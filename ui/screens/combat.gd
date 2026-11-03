extends Control
## The fight screen (portrait, top to bottom): floor strip + lives, enemy card with intent,
## live total vs enemy value, played cards, fanned hand, piles and action buttons.

const Style := preload("res://ui/style.gd")
const CardView := preload("res://ui/card_view.gd")
const GameState := preload("res://engine/game_state.gd")
const Ev := preload("res://engine/events.gd")
const Phase := GameState.Phase

const HAND_CARD := Vector2(132, 185)
const ENEMY_CARD := Vector2(220, 308)
const MINI := Vector2(56, 78)


class Icon:
	extends Control
	## Sword (attack) or shield intent icon.
	var kind := "attack"
	var col := Color.WHITE

	func _draw() -> void:
		var c := size / 2
		var s := minf(size.x, size.y)
		if kind == "attack":
			var blade := PackedVector2Array([c + Vector2(-0.07, 0.15) * s, c + Vector2(-0.07, -0.38) * s,
				c + Vector2(0, -0.48) * s, c + Vector2(0.07, -0.38) * s, c + Vector2(0.07, 0.15) * s])
			draw_colored_polygon(blade, col)
			draw_polyline(blade + PackedVector2Array([blade[0]]), Style.INK, 3)
			draw_rect(Rect2(c + Vector2(-0.24, 0.15) * s, Vector2(0.48, 0.08) * s), Style.GOLD)
			draw_rect(Rect2(c + Vector2(-0.05, 0.23) * s, Vector2(0.1, 0.2) * s), Color("8b5a2b"))
		else:
			var sh := PackedVector2Array([c + Vector2(-0.36, -0.4) * s, c + Vector2(0.36, -0.4) * s,
				c + Vector2(0.34, 0.05) * s, c + Vector2(0, 0.45) * s, c + Vector2(-0.34, 0.05) * s])
			draw_colored_polygon(sh, col)
			draw_polyline(sh + PackedVector2Array([sh[0]]), Style.INK, 4)
			draw_line(c + Vector2(0, -0.35) * s, c + Vector2(0, 0.38) * s, Color(1, 1, 1, 0.5), 3)


class FloorStrip:
	extends Control
	var current := 3
	var font: Font

	func _draw() -> void:
		var n := 11
		var w := (size.x - (n - 1) * 6) / n
		for i in n:
			var f := 3 + i
			var r := Rect2(i * (w + 6), 0, w, size.y)
			var bg := Style.PAPER if f == current else (Color(1, 1, 1, 0.12) if f < current else Color(0, 0, 0, 0.35))
			draw_style_box(Style.box(bg, Style.INK if f == current else Color(1, 1, 1, 0.2), 3, 6), r)
			var txt := Style.floor_text(f)
			var tc := Style.INK if f == current else (Color(1, 1, 1, 0.35) if f < current else Style.WHITE)
			draw_string(font, r.position + Vector2(0, size.y * 0.72), txt, HORIZONTAL_ALIGNMENT_CENTER, w, 24, tc)


var main
var _e  # engine
var _floor_strip: FloorStrip
var _lives_box: HBoxContainer
var _info_box: HBoxContainer
var _seed_label: Label
var _enemy_layer: Control
var _enemy_views: Dictionary = {}  # id -> CardView
var _intent_layer: Control
var _left_label: Label
var _preview_box: HBoxContainer
var _total_label: Label
var _need_label: Label
var _carry_label: Label
var _hint_label: Label
var _table: Control
var _hand_layer: Control
var _hand_views: Dictionary = {}  # id -> CardView
var _table_views: Dictionary = {}
var _selected: Array = []
var _retain_sel: Array = []
var _main_btn: Button
var _ace_btn: Button
var _draw_btn: Button
var _disc_btn: Button
var _menu_btn: Button
var _last_total := -1
var _reveal_fresh := true


func enter() -> void:
	_e = main.engine
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	resized.connect(_layout)
	_layout()
	if main.has_pending_events():
		# Events (floor start, reveal, deal) are about to be animated; show only the static parts now.
		var st = _e.state
		_floor_strip.current = st.floor_num
		_seed_label.text = "Seed %d" % st.seed_value
		_sync_lives()
		_sync_info()
		_update_controls()
	else:
		refresh()


# ---------------------------------------------------------------- build

func _build() -> void:
	_floor_strip = FloorStrip.new()
	_floor_strip.font = Style.font()
	_floor_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_floor_strip)

	_lives_box = HBoxContainer.new()
	_lives_box.add_theme_constant_override("separation", 6)
	add_child(_lives_box)
	_info_box = HBoxContainer.new()
	_info_box.add_theme_constant_override("separation", 6)
	add_child(_info_box)
	_seed_label = Style.label("", 18, Style.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	add_child(_seed_label)
	_menu_btn = Style.button("≡", Style.BLACK, 34)
	_menu_btn.custom_minimum_size = Vector2(76, 64)
	_menu_btn.pressed.connect(_open_menu)
	add_child(_menu_btn)

	_enemy_layer = Control.new()
	_enemy_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_enemy_layer)
	_intent_layer = Control.new()
	_intent_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_intent_layer)
	_left_label = Style.label("", 22, Style.MUTED)
	add_child(_left_label)
	_preview_box = HBoxContainer.new()
	_preview_box.add_theme_constant_override("separation", 6)
	add_child(_preview_box)

	_total_label = Style.label("", 64, Style.WHITE)
	_total_label.add_theme_constant_override("outline_size", 12)
	add_child(_total_label)
	_need_label = Style.label("", 24, Style.MUTED)
	add_child(_need_label)
	_carry_label = Style.label("", 22, Style.BLUE)
	add_child(_carry_label)
	_hint_label = Style.label("", 24, Style.GOLD)
	add_child(_hint_label)

	_table = Control.new()
	_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_table)
	_hand_layer = Control.new()
	_hand_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hand_layer)

	_draw_btn = Style.button("", Style.BLACK, 22)
	_draw_btn.custom_minimum_size = Vector2(110, 80)
	_draw_btn.pressed.connect(func(): _show_pile("Dragbunt", _e.state.draw_pile))
	add_child(_draw_btn)
	_disc_btn = Style.button("", Style.BLACK, 22)
	_disc_btn.custom_minimum_size = Vector2(110, 80)
	_disc_btn.pressed.connect(func(): _show_pile("Slänghög", _e.state.discard))
	add_child(_disc_btn)
	_ace_btn = Style.button("Offra ess", Color("7a2a8c"), 22)
	_ace_btn.custom_minimum_size = Vector2(130, 80)
	_ace_btn.pressed.connect(_ace_dialog)
	add_child(_ace_btn)
	_main_btn = Style.button("Klar", Style.RED, 34)
	_main_btn.custom_minimum_size = Vector2(220, 92)
	_main_btn.pressed.connect(_on_main)
	add_child(_main_btn)


func _layout() -> void:
	var W := size.x
	var H := size.y
	_floor_strip.position = Vector2(16, 16)
	_floor_strip.size = Vector2(W - 112, 44)
	_menu_btn.position = Vector2(W - 88, 10)
	_menu_btn.size = Vector2(76, 56)
	_lives_box.position = Vector2(16, 74)
	_info_box.position = Vector2(W - 16 - 2 * MINI.x - 6, 74)
	_seed_label.position = Vector2(16, 74 + MINI.y + 2)
	_seed_label.size = Vector2(300, 24)
	var ey := 190.0 + maxf(0.0, (H - 1280.0) * 0.25)
	_enemy_layer.position = Vector2(0, ey)
	_enemy_layer.size = Vector2(W, ENEMY_CARD.y)
	_intent_layer.position = Vector2(0, ey)
	_intent_layer.size = Vector2(W, ENEMY_CARD.y)
	_left_label.position = Vector2(0, ey + ENEMY_CARD.y + 8)
	_left_label.size = Vector2(W, 30)
	_preview_box.position = Vector2(W - 16 - 2 * MINI.x - 6, ey + ENEMY_CARD.y - MINI.y - 30)
	var ty := ey + ENEMY_CARD.y + 40
	_total_label.position = Vector2(0, ty)
	_total_label.size = Vector2(W, 80)
	_total_label.pivot_offset = Vector2(W / 2, 40)
	_need_label.position = Vector2(0, ty + 72)
	_need_label.size = Vector2(W, 30)
	_carry_label.position = Vector2(0, ty + 100)
	_carry_label.size = Vector2(W, 28)
	var by := H - 106
	_draw_btn.position = Vector2(14, by)
	_disc_btn.position = Vector2(W - 124, by)
	_main_btn.position = Vector2(W / 2 - 40, by - 6)
	_main_btn.size = Vector2(220, 92)
	_ace_btn.position = Vector2(136, by)
	var hy := by - HAND_CARD.y - 40
	_hand_layer.position = Vector2(0, hy)
	_hand_layer.size = Vector2(W, HAND_CARD.y)
	_hint_label.position = Vector2(0, hy - 46)
	_hint_label.size = Vector2(W, 34)
	_table.position = Vector2(0, ty + 134)
	_table.size = Vector2(W, 110)
	_layout_hand()
	_layout_table()
	_layout_enemies()


# ---------------------------------------------------------------- sync with state

func refresh() -> void:
	if _e == null:
		return
	var s = _e.state
	_floor_strip.current = s.floor_num
	_floor_strip.queue_redraw()
	_seed_label.text = "Seed %d" % s.seed_value
	_sync_lives()
	_sync_info()
	_sync_enemies(s.current)
	_sync_hand()
	_sync_table()
	_sync_preview()
	_update_controls()


func _sync_lives() -> void:
	var s = _e.state
	for c in _lives_box.get_children():
		c.queue_free()
	for a in s.lives:
		var cv := _mini(a)
		_lives_box.add_child(cv)
	for a in s.lost_lives:
		var cv := _mini(a)
		cv.face_up = false
		cv.modulate.a = 0.25
		_lives_box.add_child(cv)


func _sync_info() -> void:
	var s = _e.state
	for c in _info_box.get_children():
		c.queue_free()
	_info_box.add_child(_mini(s.mod_ace))
	_info_box.add_child(_mini(s.theme_king))


func _mini(card) -> CardView:
	var cv := CardView.new()
	cv.set_interactive(false)
	cv.breathing = false
	cv.setup(card, MINI)
	return cv


func _sync_enemies(cards: Array) -> void:
	var ids: Array = cards.map(func(c): return c.id)
	for id in _enemy_views.keys():
		if not ids.has(id):
			_enemy_views[id].queue_free()
			_enemy_views.erase(id)
	for c in cards:
		if not _enemy_views.has(c.id):
			var cv := CardView.new()
			cv.set_interactive(false)
			cv.setup(c, ENEMY_CARD)
			_enemy_layer.add_child(cv)
			_enemy_views[c.id] = cv
	_layout_enemies()
	_sync_intents(cards)


func _layout_enemies() -> void:
	var n := _enemy_views.size()
	var i := 0
	var W := size.x
	var gap := 30.0
	var total := n * ENEMY_CARD.x + (n - 1) * gap
	for id in _enemy_views:
		var cv: CardView = _enemy_views[id]
		var sc := 1.0 if n == 1 else 0.8
		cv.scale = Vector2(sc, sc)
		cv.position = Vector2(W / 2 - total * sc / 2 + i * (ENEMY_CARD.x + gap) * sc - (ENEMY_CARD.x * (1 - sc) / 2) , 0)
		i += 1


func _sync_intents(cards: Array) -> void:
	for c in _intent_layer.get_children():
		c.queue_free()
	var W := size.x
	var n := cards.size()
	for i in n:
		var card = cards[i]
		var attack: bool = card.base_black()
		var ic := Icon.new()
		ic.kind = "attack" if attack else "shield"
		ic.col = Color("d9dde8") if attack else Style.BLUE
		ic.size = Vector2(70, 70)
		var val: int = _e.enemy_value(card)
		var lab := Style.label(str(val), 48, Style.RED if attack else Style.BLUE)
		lab.add_theme_constant_override("outline_size", 10)
		lab.size = Vector2(90, 60)
		if n == 1:
			ic.position = Vector2(W / 2 + ENEMY_CARD.x / 2 + 18, 60)
			lab.position = Vector2(W / 2 + ENEMY_CARD.x / 2 + 8, 130)
		else:
			var cx := W / 2 + (i - 0.5) * (ENEMY_CARD.x + 30) * 0.8
			ic.position = Vector2(cx - 80, ENEMY_CARD.y * 0.8 + 4)
			lab.position = Vector2(cx - 10, ENEMY_CARD.y * 0.8 + 8)
		_intent_layer.add_child(ic)
		_intent_layer.add_child(lab)
	var s = _e.state
	_left_label.text = ("Boss: %d kvar" if s.is_boss() else "%d kvar i fiendens hög") % s.enemy_pile.size()


func _sync_preview() -> void:
	for c in _preview_box.get_children():
		c.queue_free()
	for c in _e.preview_enemies():
		_preview_box.add_child(_mini(c))


func _sync_hand() -> void:
	var s = _e.state
	var ids: Array = s.hand.map(func(c): return c.id)
	for id in _hand_views.keys():
		if not ids.has(id):
			_hand_views[id].queue_free()
			_hand_views.erase(id)
	for c in s.hand:
		if not _hand_views.has(c.id):
			_add_hand_card(c, 0.0)
	_selected = _selected.filter(func(id): return ids.has(id))
	_retain_sel = _retain_sel.filter(func(id): return ids.has(id))
	_layout_hand()


func _add_hand_card(c, delay: float) -> CardView:
	var cv := CardView.new()
	cv.setup(c, HAND_CARD)
	cv.tapped.connect(_on_card_tapped)
	_hand_layer.add_child(cv)
	_hand_views[c.id] = cv
	_layout_hand()
	cv.land(delay, Vector2(0, 260))
	return cv


func _layout_hand() -> void:
	var s = _e.state if _e else null
	if s == null:
		return
	var cards: Array = []
	for c in s.hand:
		if _hand_views.has(c.id):
			cards.append(_hand_views[c.id])
	var n := cards.size()
	if n == 0:
		return
	var W := size.x
	var spacing := minf(150.0, (W - 40 - HAND_CARD.x) / maxf(1.0, n - 1))
	var total := spacing * (n - 1)
	for i in n:
		var cv: CardView = cards[i]
		var t := i - (n - 1) / 2.0
		cv.rotation = t * 0.07
		cv.position = Vector2(W / 2 - total / 2 + i * spacing - HAND_CARD.x / 2, absf(t) * absf(t) * 6)
		cv.z_index = i


func _sync_table() -> void:
	var s = _e.state
	var ids: Array = s.played.map(func(c): return c.id)
	for id in _table_views.keys():
		if not ids.has(id):
			_table_views[id].queue_free()
			_table_views.erase(id)
	for c in s.played:
		if not _table_views.has(c.id):
			var cv := CardView.new()
			cv.set_interactive(false)
			cv.setup(c, Vector2(76, 106))
			_table.add_child(cv)
			_table_views[c.id] = cv
			cv.pop(0.2)
	_layout_table()


func _layout_table() -> void:
	var n := _table_views.size()
	var W := size.x
	var i := 0
	var sp := minf(84.0, (W - 100) / maxf(1.0, n))
	for id in _table_views:
		_table_views[id].position = Vector2(W / 2 - n * sp / 2 + i * sp, 0)
		i += 1


func _update_controls() -> void:
	var s = _e.state
	var playing: bool = s.phase == Phase.PLAY
	var retaining: bool = s.phase == Phase.RETAIN
	for id in _hand_views:
		var cv: CardView = _hand_views[id]
		var c = s.find_in(s.hand, id)
		if c == null:
			continue
		cv.dimmed = playing and not _e.can_play_card(c)
		cv.set_selected((playing and _selected.has(id)) or (retaining and _retain_sel.has(id)))
		cv.highlight = Style.GOLD if retaining and _retain_sel.has(id) else Color(0, 0, 0, 0)
	_ace_btn.visible = playing and not _e.sacrificable_aces().is_empty()
	_main_btn.disabled = main.is_busy()
	if playing:
		_main_btn.text = "Spela" if not _selected.is_empty() else "Klar"
		var none_playable: bool = _e.playable_cards().is_empty()
		_hint_label.text = "Tryck på kort av rätt färg" if _selected.is_empty() and not none_playable else ""
		if none_playable and s.played.is_empty():
			_hint_label.text = "Inga kort av rätt färg"
	elif retaining:
		_main_btn.text = "Fortsätt"
		_hint_label.text = "Spara %d kort (tryck)" % _e.retain_limit()
	else:
		_hint_label.text = ""
	_draw_btn.text = "Drag\n%d" % s.draw_pile.size()
	_disc_btn.text = "Släng\n%d" % s.discard.size()
	_update_total()


func _update_total() -> void:
	var s = _e.state
	if s.phase != Phase.PLAY or s.current.is_empty():
		_total_label.text = ""
		_need_label.text = ""
		_carry_label.text = ("Sparad sköld: %d" % s.carry_shield) if s.carry_shield > 0 else ""
		return
	var t: Dictionary = _e.preview(_selected)
	var parts: Array = []
	var ok := true
	var exact := false
	var total := 0
	if int(t["block_need"]) > 0:
		parts.append("BLOCK %d / %d" % [t["block"], t["block_need"]])
		ok = ok and int(t["block"]) >= int(t["block_need"])
		exact = int(t["block"]) == int(t["block_need"])
		total += int(t["block"])
	if int(t["attack_need"]) > 0:
		parts.append("ATTACK %d / %d" % [t["attack"], t["attack_need"]])
		ok = ok and int(t["attack"]) >= int(t["attack_need"])
		exact = exact or int(t["attack"]) == int(t["attack_need"])
		total += int(t["attack"])
	_total_label.text = "  ".join(parts) if parts.size() > 1 else parts[0] if not parts.is_empty() else ""
	_total_label.add_theme_font_size_override("font_size", 40 if parts.size() > 1 else 60)
	_total_label.add_theme_color_override("font_color", Style.GREEN if ok else Style.WHITE)
	if ok:
		_need_label.text = "Exakt!" if exact else "Det räcker"
	else:
		var miss := int(t["block_need"]) - int(t["block"])
		if miss > 0:
			var lives := 2 if miss >= int(s.balance["graded_threshold"]) else 1
			_need_label.text = "Miss %d → -%d liv" % [miss, lives]
		else:
			_need_label.text = "Skölden håller"
	_carry_label.text = ("Sparad sköld +%d inräknad" % t["carry"]) if int(t["carry"]) > 0 else ""
	if total != _last_total:
		_last_total = total
		_total_label.scale = Vector2(1.25, 1.25)
		create_tween().tween_property(_total_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
		if ok:
			main.sfx.play("select", 1.4)


# ---------------------------------------------------------------- input

func _on_card_tapped(cv: CardView) -> void:
	if main.is_busy():
		return
	var s = _e.state
	var c = s.find_in(s.hand, cv.card_id)
	if c == null:
		return
	if s.phase == Phase.PLAY:
		if not _e.can_play_card(c):
			cv.pop(-0.1)
			_hint_label.text = "Fel färg mot det här kortet"
			return
		if _selected.has(c.id):
			_selected.erase(c.id)
		else:
			_selected.append(c.id)
		main.sfx.play("select")
	elif s.phase == Phase.RETAIN:
		if _retain_sel.has(c.id):
			_retain_sel.erase(c.id)
		else:
			if _retain_sel.size() >= _e.retain_limit():
				_retain_sel.pop_front()
			_retain_sel.append(c.id)
		main.sfx.play("select")
	_update_controls()


func _on_main() -> void:
	if main.is_busy():
		return
	var s = _e.state
	if s.phase == Phase.PLAY:
		var sel := _selected.duplicate()
		_selected.clear()
		main.act(func():
			if sel.is_empty():
				_e.resolve()
				return
			var before: Array = s.hand.map(func(c): return c.id)
			_e.play_cards(sel)
			var fresh := false
			for c in _e.playable_cards():
				if not before.has(c.id):
					fresh = true
			if not fresh:
				_e.resolve())
	elif s.phase == Phase.RETAIN:
		var keep := _retain_sel.duplicate()
		_retain_sel.clear()
		main.act(func(): _e.retain(keep))


func _ace_dialog() -> void:
	var choices: Array = []
	for a in _e.sacrificable_aces():
		var ace = a
		choices.append(["Offra %s (−1 liv, +%d)" % [ace.label(), int(_e.state.balance["ace_value"])],
			func(): main.act(func(): _e.sacrifice_ace(ace.id)), Color("7a2a8c")])
	choices.append(["Avbryt", Callable(), Style.BLACK])
	main.confirm("Offra ett livs-ess?\nDu förlorar livet, esset räknas som 14 den här rundan.", choices)


func _open_menu() -> void:
	var choices: Array = [["Händelselogg", func(): main.open_log(), Style.BLUE]]
	if main.debug_unlocked:
		choices.append(["Debugmeny", func(): main.open_debug(), Color("7a2a8c")])
	choices.append(["Avsluta omgången", func(): main.quit_to_menu(), Style.RED])
	choices.append(["Tillbaka", Callable(), Style.BLACK])
	main.confirm("Seed %d" % _e.state.seed_value, choices)


func _show_pile(title: String, cards: Array) -> void:
	var v := VBoxContainer.new()
	v.add_child(Style.label("%s (%d)" % [title, cards.size()], 32, Style.GOLD))
	var grid := GridContainer.new()
	grid.columns = 5
	var sorted := cards.duplicate()
	sorted.sort_custom(func(a, b): return a.suit < b.suit or (a.suit == b.suit and a.rank < b.rank))
	for c in sorted:
		var cv := CardView.new()
		cv.set_interactive(false)
		cv.breathing = false
		cv.setup(c, Vector2(100, 140))
		grid.add_child(cv)
	if cards.is_empty():
		v.add_child(Style.label("Tom", 26, Style.MUTED))
	v.add_child(grid)
	var p := Style.panel(v)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var close := Style.button("Stäng", Style.BLACK)
	close.pressed.connect(p.queue_free)
	v.add_child(close)
	main.open_overlay(p)


# ---------------------------------------------------------------- events (animations)

func play_event(ev: Dictionary) -> float:
	var s = _e.state
	match ev["type"]:
		Ev.FLOOR_STARTED:
			_floor_strip.current = ev["floor"]
			_floor_strip.queue_redraw()
			for id in _table_views.keys():
				_table_views[id].queue_free()
			_table_views.clear()
			main.toast("Våning " + Style.floor_text(ev["floor"]) if ev["floor"] < 13 else "KUNGEN", Style.GOLD, 420)
			_reveal_fresh = true
			return 0.7
		Ev.JOKER_TRIGGERED:
			main.toast("JOKER!", Style.RED, 380)
			main.flash(Color(0.6, 0, 0.2, 0.4))
			_hint_label.text = ev["desc"]
			main.sfx.play("hit", 0.7)
			return 0.9
		Ev.ENEMY_REVEALED:
			if _reveal_fresh:
				_reveal_fresh = false
				for id in _enemy_views.keys():
					_enemy_views[id].queue_free()
				_enemy_views.clear()
			var card = _find_card(ev["id"])
			if card != null:
				var cv := CardView.new()
				cv.set_interactive(false)
				cv.setup(card, ENEMY_CARD)
				cv.face_up = false
				_enemy_layer.add_child(cv)
				_enemy_views[card.id] = cv
				_layout_enemies()
				cv.flip_to(true, 0.3)
				_sync_intents(_enemy_views.keys().map(func(id): return _find_card(id)).filter(func(c): return c != null))
				_left_label.text = ("Boss: %d kvar" if s.is_boss() else "%d kvar i fiendens hög") % ev["left"]
			main.sfx.play("flip")
			return 0.35
		Ev.HAND_FILLED:
			_reveal_fresh = true
			var i := 0
			for id in ev["ids"]:
				if not _hand_views.has(id):
					var c = _find_card(id)
					if c != null:
						_add_hand_card(c, i * 0.06)
						i += 1
			if i > 0:
				main.sfx.play("draw")
			_sync_preview()
			return 0.15 + i * 0.06
		Ev.CARD_DRAWN:
			var c = _find_card(ev["id"])
			if c != null and not _hand_views.has(c.id):
				_add_hand_card(c, 0.0)
			main.sfx.play("draw")
			return 0.2
		Ev.CARDS_PLAYED:
			for id in ev["ids"]:
				if _hand_views.has(id):
					_hand_views[id].queue_free()
					_hand_views.erase(id)
				var c = _find_card(id)
				if c != null and not _table_views.has(id):
					var cv := CardView.new()
					cv.set_interactive(false)
					cv.setup(c, Vector2(76, 106))
					_table.add_child(cv)
					_table_views[id] = cv
					cv.land(0.0, Vector2(0, 300))
			_layout_hand()
			_layout_table()
			main.sfx.play("play")
			return 0.25
		Ev.ACE_SACRIFICED:
			var c = _find_card(ev["temp_id"])
			if c != null:
				var cv := CardView.new()
				cv.set_interactive(false)
				cv.setup(c, Vector2(76, 106))
				_table.add_child(cv)
				_table_views[c.id] = cv
				_layout_table()
				cv.land(0.0, Vector2(0, -500))
			main.flash(Color(0.5, 0.1, 0.6, 0.4))
			return 0.3
		Ev.LIFE_LOST:
			for child in _lives_box.get_children():
				var cv := child as CardView
				if cv and cv.card_id == ev["id"] and cv.face_up:
					cv.shatter()
			main.sfx.play("crack")
			return 0.45
		Ev.LIFE_RESTORED:
			_sync_lives()
			main.toast("+1 LIV", Style.RED, 300, 52)
			main.sfx.play("reward")
			return 0.5
		Ev.BLOCKED:
			if ev["exact"]:
				main.flash(Color(1, 1, 1, 0.7), 0.35)
				main.toast("PRECIS!", Style.GOLD, 600)
				main.sfx.play("exact")
			else:
				main.toast("BLOCK!", Style.BLUE, 600)
				main.sfx.play("block")
			return 0.55
		Ev.DAMAGE_TAKEN:
			main.shake(28.0 if ev["lives"] >= 2 else 16.0)
			main.flash(Color(0.9, 0, 0, 0.45), 0.4)
			main.toast("-%d LIV" % ev["lives"], Style.RED, 600)
			main.sfx.play("hit")
			return 0.6
		Ev.SHIELD_STORED:
			_carry_label.text = "Sparad sköld: %d" % ev["amount"]
			_carry_label.scale = Vector2(1.4, 1.4)
			create_tween().tween_property(_carry_label, "scale", Vector2.ONE, 0.3)
			return 0.25
		Ev.ATTACK_SUCCEEDED:
			if ev["exact"]:
				main.flash(Color(1, 1, 1, 0.7), 0.35)
				main.toast("PRECIS!", Style.GOLD, 600)
				main.sfx.play("exact")
			else:
				main.toast("KROSS!", Style.GOLD, 600)
			main.shake(8.0)
			return 0.45
		Ev.ATTACK_FAILED:
			main.toast("Skölden håller", Style.BLUE, 600, 48)
			for id in _enemy_views:
				var cv: CardView = _enemy_views[id]
				var c = _find_card(id)
				if c != null and c.base_red():
					var tw := cv.create_tween()
					tw.tween_property(cv, "position:y", cv.position.y - 40, 0.12)
					tw.tween_property(cv, "position:y", cv.position.y + 500, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
					tw.parallel().tween_property(cv, "modulate:a", 0.0, 0.3)
			main.sfx.play("block", 0.7)
			return 0.6
		Ev.LOCKOUT:
			main.toast("LÅST!", Style.RED, 520)
			main.shake(20.0)
			main.sfx.play("hit", 0.8)
			return 0.8
		Ev.ENEMY_DEFEATED:
			if _enemy_views.has(ev["id"]):
				var cv: CardView = _enemy_views[ev["id"]]
				var center := cv.get_global_rect().get_center()
				main.burst(center, Style.suit_color(ev["suit"]) if ev["suit"] != "J" else Style.GOLD, 46)
				main.burst(center, Style.GOLD, 16)
				var tw := cv.create_tween()
				tw.tween_property(cv, "scale", cv.scale * 1.2, 0.08)
				tw.tween_property(cv, "scale", Vector2(0.01, 0.01), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			main.sfx.play("defeat")
			return 0.35
		Ev.RETAINED:
			for id in _table_views.keys():
				_table_views[id].queue_free()
			_table_views.clear()
			for id in _hand_views.keys():
				if not ev["ids"].has(id):
					var cv: CardView = _hand_views[id]
					var tw := cv.create_tween()
					tw.tween_property(cv, "position:y", cv.position.y + 300, 0.2)
					tw.tween_callback(cv.queue_free)
					_hand_views.erase(id)
			return 0.2
		Ev.FLOOR_CLEARED:
			main.toast("VÅNING KLAR!" if ev["floor"] < 13 else "KUNGEN FÄLLD!", Style.GOLD, 480)
			main.sfx.play("reward")
			return 0.9
		Ev.RUN_WON:
			main.toast("SEGER!", Style.GOLD, 480, 96)
			main.burst(size / 2, Style.GOLD, 80)
			main.sfx.play("win")
			return 1.4
		Ev.RUN_LOST:
			main.toast("FÖRLUST", Style.RED, 480, 96)
			main.shake(30.0)
			main.sfx.play("lose")
			return 1.4
	return 0.0


## Find a card object anywhere in the run state by id.
func _find_card(id: int):
	var s = _e.state
	for arr in [s.hand, s.played, s.current, s.enemy_pile, s.beaten, s.deck, s.discard, s.draw_pile, s.retained, s.lives, s.lost_lives]:
		for c in arr:
			if c.id == id:
				return c
	return _recent.get(id)


var _recent: Dictionary = {}
