extends ColorRect
## Drifting smoke over the page.
##
## "fluid" mode: a small, real fluid simulation (semi-Lagrangian advection plus a few pressure
## iterations, like "stable fluids") on a coarse grid, run at 30 Hz on the CPU. The density is
## uploaded as a tiny texture and the shader adds fine wisps, so the grid never shows.
## Dragging a finger and card effects (puff()) stir it.
## "simple" mode: no simulation at all, the shader draws drifting flow noise (cheapest).

const NX := 36
const NY := 64
const STEP := 1.0 / 30.0
const JACOBI := 4

var simulated := true
var _u := PackedFloat32Array()
var _v := PackedFloat32Array()
var _d := PackedFloat32Array()
var _u0 := PackedFloat32Array()
var _v0 := PackedFloat32Array()
var _d0 := PackedFloat32Array()
var _p := PackedFloat32Array()
var _div := PackedFloat32Array()
var _bytes := PackedByteArray()
var _sx := PackedFloat32Array()
var _cx := PackedFloat32Array()
var _sy := PackedFloat32Array()
var _cy := PackedFloat32Array()
var _img: Image
var _tex: ImageTexture
var _acc := 0.0
var _t := 0.0
var _emit_phase := randf() * 10.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://ui/fx/smoke.gdshader")
	material = m
	var n := NX * NY
	for arr in [_u, _v, _d, _u0, _v0, _d0, _p, _div]:
		arr.resize(n)
		arr.fill(0.0)
	for arr in [_sx, _cx]:
		arr.resize(NX)
	for arr in [_sy, _cy]:
		arr.resize(NY)
	_bytes.resize(n)
	_bytes.fill(0)
	_img = Image.create_from_data(NX, NY, false, Image.FORMAT_L8, _bytes)
	_tex = ImageTexture.create_from_image(_img)
	m.set_shader_parameter("density", _tex)
	# Start with some smoke already on the page.
	for k in 150:
		_emit(STEP)
		_step(STEP)
	set_simulated(simulated)


func set_simulated(on: bool) -> void:
	simulated = on
	(material as ShaderMaterial).set_shader_parameter("simulated", on)
	set_process(on)


func set_colors(smoke: Color, shade: Color, strength: float) -> void:
	var m := material as ShaderMaterial
	m.set_shader_parameter("smoke_col", smoke)
	m.set_shader_parameter("shade_col", shade)
	m.set_shader_parameter("strength", strength)


func _process(delta: float) -> void:
	_acc = minf(_acc + delta, STEP * 2.0)
	if _acc >= STEP:
		_acc -= STEP
		_emit(STEP)
		_step(STEP)
		_upload()


func _input(event: InputEvent) -> void:
	if not simulated or size.x <= 0.0:
		return
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		stir(event.position - global_position, event.relative)


## Pushes the smoke along a drag (screen position and movement in pixels).
func stir(pos: Vector2, rel: Vector2) -> void:
	var cx := pos.x / size.x * NX
	var cy := pos.y / size.y * NY
	var f := rel / size * Vector2(NX, NY) * 9.0
	_splat(cx, cy, 2.6, f.x, f.y, 0.0)


## A soft outward puff (card effects): pushes smoke away from `pos` and adds a little.
func puff(pos: Vector2, strength: float = 1.0) -> void:
	if not simulated or size.x <= 0.0:
		return
	var cx := pos.x / size.x * NX
	var cy := pos.y / size.y * NY
	var r := 4.0
	for y in range(maxi(1, int(cy - r)), mini(NY - 1, int(cy + r) + 1)):
		for x in range(maxi(1, int(cx - r)), mini(NX - 1, int(cx + r) + 1)):
			var dx := x - cx
			var dy := y - cy
			var dist := sqrt(dx * dx + dy * dy)
			if dist > r or dist < 0.01:
				continue
			var w := (1.0 - dist / r) * strength
			var i := x + y * NX
			_u[i] += dx / dist * w * 7.0
			_v[i] += dy / dist * w * 7.0
			_d[i] = minf(1.2, _d[i] + w * 0.25)


func _splat(cx: float, cy: float, r: float, fx: float, fy: float, dens: float) -> void:
	for y in range(maxi(1, int(cy - r)), mini(NY - 1, int(cy + r) + 1)):
		for x in range(maxi(1, int(cx - r)), mini(NX - 1, int(cx + r) + 1)):
			var dx := x - cx
			var dy := y - cy
			var w := 1.0 - (dx * dx + dy * dy) / (r * r)
			if w <= 0.0:
				continue
			var i := x + y * NX
			_u[i] += fx * w
			_v[i] += fy * w
			_d[i] = minf(1.2, _d[i] + dens * w)


## Incense-like sources: slow wisps rising from the lower corners and an occasional drifting one.
func _emit(dt: float) -> void:
	_t += dt
	var ph := _t * 0.35 + _emit_phase
	_splat(5.0 + sin(ph) * 2.0, NY - 7.0, 2.2, 0.8 + sin(ph * 1.3) * 0.6, -3.0, 0.2)
	_splat(NX - 6.0 + sin(ph * 0.8 + 2.0) * 2.0, NY - 6.0, 2.2, -0.8 + cos(ph * 1.1) * 0.6, -2.8, 0.18)
	# a wandering source across the middle of the page
	var wx := NX * (0.5 + 0.38 * sin(_t * 0.07 + _emit_phase))
	var wy := NY * (0.55 + 0.3 * sin(_t * 0.05 + 1.7))
	_splat(wx, wy, 2.0, cos(_t * 0.3) * 0.8, -0.5, 0.09)


func _step(dt: float) -> void:
	# gentle swirling wind from an analytic stream function (divergence-free by construction)
	var a := 0.31
	var b := 0.23
	var p := _t * 0.21
	var q := _t * 0.17
	for x in NX:
		_sx[x] = sin(a * x + p)
		_cx[x] = cos(a * x + p)
	for y in NY:
		_sy[y] = sin(b * y - q)
		_cy[y] = cos(b * y - q)
	var wu := -b * 6.0 * 1.6 * dt
	var wv := -a * 6.0 * 1.6 * dt
	var buoy := 3.0 * dt
	var damp := 0.985
	var fade := 0.995
	var u := _u
	var v := _v
	var d := _d
	var nu := _u0
	var nv := _v0
	var nd := _d0
	# advect velocity and density (semi-Lagrangian, bilinear) and add the forces, in one pass
	for y in range(1, NY - 1):
		var syy: float = _sy[y]
		var cyy: float = _cy[y]
		for x in range(1, NX - 1):
			var i := x + y * NX
			var px := clampf(x - u[i] * 0.1, 0.5, NX - 1.5)
			var py := clampf(y - v[i] * 0.1, 0.5, NY - 1.5)
			var x0 := int(px)
			var y0 := int(py)
			var fx := px - x0
			var fy := py - y0
			var j := x0 + y0 * NX
			var w00 := (1.0 - fx) * (1.0 - fy)
			var w10 := fx * (1.0 - fy)
			var w01 := (1.0 - fx) * fy
			var w11 := fx * fy
			var dd := (d[j] * w00 + d[j + 1] * w10 + d[j + NX] * w01 + d[j + NX + 1] * w11) * fade
			nd[i] = dd
			nu[i] = (u[j] * w00 + u[j + 1] * w10 + u[j + NX] * w01 + u[j + NX + 1] * w11) * damp + wu * _sx[x] * syy
			nv[i] = (v[j] * w00 + v[j + 1] * w10 + v[j + NX] * w01 + v[j + NX + 1] * w11) * damp + wv * _cx[x] * cyy - dd * buoy
	# swap buffers
	_u = nu
	_v = nv
	_d = nd
	_u0 = u
	_v0 = v
	_d0 = d
	u = nu
	v = nv
	# make it incompressible (this is what turns pushes into curls)
	for y in range(1, NY - 1):
		for x in range(1, NX - 1):
			var i := x + y * NX
			_div[i] = -0.5 * (u[i + 1] - u[i - 1] + v[i + NX] - v[i - NX])
			_p[i] = _div[i] * 0.25
	for k in JACOBI - 1:
		for y in range(1, NY - 1):
			for x in range(1, NX - 1):
				var i := x + y * NX
				_p[i] = (_div[i] + _p[i - 1] + _p[i + 1] + _p[i - NX] + _p[i + NX]) * 0.25
	for y in range(1, NY - 1):
		for x in range(1, NX - 1):
			var i := x + y * NX
			u[i] -= 0.5 * (_p[i + 1] - _p[i - 1])
			v[i] -= 0.5 * (_p[i + NX] - _p[i - NX])
	# smoke that reaches the top edge drifts off the page
	for x in NX:
		_d[x] *= 0.5
		_d[x + NX] *= 0.8


func _upload() -> void:
	var n := NX * NY
	for i in n:
		_bytes[i] = int(clampf(_d[i], 0.0, 1.0) * 255.0)
	_img.set_data(NX, NY, false, Image.FORMAT_L8, _bytes)
	_tex.update(_img)
