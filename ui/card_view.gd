extends Control
## A playing card drawn entirely in code: thick outline, vector suits, juicy motion.
## Visual transforms (lift, squash, tilt, breathing) are applied in _draw so the touch rect stays put.

signal tapped(view)

const Style := preload("res://ui/style.gd")
const JOKER_TAG := {"dual": "♥♠", "innate": "1st", "double": "x2", "draw2": "+2"}

var card_id: int = -1
var rank: int = 2
var suit: String = "S"
var joker: String = ""
var face_up := true
var selected := false
var dimmed := false
var highlight := Color(0, 0, 0, 0)  # glow colour (alpha 0 = none)
var breathing := true
var interactive := true
var crack := 0.0  # 0..1, cracked-ace effect

var lift := 0.0
var drop := Vector2.ZERO  # visual-only offset used by land(), so layouts/containers keep control of position
var squash := 0.0
var tilt := 0.0
var flip := 1.0     # horizontal scale during flip animation
var _t := randf() * 10.0
var _sc := Vector2.ONE
var _press_pos := Vector2.ZERO
var _pressed := false


func setup(c, p_size: Vector2 = Vector2(130, 182)) -> Control:
	if c != null:
		card_id = c.id
		rank = c.rank
		suit = c.suit
		joker = c.joker
	custom_minimum_size = p_size
	size = p_size
	pivot_offset = p_size / 2
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	queue_redraw()
	return self


func set_interactive(v: bool) -> void:
	interactive = v
	mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	if _pressed:
		var local := get_local_mouse_position()
		tilt = lerpf(tilt, clampf((local.x - size.x / 2) / size.x, -0.5, 0.5) * 0.25, 0.3)
	else:
		tilt = lerpf(tilt, 0.0, 0.15)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press_pos = event.position
		elif _pressed:
			_pressed = false
			if event.position.distance_to(_press_pos) < 40:
				tapped.emit(self)
		accept_event()


# ---------------------------------------------------------------- animations

func set_selected(v: bool) -> void:
	if v == selected:
		return
	selected = v
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "lift", -40.0 if v else 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop(0.12 if v else -0.08)


## Squash-and-stretch.
func pop(amount: float = 0.12) -> void:
	squash = amount
	var tw := create_tween()
	tw.tween_property(self, "squash", 0.0, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Drop in from an offset with a bounce (visual only; position stays where the layout put it).
func land(delay: float = 0.0, from: Vector2 = Vector2(0, -220)) -> void:
	drop = from
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(self, "modulate:a", 1.0, 0.08)
	tw.parallel().tween_property(self, "drop", Vector2.ZERO, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(pop.bind(0.14))


func flip_to(p_face_up: bool, dur: float = 0.25) -> void:
	var tw := create_tween()
	tw.tween_property(self, "flip", 0.0, dur / 2).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): face_up = p_face_up)
	tw.tween_property(self, "flip", 1.0, dur / 2).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(pop.bind(0.1))


func shatter() -> Tween:
	var tw := create_tween()
	tw.tween_property(self, "crack", 1.0, 0.25)
	tw.parallel().tween_property(self, "squash", 0.2, 0.1)
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	return tw


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var breathe := 0.012 * sin(_t * 2.2) if breathing else 0.0
	_sc = Vector2((1.0 + squash + breathe) * flip, 1.0 - squash + breathe)
	draw_set_transform(size / 2 + Vector2(0, lift) + drop, tilt, _sc)
	var r := Rect2(-size / 2, size)
	var a := 0.45 if dimmed else 1.0
	# shadow
	var sh := Style.box(Color(0, 0, 0, 0.35 * a), Color(0, 0, 0, 0), 0, 14)
	draw_style_box(sh, Rect2(r.position + Vector2(4, 8 - lift * 0.15), r.size))
	if highlight.a > 0.0:
		var g := Style.box(Color(0, 0, 0, 0), highlight, 6, 18)
		draw_style_box(g, r.grow(7))
	if not face_up:
		_draw_back(r, a)
	else:
		_draw_face(r, a)
	if crack > 0.0:
		_draw_crack(r)
	draw_set_transform(Vector2.ZERO)


func _draw_back(r: Rect2, a: float) -> void:
	draw_style_box(Style.box(Color("4b1d6b", a), Color(Style.INK, a), 5, 14), r)
	var inner := r.grow(-14)
	draw_style_box(Style.box(Color("6a2c91", a), Color(Style.GOLD, a * 0.8), 3, 8), inner)
	var step := 22.0
	var x := inner.position.x
	while x < inner.end.x:
		draw_line(Vector2(x, inner.position.y + 4), Vector2(x, inner.end.y - 4), Color(1, 1, 1, 0.07 * a), 2)
		x += step
	_draw_suit(Vector2.ZERO, r.size.x * 0.35, "J", Color(Style.GOLD, a))


func _draw_face(r: Rect2, a: float) -> void:
	var col := Style.suit_color(suit)
	if suit == "J":
		col = Style.BLACK
	col.a = a
	var paper := Style.PAPER
	if joker != "":
		paper = Color("fff3c4")
	paper.a = a
	draw_style_box(Style.box(paper, Color(Style.INK, a), 5, 14), r)
	var f := Style.font()
	var w := r.size.x
	var rt := Style.rank_text(rank)
	var fs := int(w * 0.26)
	draw_string(f, r.position + Vector2(10, fs + 4), rt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	_draw_suit(r.position + Vector2(10 + fs * 0.32, fs * 1.55), fs * 0.6, suit, col)
	# bottom-right rank (upside down)
	draw_set_transform(size / 2 + Vector2(0, lift) + drop, tilt + PI, _sc)
	draw_string(f, r.position + Vector2(10, fs + 4), rt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_set_transform(size / 2 + Vector2(0, lift) + drop, tilt, _sc)
	# centre
	if rank >= 11 and rank <= 13:
		var big := int(w * 0.5)
		draw_string(f, Vector2(-w / 2, big * 0.3), rt, HORIZONTAL_ALIGNMENT_CENTER, w, big, col)
		_draw_suit(Vector2(0, r.size.y * 0.27), w * 0.2, suit, col)
	else:
		_draw_suit(Vector2(0, 4), w * (0.5 if rank == 14 or suit == "J" else 0.4), suit, col)
		if suit == "J":
			draw_string(f, Vector2(-w / 2, r.size.y * 0.38), "JOKER", HORIZONTAL_ALIGNMENT_CENTER, w, int(w * 0.14), col)
	if joker != "":
		var band := Rect2(r.position.x + 8, r.end.y - 38, r.size.x - 16, 28)
		draw_style_box(Style.box(Color(Style.GOLD, a), Color(Style.INK, a), 3, 8), band)
		draw_string(f, band.position + Vector2(0, 22), "★ " + JOKER_TAG.get(joker, joker), HORIZONTAL_ALIGNMENT_CENTER, band.size.x, 20, Color(Style.INK, a))


func _draw_crack(r: Rect2) -> void:
	var c := Color(Style.INK, crack)
	var pts := [Vector2(-0.1, -0.5), Vector2(0.05, -0.2), Vector2(-0.12, 0.05), Vector2(0.1, 0.25), Vector2(-0.02, 0.5)]
	for i in pts.size() - 1:
		draw_line(pts[i] * r.size, pts[i + 1] * r.size, c, 5)
	draw_line(Vector2(0.05, -0.2) * r.size, Vector2(0.4, -0.3) * r.size, c, 4)
	draw_line(Vector2(-0.12, 0.05) * r.size, Vector2(-0.45, 0.15) * r.size, c, 4)


## Vector suit shapes so no glyphs are needed.
func _draw_suit(c: Vector2, s: float, p_suit: String, col: Color) -> void:
	match p_suit:
		"H":
			draw_circle(c + Vector2(-0.24, -0.12) * s, 0.27 * s, col)
			draw_circle(c + Vector2(0.24, -0.12) * s, 0.27 * s, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.5, -0.04) * s, c + Vector2(0.5, -0.04) * s, c + Vector2(0, 0.5) * s]), col)
		"D":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.5) * s, c + Vector2(0.37, 0) * s, c + Vector2(0, 0.5) * s, c + Vector2(-0.37, 0) * s]), col)
		"S":
			draw_circle(c + Vector2(-0.24, 0.1) * s, 0.25 * s, col)
			draw_circle(c + Vector2(0.24, 0.1) * s, 0.25 * s, col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-0.49, 0.08) * s, c + Vector2(0.49, 0.08) * s, c + Vector2(0, -0.52) * s]), col)
			_stem(c, s, col)
		"C":
			draw_circle(c + Vector2(0, -0.22) * s, 0.22 * s, col)
			draw_circle(c + Vector2(-0.24, 0.08) * s, 0.22 * s, col)
			draw_circle(c + Vector2(0.24, 0.08) * s, 0.22 * s, col)
			draw_circle(c + Vector2(0, 0.02) * s, 0.12 * s, col)
			_stem(c, s, col)
		_:
			var pts := PackedVector2Array()
			for i in 10:
				var ang := -PI / 2 + i * PI / 5
				var rad := 0.5 if i % 2 == 0 else 0.22
				pts.append(c + Vector2(cos(ang), sin(ang)) * rad * s)
			draw_colored_polygon(pts, col)


func _stem(c: Vector2, s: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(-0.06, 0.12) * s, c + Vector2(0.06, 0.12) * s,
		c + Vector2(0.2, 0.5) * s, c + Vector2(-0.2, 0.5) * s]), col)
