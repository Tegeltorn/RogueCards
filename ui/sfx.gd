extends Node
## Sound effects, synthesized in code (no audio files, nothing to license).
##
## Palette to match the manuscript look. Everything done with a card sounds like paper (picking up,
## sliding, laying down, flipping, tearing); buttons and good news use plucked harp strings
## (Karplus-Strong); blows use a wooden shield, a frame drum and a hand bell. D dorian, short room reverb. Sounds are built one per frame after start-up so loading stays smooth;
## one that is needed before it is built is built on the spot.

const RATE := 24000

# D dorian
const D3 := 146.83
const A3 := 220.0
const C4 := 261.63
const D4 := 293.66
const E4 := 329.63
const F4 := 349.23
const G4 := 392.0
const A4 := 440.0
const C5 := 523.25
const D5 := 587.33
const F5 := 698.46
const A5 := 880.0
const D6 := 1174.66

## Peak level of each sound (0..1), so plucks, knocks and bells sit at a balanced loudness.
const LEVEL := {"select": 0.3, "card": 0.32, "draw": 0.35, "play": 0.5, "flip": 0.28, "block": 0.6, "hit": 0.75,
	"defeat": 0.45, "exact": 0.5, "reward": 0.45, "crack": 0.55, "win": 0.6, "lose": 0.6}

var enabled := true
var _streams: Dictionary = {}
var _pending: Array = []
var _players: Array = []
var _next := 0


func _ready() -> void:
	_pending = ["select", "card", "draw", "play", "flip", "block", "hit", "defeat", "exact", "reward", "crack", "win", "lose"]
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func _process(_delta: float) -> void:
	if _pending.is_empty():
		set_process(false)
		return
	var name: String = _pending.pop_front()
	if not _streams.has(name):
		_streams[name] = _build(name)


func play(name: String, pitch: float = 1.0) -> void:
	if not enabled:
		return
	if not _streams.has(name):
		if not _pending.has(name):
			return
		_pending.erase(name)
		_streams[name] = _build(name)
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.pitch_scale = pitch * randf_range(0.98, 1.02)
	p.play()


# ---------------------------------------------------------------- the sounds

func _build(name: String) -> AudioStreamWAV:
	var b := PackedFloat32Array()
	match name:
		"select":  # buttons: a light harp pluck
			b = _buf(0.45)
			_add(b, _pluck(D5, 0.45, 0.75, 0.9965), 0.0, 0.3)
		"card":  # a card picked up / tapped: a crisp paper flick
			b = _buf(0.12)
			_add(b, _rustle(0.035, 0.85, 0.002), 0.0, 0.7)
			_add(b, _rustle(0.09, 0.45, 0.015), 0.01, 0.35)
		"draw":  # a card slid off the deck
			b = _buf(0.16)
			_add(b, _rustle(0.14, 0.35, 0.02), 0.0, 0.5)
		"play":  # a card slid and slapped down on the table
			b = _buf(0.3)
			_add(b, _rustle(0.09, 0.45, 0.02), 0.0, 0.4)
			_add(b, _thud(0.09), 0.08, 0.8)
			_add(b, _rustle(0.03, 0.8, 0.001), 0.08, 0.35)
		"flip":  # a parchment flick
			b = _buf(0.1)
			_add(b, _rustle(0.06, 0.7, 0.004), 0.0, 0.35)
			_add(b, _knock(620.0, 0.03), 0.0, 0.1)
		"block":  # a wooden shield takes the blow
			b = _buf(0.5)
			_add(b, _knock(120.0, 0.25), 0.0, 0.6)
			_add(b, _rustle(0.05, 0.3, 0.002), 0.0, 0.2)
			_add(b, _pluck(A3, 0.45, 0.4, 0.995), 0.02, 0.22)
		"hit":  # a frame-drum blow and a sour low string
			b = _buf(0.75)
			_add(b, _drum(115.0, 52.0, 0.5), 0.0, 0.75)
			_add(b, _pluck(D3, 0.7, 0.5, 0.996), 0.03, 0.22)
			_add(b, _pluck(D3 * 1.06, 0.7, 0.5, 0.996), 0.04, 0.16)
		"defeat":  # enemy beaten: a rising fifth
			b = _buf(0.7)
			_add(b, _pluck(A4, 0.6, 0.6, 0.997), 0.0, 0.26)
			_add(b, _pluck(D5, 0.6, 0.6, 0.997), 0.07, 0.26)
		"exact":  # a hand bell
			b = _buf(1.4)
			_add(b, _bell(A5, 1.3), 0.0, 0.26)
			_add(b, _pluck(A4, 0.8, 0.6, 0.997), 0.0, 0.18)
		"reward":  # harp arpeggio
			b = _buf(1.2)
			var notes := [D4, F4, A4, D5]
			for i in notes.size():
				_add(b, _pluck(notes[i], 0.9, 0.65, 0.998), i * 0.085, 0.24)
		"crack":  # an ace torn in two: a paper tear
			b = _buf(0.45)
			_add(b, _tear(0.38), 0.0, 0.8)
		"win":  # a short modal fanfare over a drone
			b = _buf(2.6)
			_add(b, _pluck(D3, 2.2, 0.4, 0.9992), 0.0, 0.2)
			_add(b, _pluck(A3, 2.2, 0.4, 0.9992), 0.0, 0.16)
			var tune := [[D4, 0.0], [A4, 0.16], [D5, 0.32], [C5, 0.56], [D5, 0.72], [F5, 0.88], [D5, 1.12]]
			for n in tune:
				_add(b, _pluck(n[0], 1.0, 0.7, 0.998), n[1], 0.24)
			_add(b, _bell(D6, 1.3), 1.12, 0.14)
			_add(b, _drum(140.0, 90.0, 0.3), 1.12, 0.3)
		"lose":  # falling line and a low drum
			b = _buf(2.0)
			var fall := [[D4, 0.0], [C4, 0.22], [A3, 0.44], [D3, 0.75]]
			for n in fall:
				_add(b, _pluck(n[0], 1.1, 0.4, 0.9975), n[1], 0.26)
			_add(b, _drum(90.0, 45.0, 0.8), 0.75, 0.5)
		_:
			b = _buf(0.05)
	return _wav(_reverb(b, 0.16), float(LEVEL.get(name, 0.5)))


# ---------------------------------------------------------------- building blocks

func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(dur * RATE))
	b.fill(0.0)
	return b


func _add(dst: PackedFloat32Array, src: PackedFloat32Array, at: float, gain: float) -> void:
	var o := int(at * RATE)
	var n := mini(src.size(), dst.size() - o)
	for i in n:
		dst[o + i] += src[i] * gain


## Karplus-Strong plucked string. `bright` 0..1 shapes the pluck noise, `decay` the sustain.
func _pluck(freq: float, dur: float, bright: float, decay: float) -> PackedFloat32Array:
	var out := _buf(dur)
	var period := maxi(2, int(RATE / freq))
	var ring := PackedFloat32Array()
	ring.resize(period)
	var lp := 0.0
	for i in period:
		lp += (randf() * 2.0 - 1.0 - lp) * bright
		ring[i] = lp
	var idx := 0
	var n := out.size()
	var fade_from := n - int(0.03 * RATE)
	for i in n:
		var nxt := (idx + 1) % period
		var v := ring[idx]
		ring[idx] = (v + ring[nxt]) * 0.5 * decay
		var g := 1.0 if i < fade_from else float(n - i) / float(n - fade_from)
		out[i] = v * g
		idx = nxt
	return out


## Band-limited noise burst (paper, cloth). `tone` 0..1: dark to bright. `attack` in seconds.
func _rustle(dur: float, tone: float, attack: float) -> PackedFloat32Array:
	var out := _buf(dur)
	var lo := 0.0
	var lo2 := 0.0
	var n := out.size()
	var a := maxi(1, int(attack * RATE))
	for i in n:
		var w := randf() * 2.0 - 1.0
		lo += (w - lo) * (0.15 + tone * 0.6)
		lo2 += (lo - lo2) * 0.04
		var env := float(i) / a if i < a else pow(1.0 - float(i - a) / maxf(1.0, n - a), 2.0)
		out[i] = (lo - lo2) * env * 1.6
	return out


## Paper landing on wood: a dull, heavily filtered noise thump.
func _thud(dur: float) -> PackedFloat32Array:
	var out := _buf(dur)
	var lo := 0.0
	var lo2 := 0.0
	for i in out.size():
		var t := float(i) / RATE
		lo += (randf() * 2.0 - 1.0 - lo) * 0.12
		lo2 += (lo - lo2) * 0.2
		out[i] = lo2 * 3.0 * exp(-t * 45.0) * minf(1.0, t * 2000.0)
	return out


## Paper tear: many tiny fibre snaps, getting denser, over a thin rustle.
func _tear(dur: float) -> PackedFloat32Array:
	var out := _buf(dur)
	var n := out.size()
	var hi := 0.0
	var lo := 0.0
	for i in n:
		var x := float(i) / n
		var w := randf() * 2.0 - 1.0
		hi += (w - hi) * 0.7
		lo += (hi - lo) * 0.05
		# snaps: random spikes whose rate rises through the tear, then stops abruptly
		var rate := 0.002 + 0.03 * x
		var snap := (randf() * 2.0 - 1.0) * 2.5 if randf() < rate else 0.0
		var env := minf(1.0, x * 12.0) * (1.0 if x < 0.85 else (1.0 - x) / 0.15)
		out[i] = ((hi - lo) * (0.35 + 0.4 * x) + snap) * env
	return out


## Wooden knock: a damped low partial and a fast upper one, plus a click.
func _knock(freq: float, dur: float) -> PackedFloat32Array:
	var out := _buf(dur)
	for i in out.size():
		var t := float(i) / RATE
		var v := sin(TAU * freq * t) * exp(-t * 28.0) + 0.5 * sin(TAU * freq * 2.71 * t) * exp(-t * 60.0)
		if i < 60:
			v += (randf() * 2.0 - 1.0) * (1.0 - i / 60.0) * 0.6
		out[i] = v
	return out


## Frame drum: falling pitch and a soft skin noise.
func _drum(f0: float, f1: float, dur: float) -> PackedFloat32Array:
	var out := _buf(dur)
	var ph := 0.0
	var lo := 0.0
	for i in out.size():
		var t := float(i) / RATE
		var f := f1 + (f0 - f1) * exp(-t * 18.0)
		ph += TAU * f / RATE
		lo += (randf() * 2.0 - 1.0 - lo) * 0.08
		out[i] = (sin(ph) + lo * 0.5 * exp(-t * 30.0)) * exp(-t * 7.0)
	return out


## Small hand bell: inharmonic partials that fade at different speeds.
## Each partial is a recursive oscillator (two multiplies per sample, no sin/exp calls).
func _bell(freq: float, dur: float) -> PackedFloat32Array:
	var out := _buf(dur)
	var n := out.size()
	for p in [[1.0, 1.0, 3.0], [2.0, 0.5, 4.5], [2.76, 0.35, 6.0], [4.07, 0.2, 9.0], [5.4, 0.12, 12.0]]:
		var w: float = TAU * freq * p[0] / RATE
		var r: float = exp(-p[2] / RATE)
		var c := 2.0 * r * cos(w)
		var r2 := r * r
		var y1 := 0.0
		var amp: float = p[1]
		var y2: float = -sin(w) * r * amp  # so y starts as amp * sin(w * i)
		for i in n:
			var y: float = c * y1 - r2 * y2
			if i == 0:
				y = 0.0
			out[i] += y * 0.6
			y2 = y1
			y1 = y
	for i in mini(60, n):
		out[i] *= i / 60.0
	return out


## A small room: four combs and two all-passes (Schroeder), mixed in lightly. Adds a short tail.
func _reverb(dry: PackedFloat32Array, wet: float) -> PackedFloat32Array:
	var tail := int(0.35 * RATE)
	var n := dry.size() + tail
	var out := PackedFloat32Array()
	out.resize(n)
	var acc := PackedFloat32Array()
	acc.resize(n)
	acc.fill(0.0)
	for ms in [29.7, 37.1, 41.1, 43.7]:
		var d := int(ms * 0.001 * RATE)
		var line := PackedFloat32Array()
		line.resize(d)
		line.fill(0.0)
		var k := 0
		for i in n:
			var x := dry[i] if i < dry.size() else 0.0
			var y := line[k]
			line[k] = x + y * 0.72
			acc[i] += y
			k = (k + 1) % d
	for ms in [5.0, 1.7]:
		var d := int(ms * 0.001 * RATE)
		var line := PackedFloat32Array()
		line.resize(d)
		line.fill(0.0)
		var k := 0
		for i in n:
			var x := acc[i]
			var y := line[k]
			line[k] = x + y * 0.7
			acc[i] = y - x * 0.7
			k = (k + 1) % d
	for i in n:
		var x := dry[i] if i < dry.size() else 0.0
		out[i] = x + acc[i] * wet * 0.25
	return out


func _wav(b: PackedFloat32Array, level: float) -> AudioStreamWAV:
	var peak := 0.0
	for v in b:
		peak = maxf(peak, absf(v))
	var g := level / maxf(peak, 0.0001)
	var data := PackedByteArray()
	data.resize(b.size() * 2)
	for i in b.size():
		data.encode_s16(i * 2, int(clampf(b[i] * g, -1.0, 1.0) * 32000))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s
