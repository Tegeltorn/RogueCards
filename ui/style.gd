extends RefCounted
## Palette, fonts and small widget factories. Everything visual is built in code (no image assets).
##
## Look: an illuminated manuscript. Vellum, iron-gall ink, madder red, moss green and ochre gold.
## There is no saturated blue anywhere, so the screen is easy on the eyes (low blue light).
## Two palettes: "day" (vellum) and "night" (candlelit). Call set_night() and rebuild screens to switch.

# The palette is static vars (not consts) so night mode can swap it. Names are semantic:
static var BG_A: Color    # page background
static var BG_B: Color    # background mottling / edges
static var INK: Color     # outlines and lines
static var PAPER: Color   # card face
static var RED: Color     # red suits, danger, primary buttons
static var BLACK: Color   # black suits, secondary buttons
static var GOLD: Color    # highlights, headings
static var BLUE: Color    # shields and info (a blue-free verdigris)
static var GREEN: Color   # "this counts" and confirmations
static var PLUM: Color    # sacrifices, debug and other rare actions
static var STEEL: Color   # sword blade
static var PANEL: Color   # overlay panels
static var WHITE: Color   # main text colour on the background
static var MUTED: Color   # secondary text
static var ON_DARK: Color # text on dark (coloured) buttons
static var night := false

const SUIT_SYM := {"H": "♥", "D": "♦", "S": "♠", "C": "♣", "J": "★"}
const SUIT_NAME := {"H": "Hearts", "D": "Diamonds", "S": "Spades", "C": "Clubs"}

static var _theme: Theme
static var _font: Font
static var _bold: Font
static var _display: Font


static func _static_init() -> void:
	set_night(false)


static func set_night(on: bool) -> void:
	night = on
	_theme = null
	if not on:
		BG_A = Color("efe4cb")
		BG_B = Color("dfcda8")
		INK = Color("3b2a1d")
		PAPER = Color("f8f0de")
		RED = Color("9a2f24")
		BLACK = Color("2e2721")
		GOLD = Color("9c6b1c")
		BLUE = Color("3f6b5f")
		GREEN = Color("4d6b2f")
		PLUM = Color("6e3550")
		STEEL = Color("8a8173")
		PANEL = Color("f4ead2")
		WHITE = Color("33261a")
		MUTED = Color("7a6650")
		ON_DARK = Color("f6e9c8")
	else:
		BG_A = Color("1f1612")
		BG_B = Color("120c09")
		INK = Color("140d09")
		PAPER = Color("e3d3b2")
		RED = Color("a2392c")
		BLACK = Color("2b231d")
		GOLD = Color("c99a4a")
		BLUE = Color("7f9c84")
		GREEN = Color("8a9f55")
		PLUM = Color("8a4a66")
		STEEL = Color("b8ab95")
		PANEL = Color("2a1f18")
		WHITE = Color("e6d5b4")
		MUTED = Color("a08a6c")
		ON_DARK = Color("f0dfbc")


## "#rrggbb" for bbcode.
static func hex(c: Color) -> String:
	return "#" + c.to_html(false)


static func _ts_tag(name: String) -> int:
	return TextServerManager.get_primary_interface().name_to_tag(name)


static func _base(path: String) -> FontFile:
	var f: FontFile = load(path)
	var sym: FontFile = load("res://assets/fonts/SuitSymbols.ttf")
	f.fallbacks = [sym]
	# No system fonts on the web: turn system fallback off so desktop runs show missing glyphs too.
	f.allow_system_fallback = false
	sym.allow_system_fallback = false
	return f


static func _garamond(weight: int) -> Font:
	var fv := FontVariation.new()
	fv.base_font = _base("res://assets/fonts/EBGaramond.ttf")
	fv.variation_opentype = {_ts_tag("wght"): weight}
	# Lining figures: numbers line up with capitals, easier to read at a glance.
	fv.opentype_features = {_ts_tag("lnum"): 1}
	return fv


## Body text: EB Garamond, slightly heavier than book weight so it reads well on a phone.
static func font() -> Font:
	if _font == null:
		_font = _garamond(560)
	return _font


## Card ranks and big numbers.
static func bold() -> Font:
	if _bold == null:
		_bold = _garamond(720)
	return _bold


## Titles: Uncial Antiqua.
static func display() -> Font:
	if _display == null:
		var fv := FontVariation.new()
		fv.base_font = _base("res://assets/fonts/UncialAntiqua.ttf")
		_display = fv
	return _display


static func suit_color(suit: String) -> Color:
	return RED if suit == "H" or suit == "D" else BLACK


static func rank_text(rank: int) -> String:
	return {11: "J", 12: "Q", 13: "K", 14: "A", 0: "★"}.get(rank, str(rank))


static func floor_text(f: int) -> String:
	return {11: "J", 12: "Q", 13: "K"}.get(f, str(f))


static func shadow() -> Color:
	return Color(0, 0, 0, 0.45) if night else Color(0.23, 0.15, 0.08, 0.18)


static func box(bg: Color, border: Color = INK, bw: int = 2, radius: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.anti_aliasing = true
	s.shadow_color = shadow()
	s.shadow_size = 0
	s.shadow_offset = Vector2(0, 4)
	return s


static func is_dark(c: Color) -> bool:
	return c.get_luminance() < 0.42


## Secondary buttons (passed Style.BLACK) are quiet: parchment with an ink hairline.
static func _button_box(col: Color, kind: String) -> StyleBoxFlat:
	var secondary := col == BLACK
	var bg := col
	var border := GOLD if not secondary else Color(INK, 0.35 if not night else 0.9)
	if secondary:
		bg = PANEL.darkened(0.03) if not night else Color("3a2b21")
	match kind:
		"hover": bg = bg.lightened(0.06)
		"pressed": bg = bg.darkened(0.12)
		"disabled":
			bg = Color(bg.lerp(PANEL, 0.7), 0.8)
			border = Color(INK, 0.15)
	var sb := box(bg, border, 2, 12)
	sb.shadow_size = 0 if kind == "pressed" or kind == "disabled" else 3
	sb.shadow_offset = Vector2(0, 3)
	return sb


static func _button_text(col: Color) -> Color:
	if col == BLACK:
		return WHITE
	return ON_DARK if is_dark(col) else INK


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 28
	for kind in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(kind, "Button", _button_box(RED, kind))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", ON_DARK)
	t.set_color("font_hover_color", "Button", ON_DARK)
	t.set_color("font_pressed_color", "Button", ON_DARK)
	t.set_color("font_disabled_color", "Button", Color(MUTED, 0.8))
	t.set_constant("outline_size", "Button", 0)
	t.set_color("font_color", "Label", WHITE)
	# Labels that ask for an outline get a soft halo in the page colour (keeps text legible over cards).
	t.set_color("font_outline_color", "Label", BG_A)
	t.set_constant("outline_size", "Label", 0)
	var pb := box(PANEL, Color(GOLD, 0.65), 2, 16)
	pb.shadow_size = 18
	pb.shadow_offset = Vector2(0, 8)
	pb.content_margin_left = 22
	pb.content_margin_right = 22
	pb.content_margin_top = 16
	pb.content_margin_bottom = 16
	t.set_stylebox("panel", "PanelContainer", pb)
	t.set_stylebox("panel", "Panel", pb)
	var field := PANEL.darkened(0.05) if not night else PANEL.lightened(0.05)
	t.set_stylebox("normal", "LineEdit", box(field, Color(INK, 0.35), 2, 10))
	t.set_stylebox("focus", "LineEdit", box(field, GOLD, 2, 10))
	t.set_color("font_color", "LineEdit", WHITE)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.8))
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_font_size("font_size", "LineEdit", 26)
	t.set_color("default_color", "RichTextLabel", WHITE)
	t.set_font_size("normal_font_size", "RichTextLabel", 22)
	t.set_font("bold_font", "RichTextLabel", bold())
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	for cls in ["CheckBox", "OptionButton"]:
		t.set_color("font_color", cls, WHITE)
		t.set_color("font_hover_color", cls, WHITE)
		t.set_color("font_pressed_color", cls, WHITE)
		t.set_color("font_hover_pressed_color", cls, WHITE)
	t.set_font_size("font_size", "CheckBox", 24)
	for kind in ["normal", "hover", "pressed", "hover_pressed"]:
		var cb := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 10)
		if kind != "normal":
			cb.bg_color = Color(GOLD, 0.12)
		t.set_stylebox(kind, "CheckBox", cb)
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	for kind in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(kind, "OptionButton", _button_box(BLACK, kind))
	var sb_grab := box(Color(GOLD, 0.7), Color(0, 0, 0, 0), 0, 6)
	t.set_stylebox("grabber", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb_grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", sb_grab)
	t.set_stylebox("scroll", "VScrollBar", box(Color(INK, 0.08), Color(0, 0, 0, 0), 0, 6))
	t.set_stylebox("panel", "PopupMenu", box(PANEL, Color(GOLD, 0.65), 2, 10))
	t.set_color("font_color", "PopupMenu", WHITE)
	t.set_color("font_hover_color", "PopupMenu", GOLD)
	_theme = t
	return t


## A small hand-drawn checkbox (a gold square, filled with a ♦-like lozenge when on).
static func _check_icon(on: bool) -> ImageTexture:
	var n := 30
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var edge := x < 3 or y < 3 or x >= n - 3 or y >= n - 3
			if edge:
				img.set_pixel(x, y, GOLD)
			elif on and absf(x - n / 2.0 + 0.5) + absf(y - n / 2.0 + 0.5) < 9.0:
				img.set_pixel(x, y, RED)
	return ImageTexture.create_from_image(img)


## Labels of 38 px and up are titles and use the display font.
static func label(text: String, size: int = 28, color: Color = WHITE, align: int = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if size >= 38:
		l.add_theme_font_override("font", display())
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
		for kind in ["normal", "hover", "pressed", "disabled"]:
			b.add_theme_stylebox_override(kind, _button_box(color, kind))
		var tc := _button_text(color)
		for k in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(k, tc)
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


## A thin rule with a lozenge in the middle, like a manuscript section break.
class Ornament:
	extends Control
	var col := Color.BLACK

	func _draw() -> void:
		var c := size / 2
		var half := minf(size.x * 0.42, 260.0)
		draw_line(c - Vector2(half, 0), c - Vector2(14, 0), Color(col, 0.6), 1.5, true)
		draw_line(c + Vector2(14, 0), c + Vector2(half, 0), Color(col, 0.6), 1.5, true)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(8, 0), c + Vector2(0, 7), c + Vector2(-8, 0)]), col)
		draw_circle(c - Vector2(half, 0), 2.5, col)
		draw_circle(c + Vector2(half, 0), 2.5, col)


static func ornament(width: float = 0.0) -> Control:
	var o := Ornament.new()
	o.col = GOLD
	o.custom_minimum_size = Vector2(width, 18)
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return o
