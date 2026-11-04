extends Control
## Root of the game UI. Owns the engine, replays its events through the active screen
## (one at a time, so animations play in order) and routes between screens by phase.

const GameEngine := preload("res://engine/engine.gd")
const Balance := preload("res://engine/balance.gd")
const GameState := preload("res://engine/game_state.gd")
const Ev := preload("res://engine/events.gd")
const Style := preload("res://ui/style.gd")
const Store := preload("res://ui/store.gd")
const Sfx := preload("res://ui/sfx.gd")
const Smoke := preload("res://ui/fx/smoke.gd")
const Phase := GameState.Phase

const SCREENS := {
	"menu": preload("res://ui/screens/menu.gd"),
	"reveal": preload("res://ui/screens/reveal.gd"),
	"combat": preload("res://ui/screens/combat.gd"),
	"reward": preload("res://ui/screens/reward.gd"),
	"summary": preload("res://ui/screens/summary.gd"),
}
const LogView := preload("res://ui/screens/log_view.gd")
const DebugMenu := preload("res://ui/screens/debug_menu.gd")
const StatsView := preload("res://ui/screens/stats_view.gd")

var engine: GameEngine
var sfx: Sfx
var updater  # ui/updater.gd: looks for a newer build on start
var settings: Dictionary
var debug_unlocked := false
var screen: Control
var screen_name := ""

var _bg: ColorRect
var _smoke: Smoke
var _shake_root: Control
var _holder: Control
var _overlay: Control
var _crt: ColorRect
var _flash: ColorRect
var _queue: Array = []
var _playing := false
var _shake := 0.0
var _recorded := false


func _ready() -> void:
	settings = Store.settings()
	Style.set_night(bool(settings.get("night", false)))
	theme = Style.theme()
	_bg = ColorRect.new()
	var bgm := ShaderMaterial.new()
	bgm.shader = load("res://ui/fx/background.gdshader")
	_bg.material = bgm
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Style.full(_bg))
	# Smoke drifts over the page, behind the cards and text.
	_smoke = Smoke.new()
	add_child(Style.full(_smoke))
	_shake_root = Style.full(Control.new())
	_shake_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shake_root)
	_holder = Style.full(Control.new())
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shake_root.add_child(_holder)
	_flash = Style.full(ColorRect.new())
	_flash.color = Color(Style.GOLD, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_overlay = Style.full(Control.new())
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_crt = Style.full(ColorRect.new())
	var crtm := ShaderMaterial.new()
	crtm.shader = load("res://ui/fx/crt.gdshader")
	_crt.material = crtm
	_crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crt)
	# Hand cards use small z_index values for their fan order; keep effects and overlays above them.
	_flash.z_index = 90
	_overlay.z_index = 100
	_crt.z_index = 110
	sfx = Sfx.new()
	add_child(sfx)
	updater = load("res://ui/updater.gd").new()
	add_child(updater)
	# Every button and toggle plucks the harp when pressed (cards use paper sounds instead).
	get_tree().node_added.connect(_on_node_added)
	apply_settings()
	if OS.has_feature("web"):
		_start_heartbeat()
	# A run left unfinished (closed tab, or the page reloaded after the phone dropped the graphics) goes on.
	if not resume_run():
		show_screen("menu")


func _process(delta: float) -> void:
	if _shake > 0.01:
		_shake_root.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = lerpf(_shake, 0.0, minf(1.0, delta * 10.0))
	else:
		_shake_root.position = Vector2.ZERO


func apply_settings() -> void:
	_crt.visible = bool(settings.get("crt", true))
	sfx.enabled = bool(settings.get("sound", true))
	_apply_palette()
	Store.save_settings(settings)


## Pushes the current palette (day vellum or candlelit night) into the theme and the shaders.
func _apply_palette() -> void:
	var want := bool(settings.get("night", false))
	var changed := want != Style.night
	if changed:
		Style.set_night(want)
		theme = Style.theme()
	var bgm: ShaderMaterial = _bg.material
	bgm.set_shader_parameter("color_a", Style.BG_A)
	bgm.set_shader_parameter("color_b", Style.BG_B)
	bgm.set_shader_parameter("glow_strength", 0.07 if Style.night else 0.0)
	bgm.set_shader_parameter("edge", 0.9 if Style.night else 0.55)
	var crtm: ShaderMaterial = _crt.material
	crtm.set_shader_parameter("tint", Color(0, 0, 0) if Style.night else Color(0.25, 0.14, 0.06))
	crtm.set_shader_parameter("vignette", 0.4 if Style.night else 0.22)
	if Style.night:
		_smoke.set_colors(Color("eee6da"), Color(0, 0, 0), 0.2)
	else:
		_smoke.set_colors(Color("fffaf0"), Color("6b4a2e"), 0.55)
	if changed and screen != null:
		# Screens bake colours in when built, so rebuild the visible one.
		var n := screen_name
		screen_name = ""
		show_screen(n)
		if screen.has_method("refresh"):
			screen.refresh()


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		(n as BaseButton).pressed.connect(func(): sfx.play("select"))


# ---------------------------------------------------------------- run control

func balance() -> Dictionary:
	return Balance.make(Store.overrides())


func new_run(p_seed: int = -1) -> void:
	if p_seed < 0:
		p_seed = randi() % 1000000
	engine = GameEngine.new()
	engine.event_emitted.connect(_on_event)
	_recorded = false
	_queue.clear()
	var opts := {}
	if settings.get("force_theme", "") != "":
		opts["force_theme"] = settings["force_theme"]
	if settings.get("force_mod", "") != "":
		opts["force_mod"] = settings["force_mod"]
	engine.start_run(p_seed, balance(), opts)
	_queue.clear()  # setup events are shown by the reveal screen itself
	_save_run()
	route()


## Continues the saved unfinished run, if there is one that still replays (see engine.restore()).
func resume_run() -> bool:
	var snap := Store.saved_run()
	if snap.is_empty():
		return false
	var e := GameEngine.new()
	if not e.restore(snap) or e.state.result != "":
		Store.clear_run()
		return false
	engine = e
	engine.event_emitted.connect(_on_event)
	_recorded = false
	_queue.clear()
	route()
	return true


## Saves the run after every action, so nothing is lost if the page or app is closed or reloaded.
func _save_run() -> void:
	if engine == null:
		return
	if engine.state.result != "":
		Store.clear_run()
	else:
		Store.save_run(engine.snapshot())


## Web: tells the page the game is alive (window.rcBeat). The page's watchdog (export_presets.cfg,
## html/head_include) reloads the game if it stays silent after coming back from another app.
func _start_heartbeat() -> void:
	var t := Timer.new()
	t.wait_time = 1.0
	t.timeout.connect(func(): JavaScriptBridge.eval("window.rcBeat = Date.now();", true))
	add_child(t)
	t.start()


## Run an engine action, then replay the events it produced.
func act(fn: Callable) -> void:
	if _playing:
		return
	_playing = true
	fn.call()
	_save_run()
	# Entering the fight: switch first so the fight screen animates the floor start and the deal.
	if _screen_for_phase() == "combat" and screen_name != "combat":
		show_screen("combat")
	await play_queue()
	route()


func has_pending_events() -> bool:
	return not _queue.is_empty()


func _screen_for_phase() -> String:
	if engine == null:
		return "menu"
	match engine.state.phase:
		Phase.REVEAL, Phase.SETUP_PICK:
			return "reveal"
		Phase.PLAY, Phase.RETAIN:
			return "combat"
		Phase.REWARD, Phase.REWARD_REMOVE, Phase.JOKER_ATTACH:
			return "reward"
	return "summary"


func play_queue() -> void:
	_playing = true
	while not _queue.is_empty():
		var ev: Dictionary = _queue.pop_front()
		var d := 0.0
		if screen and screen.has_method("play_event"):
			d = screen.play_event(ev)
		if d > 0.0:
			await get_tree().create_timer(d).timeout
	_playing = false


func is_busy() -> bool:
	return _playing


func _on_event(ev: Dictionary) -> void:
	_queue.append(ev)


func route() -> void:
	if engine == null:
		show_screen("menu")
		return
	var target := _screen_for_phase()
	if target == "summary" and not _recorded:
		_recorded = true
		Store.record_run(engine.state)
	show_screen(target)
	if screen and screen.has_method("refresh"):
		screen.refresh()


func show_screen(name: String) -> void:
	if name == screen_name and screen != null:
		return
	if screen != null:
		var old := screen
		var tw := old.create_tween()
		tw.tween_property(old, "modulate:a", 0.0, 0.12)
		tw.tween_callback(old.queue_free)
	screen_name = name
	screen = SCREENS[name].new()
	screen.set("main", self)
	_holder.add_child(Style.full(screen))
	screen.modulate.a = 0.0
	screen.create_tween().tween_property(screen, "modulate:a", 1.0, 0.15)
	if screen.has_method("enter"):
		screen.enter()


func quit_to_menu() -> void:
	engine = null
	Store.clear_run()
	_queue.clear()
	show_screen("menu")


# ---------------------------------------------------------------- overlays & juice

func open_overlay(ctrl: Control) -> Control:
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := Style.full(ColorRect.new())
	dim.color = Color(0, 0, 0, 0.6) if Style.night else Color(0.2, 0.13, 0.07, 0.38)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)
	var margin := Style.full(MarginContainer.new())
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	dim.add_child(margin)
	margin.add_child(ctrl)
	ctrl.scale = Vector2(0.97, 0.97)
	ctrl.modulate.a = 0.0
	ctrl.pivot_offset = Vector2(340, 600)
	var otw := ctrl.create_tween().set_parallel()
	otw.tween_property(ctrl, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	otw.tween_property(ctrl, "modulate:a", 1.0, 0.18)
	ctrl.tree_exited.connect(func():
		if is_instance_valid(dim):
			dim.queue_free()
		if not is_inside_tree():
			return
		await get_tree().process_frame
		if _overlay.get_child_count() == 0:
			_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE)
	return ctrl


func open_log() -> void:
	if engine != null:
		open_overlay(LogView.new().build(self))


func open_debug() -> void:
	open_overlay(DebugMenu.new().build(self))


func open_stats() -> void:
	open_overlay(StatsView.new().build(self))


## Simple confirm dialog. `choices` = [[label, callable], ...]
func confirm(text: String, choices: Array) -> void:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var p := Style.panel(box)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(Style.label(text, 30))
	for ch in choices:
		var b := Style.button(ch[0], ch[2] if ch.size() > 2 else Style.RED)
		var cb: Callable = ch[1]
		b.pressed.connect(func():
			p.queue_free()
			if cb.is_valid():
				cb.call())
		box.add_child(b)
	open_overlay(p)


## A light haptic tick, like a key press on a phone keyboard. `taps` > 1 gives a quick double tick.
## Works on phones (Android app and mobile web; iOS browsers don't allow vibration). Off in settings.
func haptic(taps: int = 1, ms: int = 15) -> void:
	if not bool(settings.get("vibration", true)):
		return
	Input.vibrate_handheld(ms, 0.35)
	for i in range(1, taps):
		get_tree().create_timer(0.07 * i).timeout.connect(func(): Input.vibrate_handheld(ms, 0.35))


## Screen shake, kept to a gentle nudge (callers pass arcade-sized amounts).
func shake(amount: float = 18.0) -> void:
	_shake = maxf(_shake, minf(amount * 0.3, 8.0))


## A soft wash of colour. Bright whites are turned into warm gold so nothing glares.
func flash(color: Color = Color(1, 1, 1, 0.6), dur: float = 0.25) -> void:
	var c := color
	if c.s < 0.15:
		c = Color(Style.GOLD.lightened(0.3), c.a)
	c.a *= 0.4
	_flash.color = c
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, dur * 1.6).set_trans(Tween.TRANS_SINE)


func burst(pos: Vector2, color: Color, amount: int = 40) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	# Drifting flakes of gold leaf / petals rather than an explosion.
	p.amount = maxi(6, amount / 2)
	p.lifetime = 1.3
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 260.0
	p.damping_min = 60.0
	p.damping_max = 120.0
	p.gravity = Vector2(0, 160)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	p.angular_velocity_min = -120
	p.angular_velocity_max = 120
	_overlay.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


## Animates a copy of `card` from one screen rect to another (e.g. a reward flying into the deck).
## The copy frees itself; await the returned tween to wait for the landing.
func fly_card(card, from: Rect2, to_pos: Vector2, to_size: Vector2, dur: float = 0.45) -> Tween:
	var cv = load("res://ui/card_view.gd").new()
	cv.set_interactive(false)
	cv.breathing = false
	if card == null:  # the red joker
		cv.rank = 0
		cv.suit = "J"
	cv.setup(card, from.size)
	cv.position = from.position
	cv.z_index = 97
	add_child(cv)
	var sc := to_size.x / maxf(1.0, from.size.x)
	var tw: Tween = cv.create_tween()
	tw.tween_property(cv, "scale", Vector2(1.06, 1.06), 0.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(cv, "position", to_pos - (from.size - to_size) / 2, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(cv, "scale", Vector2(sc, sc), dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): sfx.play("draw"))
	tw.tween_callback(cv.queue_free)
	return tw


## Large heading text that fades in over the middle of the screen, like a rubric.
func toast(text: String, color: Color = Style.GOLD, y: float = 520.0, size: int = 64) -> void:
	var l := Style.label(text, size, color)
	l.add_theme_constant_override("outline_size", 14)
	l.size = Vector2(get_viewport_rect().size.x, 120)
	l.position = Vector2(0, y + 16)
	l.pivot_offset = l.size / 2
	l.scale = Vector2(0.92, 0.92)
	l.modulate.a = 0.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 95
	add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 1.0, 0.2)
	tw.parallel().tween_property(l, "position:y", y, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.55)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(l, "position:y", y - 60, 0.3)
	tw.tween_callback(l.queue_free)
