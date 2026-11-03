extends Node
## Placeholder sounds synthesized at startup (no audio files, nothing to license).

const RATE := 22050

var enabled := true
var _streams: Dictionary = {}
var _players: Array = []
var _next := 0


func _ready() -> void:
	_streams["draw"] = _make(0.07, func(t, _i): return _noise() * _env(t, 0.07) * 0.5)
	_streams["select"] = _make(0.08, func(t, _i): return _sq(t, 660 + 900 * t) * _env(t, 0.08) * 0.25)
	_streams["play"] = _make(0.16, func(t, _i): return (_noise() * 0.4 + sin(TAU * (180 - 500 * t) * t) * 0.6) * _env(t, 0.16) * 0.6)
	_streams["flip"] = _make(0.1, func(t, _i): return _noise() * _env(t, 0.1) * 0.35 + _sq(t, 400) * _env(t, 0.03) * 0.15)
	_streams["hit"] = _make(0.35, func(t, _i): return (_noise() * 0.7 + sin(TAU * (90 - 120 * t) * t)) * _env(t, 0.35) * 0.7)
	_streams["block"] = _make(0.22, func(t, _i): return _sq(t, 220) * _env(t, 0.22) * 0.25 + sin(TAU * 330 * t) * _env(t, 0.22) * 0.3)
	_streams["defeat"] = _make(0.3, func(t, _i): return _sq(t, 520 + 900 * t) * _env(t, 0.3) * 0.22)
	_streams["crack"] = _make(0.4, func(t, _i): return _noise() * _env(t, 0.4) * (0.6 if fmod(t, 0.05) < 0.02 else 0.15))
	_streams["reward"] = _make(0.5, func(t, _i): return _sq(t, [523.0, 659.0, 784.0, 1047.0][mini(int(t / 0.12), 3)]) * _env(t, 0.5) * 0.22)
	_streams["exact"] = _make(0.4, func(t, _i): return sin(TAU * 880 * t) * _env(t, 0.4) * 0.35 + sin(TAU * 1320 * t) * _env(t, 0.4) * 0.2)
	_streams["win"] = _make(1.0, func(t, _i): return _sq(t, [392.0, 523.0, 659.0, 784.0, 1047.0, 1047.0][mini(int(t / 0.15), 5)]) * _env(t, 1.0) * 0.22)
	_streams["lose"] = _make(0.9, func(t, _i): return _sq(t, 300 - 200 * t) * _env(t, 0.9) * 0.25)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(name: String, pitch: float = 1.0) -> void:
	if not enabled or not _streams.has(name):
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name]
	p.pitch_scale = pitch * randf_range(0.95, 1.05)
	p.play()


func _make(dur: float, fn: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v: float = clampf(fn.call(t, i), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


static func _noise() -> float:
	return randf() * 2.0 - 1.0


static func _sq(t: float, f: float) -> float:
	return 1.0 if fmod(t * f, 1.0) < 0.5 else -1.0


static func _env(t: float, dur: float) -> float:
	var attack := 0.005
	if t < attack:
		return t / attack
	return pow(1.0 - clampf(t / dur, 0.0, 1.0), 2.0)
