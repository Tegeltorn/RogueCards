extends RefCounted
## Local play statistics: runs, win rate vs target, best run, losses per floor, per mod ace.

const Style := preload("res://ui/style.gd")
const Store := preload("res://ui/store.gd")
const SUITS := ["H", "D", "S", "C"]


func build(main) -> Control:
	var d := Store.stats()
	var runs := int(d["runs"])
	var wins := int(d["wins"])
	var target := float(main.balance().get("target", {}).get("human_win_rate", 0.25)) * 100.0
	var lines: Array = []
	lines.append("[b]Runs:[/b] %d   [b]Wins:[/b] %d (%s)" % [runs, wins, _pct(wins, runs)])
	lines.append("Target for human players: ~%d %%" % int(target))
	var best := int(d.get("best", 0))
	if best > 0:
		lines.append("[b]Best run:[/b] " + ("won" if best >= 14 else "reached " + preload("res://ui/screens/summary.gd").floor_phrase(best)))
	lines.append("")
	lines.append("[b]Losses per floor[/b]")
	for f in range(3, 14):
		var n := int(d["loss_floor"].get(str(f), 0))
		if n > 0:
			lines.append("  %s: %d  %s" % [Style.floor_text(f), n, "|".repeat(mini(n, 30))])
	for pair in [["mod", "Per mod ace"]]:
		lines.append("")
		lines.append("[b]%s[/b]" % pair[1])
		for s in SUITS:
			var v: Array = d[pair[0]].get(s, [0, 0])
			lines.append("  %s  %d/%d  (%s)" % [Style.SUIT_SYM[s], int(v[0]), int(v[1]), _pct(int(v[0]), int(v[1]))])
	var v := VBoxContainer.new()
	v.add_child(Style.label("Stats", 40, Style.GOLD))
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = "\n".join(lines)
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 26)
	rt.add_theme_font_size_override("bold_font_size", 26)
	v.add_child(rt)
	var p := Style.panel(v)
	var h := HBoxContainer.new()
	var reset := Style.button("Reset", Style.RED, 24)
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(func():
		Store.reset_stats()
		p.queue_free())
	h.add_child(reset)
	var close := Style.button("Close", Style.BLACK, 24)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(p.queue_free)
	h.add_child(close)
	v.add_child(h)
	return p


static func _pct(a: int, b: int) -> String:
	return "–" if b == 0 else "%.0f %%" % (100.0 * a / b)
