extends Control
## Title screen. Long-press the title (0.8 s) to unlock and open the debug menu.

const Style := preload("res://ui/style.gd")
const CardView := preload("res://ui/card_view.gd")
const Help := preload("res://ui/screens/help.gd")

var main
var _hold := 0.0
var _holding := false
var _title: Label
var _seed_edit: LineEdit


func enter() -> void:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	var m := Style.full(MarginContainer.new())
	for s in ["left", "right"]:
		m.add_theme_constant_override("margin_" + s, 60)
	add_child(m)
	m.add_child(v)

	var fan := Control.new()
	fan.custom_minimum_size = Vector2(0, 250)
	fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(fan)
	var suits := ["S", "H", "C", "D"]
	for i in 4:
		var cv := CardView.new()
		cv.set_interactive(false)
		cv.rank = 14
		cv.suit = suits[i]
		cv.setup(null, Vector2(130, 182))
		cv.position = Vector2(300 - 2 * 80 + i * 80 - 65 + 40, 40 + absf(i - 1.5) * 18)
		cv.rotation = (i - 1.5) * 0.18
		fan.add_child(cv)
		cv.land(0.1 * i)

	_title = Style.label("RogueCards", 78, Style.GOLD)
	_title.add_theme_constant_override("outline_size", 10)
	_title.mouse_filter = Control.MOUSE_FILTER_STOP
	_title.gui_input.connect(_on_title_input)
	_title.pivot_offset = Vector2(300, 50)
	v.add_child(_title)
	v.add_child(Style.label("A roguelike deckbuilder with a standard deck of cards", 26, Style.MUTED))
	v.add_child(Style.ornament())

	var play := Style.button("New run", Style.RED, 38)
	play.custom_minimum_size.y = 96
	play.pressed.connect(func(): main.new_run())
	v.add_child(play)

	var h := HBoxContainer.new()
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "seed"
	_seed_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.custom_minimum_size.y = 76
	h.add_child(_seed_edit)
	var sb := Style.button("Play seed", Style.BLUE, 26)
	sb.pressed.connect(func():
		var t := _seed_edit.text.strip_edges()
		if t.is_valid_int():
			main.new_run(int(t)))
	h.add_child(sb)
	v.add_child(h)

	var stats := Style.button("Stats", Style.BLACK, 28)
	stats.pressed.connect(func(): main.open_stats())
	v.add_child(stats)

	# Shown when a newer build is out (checked on start by ui/updater.gd).
	var upd := Style.button("Update available – tap to update", Style.GREEN, 28)
	upd.visible = main.updater != null and main.updater.available
	upd.pressed.connect(func():
		upd.text = "Updating…"
		upd.disabled = true
		main.updater.apply())
	v.add_child(upd)
	if main.updater != null and not main.updater.available:
		main.updater.update_available.connect(func():
			if is_instance_valid(upd):
				upd.visible = true
				upd.pivot_offset = upd.size / 2
				upd.scale = Vector2(0.9, 0.9)
				upd.create_tween().tween_property(upd, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_SINE))

	var toggles := HFlowContainer.new()
	toggles.alignment = FlowContainer.ALIGNMENT_CENTER
	toggles.add_theme_constant_override("h_separation", 10)
	for key in ["night", "crt", "sound", "vibration"]:
		var cb := CheckBox.new()
		cb.text = {"night": "Night", "crt": "Vignette", "sound": "Sound", "vibration": "Vibration"}[key]
		cb.button_pressed = bool(main.settings.get(key, key != "night"))
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(on):
			main.settings[key] = on
			main.apply_settings())
		toggles.add_child(cb)
	v.add_child(toggles)
	var hint_text := "Hold the title for the debug menu"
	if main.updater != null and not main.updater.build.is_empty():
		hint_text += "  ·  build %s" % str(main.updater.build.get("sha", "")).left(7)
	var hint := Style.label(hint_text, 18, Color(Style.MUTED, 0.6))
	v.add_child(hint)

	var help := Style.button("?", Style.BLUE, 34)
	help.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	help.offset_left = -92
	help.offset_right = -16
	help.offset_top = 16
	help.offset_bottom = 72
	help.pressed.connect(func(): main.open_overlay(Help.rules_overlay(main)))
	add_child(help)


func _process(delta: float) -> void:
	if _title == null:
		return
	_title.rotation = sin(Time.get_ticks_msec() / 1400.0) * 0.008
	if _holding:
		_hold += delta
		_title.scale = Vector2.ONE * (1.0 + minf(_hold, 0.8) * 0.15)
		if _hold >= 0.8:
			_holding = false
			_title.scale = Vector2.ONE
			main.debug_unlocked = true
			main.sfx.play("exact")
			main.open_debug()
	else:
		_title.scale = _title.scale.lerp(Vector2.ONE, 0.2)


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_holding = event.pressed
		_hold = 0.0
