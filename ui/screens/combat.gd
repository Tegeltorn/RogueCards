extends Control
## The fight screen (portrait, top to bottom): floor strip + lives, enemy card with intent,
## live total vs enemy value, played cards, fanned hand, piles and action buttons.

const Style := preload("res://ui/style.gd")
const CardView := preload("res://ui/card_view.gd")
const GameState := preload("res://engine/game_state.gd")
const Ev := preload("res://engine/events.gd")
const Help := preload("res://ui/screens/help.gd")
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
	var current := 4
	var first := 4
	var font: Font

	func _draw() -> void:
		var n := 14 - first
		var w := (size.x - (n - 1) * 6) / n
		for i in n:
			var f := first + i
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
var _stack_layer: Control
var _total_label: RichTextLabel
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
var _help_btn: Button
var _tooltip: PanelContainer
var _tooltip_label: Label
var _lives_caption: Label
var _showdown: PanelContainer
var _showdown_label: RichTextLabel
var _finish_tip: PanelContainer
var _finish_label: RichTextLabel
var _mods_caption: Label
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
		_floor_strip.first = _e.first_floor()
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
	_tappable(_lives_box, func(): main.open_overlay(Help.aces_overlay(main)))
	add_child(_lives_box)
	_info_box = HBoxContainer.new()
	_info_box.add_theme_constant_override("separation", 6)
	_tappable(_info_box, func(): main.open_overlay(Help.mods_overlay(main)))
	add_child(_info_box)
	_lives_caption = Style.label("LIVES", 18, Style.MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	_lives_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_lives_caption)
	_mods_caption = Style.label("MODS", 18, Style.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_mods_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_mods_caption)
	_seed_label = Style.label("", 18, Style.MUTED)
	add_child(_seed_label)
	_help_btn = Style.button("?", Style.BLUE, 34)
	_help_btn.custom_minimum_size = Vector2(76, 56)
	_help_btn.pressed.connect(func(): main.open_overlay(Help.rules_overlay(main)))
	add_child(_help_btn)
	_menu_btn = Style.button("MENU", Style.BLACK, 24)
	_menu_btn.custom_minimum_size = Vector2(100, 56)
	_menu_btn.pressed.connect(_open_menu)
	add_child(_menu_btn)

	_stack_layer = Control.new()
	_stack_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack_layer)
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

	_total_label = RichTextLabel.new()
	_total_label.bbcode_enabled = true
	_total_label.scroll_active = false
	_total_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_total_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_total_label.add_theme_constant_override("outline_size", 12)
	_total_label.add_theme_color_override("font_outline_color", Style.INK)
	_total_label.add_theme_font_size_override("normal_font_size", 60)
	add_child(_total_label)
	_showdown = PanelContainer.new()
	_showdown.add_theme_stylebox_override("panel", Style.box(Color(0.55, 0.05, 0.12, 0.95), Style.GOLD, 4, 10))
	_showdown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_showdown_label = RichTextLabel.new()
	_showdown_label.bbcode_enabled = true
	_showdown_label.fit_content = true
	_showdown_label.scroll_active = false
	_showdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_showdown_label.add_theme_font_size_override("normal_font_size", 22)
	_showdown.add_child(_showdown_label)
	_showdown.visible = false
	_showdown.z_index = 20
	add_child(_showdown)
	_finish_tip = PanelContainer.new()
	_finish_tip.add_theme_stylebox_override("panel", Style.box(Color(0.06, 0.04, 0.1, 0.9), Color(Style.GOLD, 0.7), 3, 10))
	_finish_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finish_label = RichTextLabel.new()
	_finish_label.bbcode_enabled = true
	_finish_label.fit_content = true
	_finish_label.scroll_active = false
	_finish_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_finish_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finish_label.add_theme_font_size_override("normal_font_size", 20)
	_finish_tip.add_child(_finish_label)
	_finish_tip.visible = false
	add_child(_finish_tip)
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
	_draw_btn.pressed.connect(func(): _show_pile("Draw pile", _e.state.draw_pile))
	add_child(_draw_btn)
	_disc_btn = Style.button("", Style.BLACK, 22)
	_disc_btn.custom_minimum_size = Vector2(110, 80)
	_disc_btn.pressed.connect(func(): _show_pile("Discard pile", _e.state.discard))
	add_child(_disc_btn)
	_main_btn = Style.button("End turn", Style.RED, 32)
	_main_btn.custom_minimum_size = Vector2(200, 92)
	_main_btn.pressed.connect(_on_main)
	add_child(_main_btn)

	_tooltip = PanelContainer.new()
	_tooltip.add_theme_stylebox_override("panel", Style.box(Color(0.06, 0.04, 0.1, 0.96), Style.GOLD, 3, 12))
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label = Style.label("", 22, Style.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_tooltip_label.custom_minimum_size = Vector2(380, 0)
	_tooltip.add_child(_tooltip_label)
	_tooltip.visible = false
	_tooltip.z_index = 50
	add_child(_tooltip)


## Makes a container react to taps (its card children ignore input).
func _tappable(c: Control, fn: Callable) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed and not main.is_busy():
			main.sfx.play("select")
			fn.call())


func _layout() -> void:
	var W := size.x
	var H := size.y
	_floor_strip.position = Vector2(16, 16)
	_floor_strip.size = Vector2(W - 224, 44)
	_help_btn.position = Vector2(W - 200, 10)
	_help_btn.size = Vector2(76, 56)
	_menu_btn.position = Vector2(W - 112, 10)
	_menu_btn.size = Vector2(100, 56)
	_info_box.position = Vector2(W - 16 - 2 * MINI.x - 6, 74)

	_mods_caption.position = Vector2(W - 216, 74 + MINI.y + 2)
	_mods_caption.size = Vector2(200, 24)
	_seed_label.position = Vector2(18, 74)
	_seed_label.size = Vector2(300, 24)
	_seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var ey := 190.0 + maxf(0.0, (H - 1280.0) * 0.25)
	_enemy_layer.position = Vector2(0, ey)
	_enemy_layer.size = Vector2(W, ENEMY_CARD.y)
	_stack_layer.position = Vector2(0, ey)
	_stack_layer.size = Vector2(W, ENEMY_CARD.y)
	_intent_layer.position = Vector2(0, ey)
	_intent_layer.size = Vector2(W, ENEMY_CARD.y)
	_left_label.position = Vector2(0, ey + ENEMY_CARD.y + 8)
	_left_label.size = Vector2(W, 30)
	_preview_box.position = Vector2(W - 16 - 2 * MINI.x - 6, ey + ENEMY_CARD.y - MINI.y - 30)
	var ty := ey + ENEMY_CARD.y + 40
	_total_label.position = Vector2(0, ty)
	_total_label.size = Vector2(W, 80)
	_total_label.pivot_offset = Vector2(W / 2, 40)
	_showdown.position = Vector2(W / 2 - 230, ey + ENEMY_CARD.y - 96)
	_finish_tip.position = Vector2(12, ey + 20)
	_showdown.size = Vector2(460, 0)
	_need_label.position = Vector2(0, ty + 72)
	_need_label.size = Vector2(W, 30)
	_carry_label.position = Vector2(0, ty + 100)
	_carry_label.size = Vector2(W, 28)
	var by := H - 106
	# Lives sit in the bottom bar between the draw pile and the main button.
	_lives_box.position = Vector2(132, by + 2)
	_lives_caption.position = Vector2(132, by - 22)
	_lives_caption.size = Vector2(180, 22)
	_draw_btn.position = Vector2(14, by)
	_disc_btn.position = Vector2(W - 124, by)
	# Bottom bar: Draw | lives | Play | End turn | Discard
	_main_btn.position = Vector2(326, by - 6)
	_main_btn.size = Vector2(W - 124 - 8 - 326, 92)
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
	_floor_strip.first = _e.first_floor()
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
	_left_label.text = _left_text(s.enemy_pile.size() + s.current.size())


## Foresight: the next enemy card, face up, labelled NEXT.
func _sync_preview() -> void:
	for c in _preview_box.get_children():
		c.queue_free()
	for c in _e.preview_enemies():
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		var l := Style.label("NEXT", 16, Style.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		v.add_child(l)
		v.add_child(_mini(c))
		_preview_box.add_child(v)
	_sync_stack(_e.state.enemy_pile.size())


## The enemy pile: a staggered stack of face-down cards behind the current enemy.
func _sync_stack(n: int) -> void:
	for c in _stack_layer.get_children():
		c.queue_free()
	var shown := mini(n, 8)
	for k in shown:
		var i := shown - 1 - k  # deepest card first
		var cv := CardView.new()
		cv.set_interactive(false)
		cv.breathing = false
		cv.setup(null, ENEMY_CARD)
		cv.face_up = false
		cv.position = Vector2(size.x / 2 - ENEMY_CARD.x / 2 + (i + 1) * 12, -(i + 1) * 10)
		_stack_layer.add_child(cv)


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
	cv.draggable = true
	cv.tapped.connect(_on_card_tapped)
	cv.drag_started.connect(_on_drag_started)
	cv.drag_moved.connect(_on_drag_moved)
	cv.drag_released.connect(_on_drag_released)
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


## Played cards are not shown on a table any more: they tap the enemy and go to the discard pile.
func _sync_table() -> void:
	for id in _table_views.keys():
		_table_views[id].queue_free()
	_table_views.clear()


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
		cv.dimmed = false
		cv.set_selected((playing and _selected.has(id)) or (retaining and _retain_sel.has(id)))
		if retaining and _retain_sel.has(id):
			cv.highlight = Style.GOLD
		elif playing and _e.is_effective(c):
			cv.highlight = Color(Style.GREEN, 0.85)  # counts against the current enemy
		else:
			cv.highlight = Color(0, 0, 0, 0)
	_main_btn.disabled = main.is_busy()
	if playing:
		_main_btn.text = "End turn"
		_hint_label.text = "Drag cards onto the enemy to play them – tap to inspect" if _selected.is_empty() else ""
	elif retaining:
		_main_btn.text = "Continue"
		_hint_label.text = "Tap to keep %d card for next round" % _e.retain_limit()
	else:
		_hint_label.text = ""
	_draw_btn.text = "Draw\n%d" % s.draw_pile.size()
	_disc_btn.text = "Discard\n%d" % (s.discard.size() + s.played.filter(func(c): return not c.temp).size())
	_update_total()
	_update_life_glow()
	_update_tooltip()


## Life aces glow when a sacrifice could help (you would miss the block or fail the shield).
func _update_life_glow() -> void:
	var s = _e.state
	var usable: Array = _e.sacrificable_aces().map(func(a): return a.id)
	var short := false
	if s.phase == Phase.PLAY and not s.current.is_empty():
		var t: Dictionary = _e.preview(_selected)
		short = int(t["block"]) < int(t["block_need"]) or int(t["attack"]) < int(t["attack_need"])
	for child in _lives_box.get_children():
		var cv := child as CardView
		if cv and cv.face_up:
			cv.highlight = Color("b05cff") if short and usable.has(cv.card_id) else Color(0, 0, 0, 0)


## Small explanation above the card when exactly one card is selected.
func _update_tooltip() -> void:
	var s = _e.state
	var sel: Array = _selected if s.phase == Phase.PLAY else _retain_sel
	if sel.size() != 1 or not _hand_views.has(sel[0]):
		_tooltip.visible = false
		return
	var c = s.find_in(s.hand, sel[0])
	if c == null:
		_tooltip.visible = false
		return
	_tooltip_label.text = c.label() + ":  " + Help.card_effect(_e, c)
	_tooltip.visible = true
	_tooltip.reset_size()
	var cv: CardView = _hand_views[sel[0]]
	var w := _tooltip.size.x
	var x := clampf(_hand_layer.position.x + cv.position.x + HAND_CARD.x / 2 - w / 2, 12, size.x - w - 12)
	_tooltip.position = Vector2(x, _hand_layer.position.y - _tooltip.size.y - 56)
	_hint_label.text = ""


func _left_text(n: int) -> String:
	return "%d enemy card%s left" % [n, "" if n == 1 else "s"]


func _update_total() -> void:
	var s = _e.state
	_update_showdown()
	if s.phase != Phase.PLAY or s.current.is_empty():
		_total_label.text = ""
		_need_label.text = ""
		_carry_label.text = ("Stored shield from ♥: %d" % s.carry_shield) if s.carry_shield > 0 else ""
		return
	_carry_label.text = ""
	var t: Dictionary = _e.preview(_selected)
	var parts: Array = []
	var ok := true
	var exact := false
	var total := 0
	if int(t["block_need"]) > 0:
		var part := "BLOCK %d / %d" % [t["block"], t["block_need"]]
		if int(t["carry"]) > 0:
			part += " [font_size=26][color=#3d8bfd](+%d stored from [color=#e0383e]♥[/color])[/color][/font_size]" % int(t["carry"])
		parts.append(part)
		ok = ok and int(t["block"]) >= int(t["block_need"])
		exact = int(t["block"]) == int(t["block_need"])
		total += int(t["block"])
	if int(t["attack_need"]) > 0:
		parts.append("ATTACK %d / %d" % [t["attack"], t["attack_need"]])
		ok = ok and int(t["attack"]) >= int(t["attack_need"])
		exact = exact or int(t["attack"]) == int(t["attack_need"])
		total += int(t["attack"])
	var col := "#2ec27e" if ok else "#fffaf0"
	var fs := 40 if parts.size() > 1 else 60
	_total_label.text = "[center][font_size=%d][color=%s]%s[/color][/font_size][/center]" % [fs, col, "  ".join(parts)]
	if ok:
		_need_label.text = "Exact!" if exact else "Enough"
	else:
		var miss := int(t["block_need"]) - int(t["block"])
		if miss > 0:
			var lives := 2 if miss >= int(s.balance["graded_threshold"]) else 1
			_need_label.text = "Miss by %d: -%d %s" % [miss, lives, "life" if lives == 1 else "lives"]
		elif _e.lockout_risk():
			_need_label.text = "Not enough: -1 life"
		else:
			_need_label.text = "The shield holds"
	_need_label.add_theme_color_override("font_color", Style.MUTED)
	var sel_cards: Array = []
	for id in _selected:
		var sc = s.find_in(s.hand, id)
		if sc != null:
			sel_cards.append(sc)
	var has_black: bool = sel_cards.any(func(c): return c.is_black() and not c.is_red())
	if has_black and int(t["block_need"]) > 0 and int(t["attack_need"]) == 0:
		if _e.overpower_value(sel_cards) > 0:
			_need_label.text = "OVERPOWER! Play: discard them, draw 1"
			_need_label.add_theme_color_override("font_color", Style.GOLD)
		else:
			_need_label.text += "  ·  black %d/%d for overpower" % [_black_value(sel_cards), int(s.balance.get("overpower_multiplier", 2)) * int(t["block_need"])]
	if int(t["block_need"]) == 0 and int(t["hearts"]) > 0:
		_need_label.text += "  ·  ♥ stores %d shield" % int(t["hearts"])
	if total != _last_total:
		_last_total = total
		_total_label.scale = Vector2(1.25, 1.25)
		create_tween().tween_property(_total_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
		if ok:
			main.sfx.play("select", 1.4)


const SHOWDOWN_FLAVOUR := [
	"The enemy is cornered and fighting for its life.",
	"No allies left. It is a desperate last stand.",
	"Final showdown: it won't go down quietly.",
	"Its back is against the wall, and it is getting desperate.",
]


## Red ribbon over the enemy when failing this shield would cost a life (no black enemy cards left).
func _black_value(cards: Array) -> int:
	var t: Dictionary = _e.compute(cards.filter(func(c): return c.is_black() and not c.is_red()))
	return int(t["attack"])


## Small tip left of the enemy on a floor's last card: what each suit gives when you finish on it.
func _update_finish_tip() -> void:
	var s = _e.state
	var show: bool = s.phase == Phase.PLAY and not s.is_boss() and s.enemy_pile.is_empty() and s.current.size() == 1
	_finish_tip.visible = show
	if not show:
		return
	var cur: String = s.current[0].suit
	var lines: Array = ["[color=#f4b942]FINISH ON[/color]"]
	for suit in ["S", "C", "H", "D"]:
		var r: Dictionary = _e.reward_rules(suit)
		var txt := ""
		match suit:
			"S": txt = "pick any"
			"C": txt = "take 1 of %d, cut 1" % int(r["reveal"])
			"H":
				var h := int(r["heal"])
				txt = "+%d %s" % [h, "life" if h == 1 else "lives"]
			"D": txt = "take %d of %d" % [int(r["picks"]), int(r["reveal"])] if int(r["picks"]) < int(r["reveal"]) else "take %d" % int(r["picks"])
		var col := "#e0383e" if suit == "H" or suit == "D" else "#fffaf0"
		var line := "[color=%s]%s[/color] %s" % [col, Style.SUIT_SYM[suit], txt]
		if suit == cur:
			line = "[color=#2ec27e]> [/color]" + line
		lines.append(line)
	_finish_label.text = "\n".join(lines)


func _update_showdown() -> void:
	_update_finish_tip()
	var s = _e.state
	var risk: bool = s.phase == Phase.PLAY and _e.lockout_risk()
	if not risk:
		_showdown.visible = false
		return
	var flavour: String = SHOWDOWN_FLAVOUR[int(s.current[0].id) % SHOWDOWN_FLAVOUR.size()]
	_showdown_label.text = "[center][font_size=30][color=#f4b942]LAST STAND![/color][/font_size]\n%s\n[color=#ffd0d0]Fail to break this shield and you lose a life.[/color][/center]" % flavour
	if not _showdown.visible:
		_showdown.visible = true
		_showdown.pivot_offset = Vector2(230, 50)
		_showdown.scale = Vector2(0.6, 0.6)
		create_tween().tween_property(_showdown, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- input

func _on_card_tapped(cv: CardView) -> void:
	if main.is_busy():
		return
	var s = _e.state
	var c = s.find_in(s.hand, cv.card_id)
	if c == null:
		return
	if s.phase == Phase.PLAY:
		# Tap inspects one card (tooltip + preview); drag it onto the enemy to play it.
		_selected = [] if _selected.has(c.id) else [c.id]
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


# ---------------------------------------------------------------- drag to play

## Everything above the hand counts as "on the enemy" (a large, forgiving drop zone).
func _drop_zone() -> Rect2:
	return Rect2(global_position + Vector2(0, 110), Vector2(size.x, _hand_layer.position.y - 130))


func _on_drag_started(cv: CardView) -> void:
	if main.is_busy() or _e.state.phase != Phase.PLAY:
		return
	_selected = [cv.card_id]
	cv.z_index = 60
	cv.set_selected(false)
	_update_controls()


func _on_drag_moved(cv: CardView, pos: Vector2) -> void:
	if _e.state.phase != Phase.PLAY:
		return
	cv.global_position = pos - HAND_CARD / 2 - Vector2(0, 50)
	cv.rotation = lerpf(cv.rotation, 0.0, 0.3)
	var over := _drop_zone().has_point(pos)
	for id in _enemy_views:
		_enemy_views[id].highlight = Style.GOLD if over else Color(0, 0, 0, 0)


func _on_drag_released(cv: CardView, pos: Vector2) -> void:
	for id in _enemy_views:
		_enemy_views[id].highlight = Color(0, 0, 0, 0)
	# Free discard (option): drop the card on the Discard button.
	if _e.can_discard() and not main.is_busy() and _disc_btn.get_global_rect().grow(30).has_point(pos) and _hand_views.has(cv.card_id):
		var did := cv.card_id
		_hand_views.erase(did)
		_selected.clear()
		var tw := cv.create_tween()
		tw.tween_property(cv, "global_position", _disc_btn.get_global_rect().get_center() - cv.size / 2, 0.2)
		tw.parallel().tween_property(cv, "scale", Vector2(0.3, 0.3), 0.2)
		tw.tween_callback(cv.queue_free)
		main.sfx.play("draw")
		main.act(func(): _e.discard_card(did))
		_layout_hand()
		return
	if _e.state.phase == Phase.PLAY and not main.is_busy() and _drop_zone().has_point(pos) and _hand_views.has(cv.card_id):
		var id := cv.card_id
		_hand_views.erase(id)
		_selected.clear()
		_tap_enemy(cv)
		main.act(func(): _e.play_cards([id]))
		return
	# Not on the enemy: slide back into the hand.
	var from := cv.global_position
	_layout_hand()
	var to := cv.position
	cv.global_position = from
	cv.create_tween().tween_property(cv, "position", to, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The played card flies to the enemy, taps it, then drops into the discard pile.
func _tap_enemy(cv: CardView) -> void:
	cv.z_index = 60
	cv.set_interactive(false)
	cv.breathing = false
	var center := _enemy_layer.global_position + Vector2(size.x / 2, ENEMY_CARD.y * 0.45)
	var dest := _disc_btn.get_global_rect().get_center()
	var tw := cv.create_tween()
	tw.tween_property(cv, "global_position", center - cv.size / 2 + Vector2(0, 40), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(cv, "rotation", -0.18, 0.14)
	tw.tween_property(cv, "rotation", 0.12, 0.06)
	tw.parallel().tween_property(cv, "scale", Vector2(1.12, 1.12), 0.06)
	tw.tween_callback(func():
		main.burst(center, Style.WHITE, 12)
		main.shake(5.0)
		for id in _enemy_views:
			_enemy_views[id].pop(0.08))
	tw.tween_property(cv, "rotation", 0.0, 0.06)
	tw.parallel().tween_property(cv, "scale", Vector2.ONE, 0.06)
	tw.tween_interval(0.05)
	tw.tween_property(cv, "global_position", dest - cv.size / 2, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(cv, "scale", Vector2(0.3, 0.3), 0.28)
	tw.parallel().tween_property(cv, "modulate:a", 0.4, 0.28)
	tw.tween_callback(cv.queue_free)
	main.sfx.play("play")
	_layout_hand()


## End turn: plays anything still selected, then resolves the round (or confirms the kept card).
func _on_main() -> void:
	if main.is_busy():
		return
	var s = _e.state
	if s.phase == Phase.PLAY:
		var sel := _selected.duplicate()
		_selected.clear()
		main.act(func():
			if not sel.is_empty():
				_e.play_cards(sel)
			_e.resolve())
	elif s.phase == Phase.RETAIN:
		var keep := _retain_sel.duplicate()
		_retain_sel.clear()
		main.act(func(): _e.retain(keep))


func _open_menu() -> void:
	var choices: Array = [["How to play", func(): main.open_overlay(Help.rules_overlay(main)), Style.BLUE],
		["Event log", func(): main.open_log(), Style.BLUE]]
	if main.debug_unlocked:
		choices.append(["Debug menu", func(): main.open_debug(), Color("7a2a8c")])
	choices.append(["Quit run", func(): main.quit_to_menu(), Style.RED])
	choices.append(["Back", Callable(), Style.BLACK])
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
		v.add_child(Style.label("Empty", 26, Style.MUTED))
	v.add_child(grid)
	var p := Style.panel(v)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var close := Style.button("Close", Style.BLACK)
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
			main.toast("Floor " + Style.floor_text(ev["floor"]) if ev["floor"] < 13 else "THE KINGS", Style.GOLD, 420)
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
				_left_label.text = _left_text(int(ev.get("total_left", ev["left"] + 1)))
				_sync_stack(int(ev["left"]))
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
		Ev.OVERPOWER:
			main.toast("OVERPOWER!", Style.GOLD, 600)
			main.shake(10.0)
			main.sfx.play("exact", 0.8)
			return 0.5
		Ev.CARDS_PLAYED:
			# Dragged cards are already animating; cards played another way (tests) tap the enemy here.
			var any := false
			for id in ev["ids"]:
				if _hand_views.has(id):
					var cv: CardView = _hand_views[id]
					_hand_views.erase(id)
					_tap_enemy(cv)
					any = true
			_layout_hand()
			return 0.3 if any else 0.15
		Ev.ACE_SACRIFICED:
			var c = _find_card(ev["temp_id"])
			if c != null:
				var cv := CardView.new()
				cv.setup(c, HAND_CARD)
				add_child(cv)
				cv.global_position = _lives_box.get_global_rect().get_center() - HAND_CARD / 2
				_tap_enemy(cv)
			main.flash(Color(0.5, 0.1, 0.6, 0.4))
			return 0.4
		Ev.LIFE_LOST:
			for child in _lives_box.get_children():
				var cv := child as CardView
				if cv and cv.card_id == ev["id"] and cv.face_up:
					cv.shatter()
			main.sfx.play("crack")
			return 0.45
		Ev.LIFE_RESTORED:
			_sync_lives()
			main.toast("+1 LIFE", Style.RED, 300, 52)
			main.sfx.play("reward")
			return 0.5
		Ev.BLOCKED:
			if ev["exact"]:
				main.flash(Color(1, 1, 1, 0.7), 0.35)
				main.toast("EXACT!", Style.GOLD, 600)
				main.sfx.play("exact")
			else:
				main.toast("BLOCK!", Style.BLUE, 600)
				main.sfx.play("block")
			return 0.55
		Ev.DAMAGE_TAKEN:
			main.shake(28.0 if ev["lives"] >= 2 else 16.0)
			main.flash(Color(0.9, 0, 0, 0.45), 0.4)
			main.toast("-%d %s" % [ev["lives"], "LIFE" if ev["lives"] == 1 else "LIVES"], Style.RED, 600)
			main.sfx.play("hit")
			return 0.6
		Ev.SHIELD_STORED:
			main.toast("+%d SHIELD STORED" % ev["amount"], Style.BLUE, 680, 40)
			return 0.25
		Ev.ATTACK_SUCCEEDED:
			if ev["exact"]:
				main.flash(Color(1, 1, 1, 0.7), 0.35)
				main.toast("EXACT!", Style.GOLD, 600)
				main.sfx.play("exact")
			else:
				main.toast("BREAK!", Style.GOLD, 600)
			main.shake(8.0)
			return 0.45
		Ev.ATTACK_FAILED:
			main.toast("The shield holds", Style.BLUE, 600, 48)
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
			main.toast("LAST STAND!", Style.RED, 520)
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
			main.toast("FLOOR CLEARED!" if ev["floor"] < 13 else "KINGS DEFEATED!", Style.GOLD, 480)
			main.sfx.play("reward")
			return 0.9
		Ev.RUN_WON:
			main.toast("VICTORY!", Style.GOLD, 480, 96)
			main.burst(size / 2, Style.GOLD, 80)
			main.sfx.play("win")
			return 1.4
		Ev.RUN_LOST:
			main.toast("DEFEAT", Style.RED, 480, 96)
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
