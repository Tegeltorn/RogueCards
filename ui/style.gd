extends RefCounted
## Palette, fonts and small widget factories. Everything visual is built in code (no image assets).

const BG_A := Color("1b0f2e")
const BG_B := Color("0d3b2e")
const INK := Color("1a1022")          # thick outlines
const PAPER := Color("f6efe0")        # card face
const RED := Color("e0383e")
const BLACK := Color("2b2d42")
const GOLD := Color("f4b942")
const BLUE := Color("3d8bfd")
const GREEN := Color("2ec27e")
const PANEL := Color(0.08, 0.05, 0.13, 0.97)
const WHITE := Color("fffaf0")
const MUTED := Color("b8a9c9")

const SUIT_SYM := {"H": "♥", "D": "♦", "S": "♠", "C": "♣", "J": "★"}
const SUIT_NAME := {"H": "Hearts", "D": "Diamonds", "S": "Spades", "C": "Clubs"}

static var _theme: Theme
static var _font: Font


static func font() -> Font:
	if _font == null:
		var f: FontFile = load("res://assets/fonts/Jersey10.ttf")
		var sym: FontFile = load("res://assets/fonts/SuitSymbols.ttf")
		f.fallbacks = [sym]
		# Ligatures off: pixel fonts can draw "fi" as a single odd glyph.
		var fv := FontVariation.new()
		fv.base_font = f
		var ts := TextServerManager.get_primary_interface()
		fv.opentype_features = {ts.name_to_tag("liga"): 0, ts.name_to_tag("clig"): 0, ts.name_to_tag("dlig"): 0}
		_font = fv
	return _font


static func suit_color(suit: String) -> Color:
	return RED if suit == "H" or suit == "D" else BLACK


static func rank_text(rank: int) -> String:
	return {11: "J", 12: "Q", 13: "K", 14: "A", 0: "★"}.get(rank, str(rank))


static func floor_text(f: int) -> String:
	return {11: "J", 12: "Q", 13: "K"}.get(f, str(f))


static func box(bg: Color, border: Color = INK, bw: int = 4, radius: int = 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 0
	s.shadow_offset = Vector2(0, 6)
	return s


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 28
	for kind in ["normal", "hover", "pressed", "disabled", "focus"]:
		var col := RED
		match kind:
			"hover": col = RED.lightened(0.1)
			"pressed": col = RED.darkened(0.2)
			"disabled": col = Color(0.35, 0.3, 0.4)
		if kind == "focus":
			t.set_stylebox(kind, "Button", StyleBoxEmpty.new())
			continue
		var sb := box(col)
		sb.shadow_size = 0 if kind == "pressed" else 1
		t.set_stylebox(kind, "Button", sb)
	t.set_color("font_color", "Button", WHITE)
	t.set_color("font_hover_color", "Button", WHITE)
	t.set_color("font_pressed_color", "Button", WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.75, 0.7, 0.8))
	t.set_constant("outline_size", "Button", 6)
	t.set_color("font_outline_color", "Button", INK)
	t.set_color("font_color", "Label", WHITE)
	t.set_color("font_outline_color", "Label", INK)
	t.set_constant("outline_size", "Label", 6)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, INK, 4, 18))
	t.set_stylebox("panel", "Panel", box(PANEL, INK, 4, 18))
	t.set_stylebox("normal", "LineEdit", box(Color(0.12, 0.08, 0.18), INK, 3, 10))
	t.set_stylebox("focus", "LineEdit", box(Color(0.16, 0.1, 0.24), GOLD, 3, 10))
	t.set_color("font_color", "LineEdit", WHITE)
	t.set_font_size("font_size", "LineEdit", 26)
	t.set_color("default_color", "RichTextLabel", WHITE)
	t.set_font_size("normal_font_size", "RichTextLabel", 22)
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_color("font_color", "CheckBox", WHITE)
	t.set_font_size("font_size", "CheckBox", 24)
	var sb_grab := box(GOLD, INK, 2, 6)
	t.set_stylebox("grabber", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb_grab)
	_theme = t
	return t


static func label(text: String, size: int = 28, color: Color = WHITE, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, color: Color = RED, size: int = 30) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 76)
	b.focus_mode = Control.FOCUS_NONE
	if color != RED:
		b.add_theme_stylebox_override("normal", box(color))
		b.add_theme_stylebox_override("hover", box(color.lightened(0.1)))
		b.add_theme_stylebox_override("pressed", box(color.darkened(0.2)))
	return b


## Fills the rect of `c` to its parent.
static func full(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0
	return c


static func panel(content: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_child(content)
	return p
