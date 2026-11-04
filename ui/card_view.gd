extends Control
## A playing card drawn entirely in code: vellum face, gilt frame, vector suits, gentle motion.
## Visual transforms (lift, squash, tilt, breathing) are applied in _draw so the touch rect stays put.

signal tapped(view)
signal drag_started(view)
signal drag_moved(view, global_pos: Vector2)
signal drag_released(view, global_pos: Vector2)

const Style := preload("res://ui/style.gd")
const JOKER_TAG := {"dual": "♥♠", "innate": "1st", "double": "x2", "draw2": "+2"}

var card_id: int = -1
var rank: int = 2
var suit: String = "S"
var joker: String = ""
var virtual := false  # enemy card made by the black joker (e.g. attack 14): not an ace
var face_up := true
var selected := false
var dimmed := false
var highlight := Color(0, 0, 0, 0)  # glow colour (alpha 0 = none)
var breathing := true
var interactive := true
var crack := 0.0  # 0..1: a crack grows across the card (broken ace, beaten enemy)
## 0..1: fades the card to a dull warm grey (beaten enemy).
var grey := 0.0:
	set(v):
		grey = v
		if v > 0.0 and material == null:
			var m := ShaderMaterial.new()
			m.shader = preload("res://ui/fx/desaturate.gdshader")
			material = m
		if material != null:
			(material as ShaderMaterial).set_shader_parameter("amount", v)
var draggable := false
var dragging := false
const DRAG_START := 18.0

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
		virtual = c.from_joker
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
			if dragging:
				dragging = false
				drag_released.emit(self, event.global_position)
			elif event.position.distance_to(_press_pos) < 40:
				tapped.emit(self)
		accept_event()
	elif event is InputEventMouseMotion and _pressed and draggable:
		if not dragging and event.position.distance_to(_press_pos) > DRAG_START:
			dragging = true
			drag_started.emit(self)
		if dragging:
			drag_moved.emit(self, event.global_position)
		accept_event()


# ---------------------------------------------------------------- animations

func set_selected(v: bool) -> void:
	if v == selected:
		return
	selected = v
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "lift", -40.0 if v else 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop(0.12 if v else -0.08)


## A small squash that settles.
func pop(amount: float = 0.12) -> void:
	squash = amount * 0.45  # kept gentle: a settle, not a bounce
	var tw := create_tween()
	tw.tween_property(self, "squash", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Drop in from an offset with a bounce (visual only; position stays where the layout put it).
func land(delay: float = 0.0, from: Vector2 = Vector2(0, -220)) -> void:
	drop = from
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(self, "modulate:a", 1.0, 0.08)
	tw.parallel().tween_property(self, "drop", Vector2.ZERO, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
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
	var breathe := 0.006 * sin(_t * 1.6) if breathing else 0.0
	_sc = Vector2((1.0 + squash + breathe) * flip, 1.0 - squash + breathe)
	draw_set_transform(size / 2 + Vector2(0, lift) + drop, tilt, _sc)
	var r := Rect2(-size / 2, size)
	var a := 0.45 if dimmed else 1.0
	var rad := _radius()
	# soft shadow, a little longer when the card is lifted
	var sh := Style.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, rad)
	sh.shadow_color = Color(Style.shadow(), Style.shadow().a * a)
	sh.shadow_size = int(maxf(4.0, size.x * 0.05))
	sh.shadow_offset = Vector2(2, 5 - lift * 0.12)
	draw_style_box(sh, r)
	if highlight.a > 0.0:
		# A clear ring: soft glow of the highlight colour, then a solid 4 px border just outside the card.
		var glow := Style.box(Color(highlight, highlight.a * 0.22), Color(0, 0, 0, 0), 0, rad + 7)
		glow.shadow_color = Color(highlight, highlight.a * 0.55)
		glow.shadow_size = 12
		glow.shadow_offset = Vector2.ZERO
		draw_style_box(glow, r.grow(7))
		draw_style_box(Style.box(Color(0, 0, 0, 0), highlight, 4, rad + 6), r.grow(6))
	if not face_up:
		_draw_back(r, a)
	else:
		_draw_face(r, a)
	if crack > 0.0:
		_draw_crack(r)
	draw_set_transform(Vector2.ZERO)


func _radius() -> int:
	return int(clampf(size.x * 0.08, 5.0, 16.0))


## A thin inner frame with small lozenges at the middle of the long edges (as on the enemy card in the mock-up).
func _frame(r: Rect2, inset: float, col: Color) -> void:
	var fr := r.grow(-inset)
	var rad := maxf(2.0, _radius() - inset * 0.5)
	draw_style_box(Style.box(Color(0, 0, 0, 0), col, 1, int(rad)), fr)
	if size.x >= 100:
		for y in [fr.position.y, fr.end.y]:
			var c := Vector2(0, y)
			var d := 4.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), col)


func _draw_back(r: Rect2, a: float) -> void:
	var rad := _radius()
	var base := Color("5a2620") if not Style.night else Color("4a1f1a")
	draw_style_box(Style.box(Color(base, a), Color(Style.INK, 0.6 * a), 1, rad), r)
	var inset := maxf(4.0, size.x * 0.07)
	var inner := r.grow(-inset)
	var gold := Color(Style.GOLD.lightened(0.15), a)
	# lattice of fine gold diagonals (a woven cloth pattern), clipped to the inner frame by hand
	var step := maxf(8.0, size.x * 0.12)
	var lc := Color(gold, 0.22 * a)
	var k := -inner.size.y
	while k < inner.size.x:
		_clip_line(inner, inner.position + Vector2(k, 0), Vector2(1, 1), lc)
		_clip_line(inner, inner.position + Vector2(k + inner.size.y, 0), Vector2(-1, 1), lc)
		k += step
	_frame(r, inset, Color(gold, 0.85 * a))
	# central rosette: four petals around a lozenge
	var s := size.x * 0.22
	for i in 4:
		var ang := i * PI / 2
		var dir := Vector2(cos(ang), sin(ang))
		draw_circle(dir * s * 0.42, s * 0.3, Color(base, a))
		draw_arc(dir * s * 0.42, s * 0.3, 0, TAU, 24, gold, 1.5, true)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -s * 0.3), Vector2(s * 0.3, 0), Vector2(0, s * 0.3), Vector2(-s * 0.3, 0)]), gold)


## Draws the part of the line p + t*dir that lies inside rect r.
func _clip_line(r: Rect2, p: Vector2, dir: Vector2, col: Color) -> void:
	var t0 := -INF
	var t1 := INF
	for ax in 2:
		var lo: float = r.position[ax]
		var hi: float = r.end[ax]
		if dir[ax] == 0.0:
			if p[ax] < lo or p[ax] > hi:
				return
			continue
		var ta := (lo - p[ax]) / dir[ax]
		var tb := (hi - p[ax]) / dir[ax]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t1 > t0:
		draw_line(p + dir * t0, p + dir * t1, col, 1.0, true)


func _draw_face(r: Rect2, a: float) -> void:
	var col := Style.suit_color(suit)
	if suit == "J":
		col = Style.BLACK
	col.a = a
	var paper := Style.PAPER
	if joker != "":
		paper = paper.lerp(Style.GOLD.lightened(0.5), 0.35)
	paper.a = a
	var rad := _radius()
	draw_style_box(Style.box(paper, Color(Style.INK, 0.55 * a), 1 if size.x < 100 else 2, rad), r)
	var w := r.size.x
	if w >= 100:
		_frame(r, w * 0.055, Color(Style.GOLD, 0.55 * a))
	var f := Style.bold()
	var rt := str(rank) if virtual else Style.rank_text(rank)
	var fs := int(w * 0.27)
	var corner := r.position + Vector2(w * 0.1, fs * 0.98)
	draw_string(f, corner, rt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	var rw := f.get_string_size(rt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pip := Vector2(w * 0.1 + maxf(rw, fs * 0.5) * 0.5, fs * 1.42)
	_draw_suit(r.position + pip, fs * 0.55, suit, col)
	# bottom-right rank (upside down)
	draw_set_transform(size / 2 + Vector2(0, lift) + drop, tilt + PI, _sc)
	draw_string(f, corner, rt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_set_transform(size / 2 + Vector2(0, lift) + drop, tilt, _sc)
	# centre
	if rank >= 11 and rank <= 13:
		var big := int(w * 0.46)
		draw_string(Style.display(), Vector2(-w / 2, big * 0.28), rt, HORIZONTAL_ALIGNMENT_CENTER, w, big, col)
		_draw_suit(Vector2(0, r.size.y * 0.25), w * 0.18, suit, col)
	elif virtual:
		# The black joker's attack / shield: a smaller pip and a "Joker" caption clear of the corner value.
		_draw_suit(Vector2(0, -r.size.y * 0.06), w * 0.34, suit, col)
		draw_string(Style.display(), Vector2(-w / 2, r.size.y * 0.2), "Joker", HORIZONTAL_ALIGNMENT_CENTER, w, int(w * 0.15), col)
	else:
		_draw_suit(Vector2(0, 4), w * (0.48 if rank == 14 or suit == "J" else 0.38), suit, col)
		if suit == "J":
			draw_string(Style.display(), Vector2(-w / 2, r.size.y * 0.36), "Joker", HORIZONTAL_ALIGNMENT_CENTER, w, int(w * 0.15), col)
	if joker != "":
		var band := Rect2(r.position.x + 10, r.end.y - 36, r.size.x - 20, 26)
		draw_style_box(Style.box(Color(Style.GOLD, a), Color(Style.INK, 0.4 * a), 1, 8), band)
		draw_string(Style.font(), band.position + Vector2(0, 20), "★ " + JOKER_TAG.get(joker, joker), HORIZONTAL_ALIGNMENT_CENTER, band.size.x, 19, Color(Style.ON_DARK if Style.is_dark(Style.GOLD) else Style.INK, a))


## A jagged crack from the left edge to the right edge, with two branches. It grows along its
## length as `crack` goes 0 -> 1, thickest in the middle and tapering to hairlines at the ends.
## A pale line just below the dark one reads as the split edge of the paper.
const CRACK_MAIN := [Vector2(-0.47, -0.3), Vector2(-0.3, -0.23), Vector2(-0.17, -0.07), Vector2(-0.03, -0.11),
	Vector2(0.07, 0.07), Vector2(0.21, 0.13), Vector2(0.29, 0.3), Vector2(0.47, 0.37)]
const CRACK_BRANCHES := [[2, Vector2(-0.1, 0.1), Vector2(-0.2, 0.22)], [4, Vector2(0.19, -0.04), Vector2(0.31, -0.16)]]


func _draw_crack(r: Rect2) -> void:
	var w := maxf(1.0, size.x * 0.011)
	var dark := Color(Style.INK, 0.9 * minf(1.0, crack * 3.0))
	var light := Color(Style.PAPER.lightened(0.6), 0.85 * minf(1.0, crack * 3.0))
	var n := CRACK_MAIN.size() - 1
	var grown := crack * n
	for i in n:
		var t := clampf(grown - i, 0.0, 1.0)
		if t <= 0.0:
			break
		var a: Vector2 = (CRACK_MAIN[i] as Vector2) * r.size
		var b: Vector2 = (CRACK_MAIN[i + 1] as Vector2) * r.size
		b = a.lerp(b, t)
		var taper := 0.35 + 0.65 * sin(PI * (i + 0.5) / n)
		_crack_seg(a, b, w * taper, dark, light)
	for br in CRACK_BRANCHES:
		var from: int = br[0]
		var t := clampf(grown - from, 0.0, 1.0)
		if t <= 0.0:
			continue
		var p0: Vector2 = (CRACK_MAIN[from] as Vector2) * r.size
		var p1: Vector2 = (br[1] as Vector2) * r.size
		var p2: Vector2 = (br[2] as Vector2) * r.size
		_crack_seg(p0, p0.lerp(p1, minf(1.0, t * 2.0)), w * 0.6, dark, light)
		if t > 0.5:
			_crack_seg(p1, p1.lerp(p2, (t - 0.5) * 2.0), w * 0.35, dark, light)


func _crack_seg(a: Vector2, b: Vector2, w: float, dark: Color, light: Color) -> void:
	var off := Vector2(0.8, 1.2) * maxf(1.0, w * 0.7)
	draw_line(a + off, b + off, light, w, true)
	draw_line(a, b, dark, w, true)
	draw_circle(b, w * 0.5, dark, true, -1.0, true)  # rounds the joints


## Vector suit shapes so no glyphs are needed.
func _draw_suit(c: Vector2, s: float, p_suit: String, col: Color) -> void:
	match p_suit:
		"H":
			draw_circle(c + Vector2(-0.24, -0.12) * s, 0.27 * s, col, true, -1.0, true)
			draw_circle(c + Vector2(0.24, -0.12) * s, 0.27 * s, col, true, -1.0, true)
			_poly(PackedVector2Array([c + Vector2(-0.5, -0.04) * s, c + Vector2(0.5, -0.04) * s, c + Vector2(0, 0.5) * s]), col)
		"D":
			_poly(PackedVector2Array([c + Vector2(0, -0.5) * s, c + Vector2(0.37, 0) * s, c + Vector2(0, 0.5) * s, c + Vector2(-0.37, 0) * s]), col)
		"S":
			draw_circle(c + Vector2(-0.24, 0.1) * s, 0.25 * s, col, true, -1.0, true)
			draw_circle(c + Vector2(0.24, 0.1) * s, 0.25 * s, col, true, -1.0, true)
			_poly(PackedVector2Array([c + Vector2(-0.49, 0.08) * s, c + Vector2(0.49, 0.08) * s, c + Vector2(0, -0.52) * s]), col)
			_stem(c, s, col)
		"C":
			draw_circle(c + Vector2(0, -0.22) * s, 0.22 * s, col, true, -1.0, true)
			draw_circle(c + Vector2(-0.24, 0.08) * s, 0.22 * s, col, true, -1.0, true)
			draw_circle(c + Vector2(0.24, 0.08) * s, 0.22 * s, col, true, -1.0, true)
			draw_circle(c + Vector2(0, 0.02) * s, 0.12 * s, col, true, -1.0, true)
			_stem(c, s, col)
		_:
			var pts := PackedVector2Array()
			for i in 10:
				var ang := -PI / 2 + i * PI / 5
				var rad := 0.5 if i % 2 == 0 else 0.22
				pts.append(c + Vector2(cos(ang), sin(ang)) * rad * s)
			_poly(pts, col)


func _stem(c: Vector2, s: float, col: Color) -> void:
	_poly(PackedVector2Array([c + Vector2(-0.06, 0.12) * s, c + Vector2(0.06, 0.12) * s,
		c + Vector2(0.2, 0.5) * s, c + Vector2(-0.2, 0.5) * s]), col)


## Filled polygon with an anti-aliased rim (draw_colored_polygon alone has hard, stepped edges).
func _poly(pts: PackedVector2Array, col: Color) -> void:
	draw_colored_polygon(pts, col)
	var rim := pts.duplicate()
	rim.append(pts[0])
	draw_polyline(rim, col, 1.0, true)
