extends RefCounted
## Scrollable event log for the current run, with copy to clipboard.

const Style := preload("res://ui/style.gd")
const Ev := preload("res://engine/events.gd")


func build(main) -> Control:
	var s = main.engine.state
	var lines: Array = []
	for e in s.events:
		lines.append(Ev.describe(e))
	var text := "\n".join(lines)
	var v := VBoxContainer.new()
	v.add_child(Style.label("Event log – seed %d" % s.seed_value, 30, Style.GOLD))
	var rt := RichTextLabel.new()
	rt.text = text
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.scroll_following = true
	rt.selection_enabled = true
	rt.add_theme_font_size_override("normal_font_size", 22)
	v.add_child(rt)
	var h := HBoxContainer.new()
	var copy := Style.button("Copy", Style.BLUE, 26)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.pressed.connect(func():
		DisplayServer.clipboard_set("RogueCards seed %d\n%s" % [s.seed_value, text])
		copy.text = "Copied!")
	h.add_child(copy)
	var p := Style.panel(v)
	var close := Style.button("Close", Style.BLACK, 26)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(p.queue_free)
	h.add_child(close)
	v.add_child(h)
	return p
