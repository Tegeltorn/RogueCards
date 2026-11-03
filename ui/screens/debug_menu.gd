extends RefCounted
## Debug menu: edit balance values (saved locally, applied from the next run), force theme/mod,
## jump to a floor, give a life.

const Style := preload("res://ui/style.gd")
const Store := preload("res://ui/store.gd")
const Balance := preload("res://engine/balance.gd")
const SUITS := ["", "H", "D", "S", "C"]

var _main
var _edits: Dictionary = {}


func build(main) -> Control:
	_main = main
	var defaults := Balance.load_json(Balance.BALANCE_PATH)
	var ov := Store.overrides()
	var v := VBoxContainer.new()
	v.add_child(Style.label("Debugmeny", 40, Style.GOLD))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	# In-run actions.
	if main.engine != null and main.engine.state.result == "":
		body.add_child(Style.label("Pågående omgång", 26, Style.MUTED))
		var h := HBoxContainer.new()
		var floor_edit := SpinBox.new()
		floor_edit.min_value = 3
		floor_edit.max_value = 13
		floor_edit.value = main.engine.state.floor_num
		floor_edit.custom_minimum_size = Vector2(160, 64)
		h.add_child(floor_edit)
		var jump := Style.button("Hoppa till våning", Style.BLUE, 22)
		jump.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		jump.pressed.connect(func():
			_close(v)
			main.act(func(): main.engine.debug_jump_to_floor(int(floor_edit.value))))
		h.add_child(jump)
		body.add_child(h)
		var life := Style.button("Ge ett liv", Style.RED, 22)
		life.pressed.connect(func():
			_close(v)
			main.act(func(): main.engine.debug_give_life()))
		body.add_child(life)

	body.add_child(Style.label("Tvinga (nästa omgång)", 26, Style.MUTED))
	for pair in [["force_theme", "Temakung"], ["force_mod", "Modess"]]:
		var h := HBoxContainer.new()
		var l := Style.label(pair[1], 24, Style.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(220, 60)
		for s in SUITS:
			ob.add_item("Slump" if s == "" else Style.SUIT_SYM[s] + " " + Style.SUIT_NAME[s])
		ob.selected = SUITS.find(main.settings.get(pair[0], ""))
		var key: String = pair[0]
		ob.item_selected.connect(func(i):
			main.settings[key] = SUITS[i]
			main.apply_settings())
		h.add_child(ob)
		body.add_child(h)

	body.add_child(Style.label("Balans (nästa omgång)", 26, Style.MUTED))
	for key in defaults:
		if typeof(defaults[key]) == TYPE_DICTIONARY:
			continue
		var cur = ov.get(key, defaults[key])
		var h := HBoxContainer.new()
		var l := Style.label(key, 20, Style.GOLD if ov.has(key) else Style.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		if typeof(defaults[key]) == TYPE_BOOL:
			var cb := CheckBox.new()
			cb.button_pressed = bool(cur)
			cb.focus_mode = Control.FOCUS_NONE
			h.add_child(cb)
			_edits[key] = cb
		else:
			var le := LineEdit.new()
			le.text = _fmt(cur)
			le.custom_minimum_size = Vector2(200, 56)
			h.add_child(le)
			_edits[key] = le
		body.add_child(h)

	var p := Style.panel(v)
	var row := HBoxContainer.new()
	var save := Style.button("Spara", Style.GREEN, 24)
	save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save.pressed.connect(func():
		_save(defaults)
		p.queue_free())
	row.add_child(save)
	var reset := Style.button("Återställ", Style.RED, 24)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func():
		Store.save_overrides({})
		p.queue_free())
	row.add_child(reset)
	var close := Style.button("Stäng", Style.BLACK, 24)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(p.queue_free)
	row.add_child(close)
	v.add_child(row)
	return p


func _close(v: Control) -> void:
	var p := v.get_parent()
	if p:
		p.queue_free()


func _save(defaults: Dictionary) -> void:
	var ov := {}
	for key in _edits:
		var w = _edits[key]
		var val
		if w is CheckBox:
			val = w.button_pressed
		else:
			val = JSON.parse_string(w.text)
			if val == null:
				val = w.text
		if _fmt(val) != _fmt(defaults[key]):
			ov[key] = val
	Store.save_overrides(ov)
	_main.toast("Sparat – gäller nästa omgång", Style.GREEN, 600, 36)


static func _fmt(v) -> String:
	if typeof(v) == TYPE_ARRAY:
		return "[" + ",".join(v.map(func(x): return _fmt(x))) + "]"
	if typeof(v) == TYPE_FLOAT and v == floor(v):
		return str(int(v))
	if typeof(v) == TYPE_STRING:
		return v
	return str(v)
