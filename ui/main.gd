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
var settings: Dictionary
var debug_unlocked := false
var screen: Control
var screen_name := ""

var _bg: ColorRect
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
	theme = Style.theme()
	settings = Store.settings()
	_bg = ColorRect.new()
	var bgm := ShaderMaterial.new()
	bgm.shader = load("res://ui/fx/background.gdshader")
	_bg.material = bgm
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(Style.full(_bg))
	_shake_root = Style.full(Control.new())
	_shake_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shake_root)
	_holder = Style.full(Control.new())
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shake_root.add_child(_holder)
	_flash = Style.full(ColorRect.new())
	_flash.color = Color(1, 1, 1, 0)
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
	apply_settings()
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
	Store.save_settings(settings)


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
	route()


## Run an engine action, then replay the events it produced.
func act(fn: Callable) -> void:
	if _playing:
		return
	_playing = true
	fn.call()
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
	_queue.clear()
	show_screen("menu")


# ---------------------------------------------------------------- overlays & juice

func open_overlay(ctrl: Control) -> Control:
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := Style.full(ColorRect.new())
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)
	var margin := Style.full(MarginContainer.new())
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	dim.add_child(margin)
	margin.add_child(ctrl)
	ctrl.scale = Vector2(0.9, 0.9)
	ctrl.pivot_offset = Vector2(340, 600)
	ctrl.create_tween().tween_property(ctrl, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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


func shake(amount: float = 18.0) -> void:
	_shake = maxf(_shake, amount)


func flash(color: Color = Color(1, 1, 1, 0.6), dur: float = 0.25) -> void:
	_flash.color = color
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, dur)


func burst(pos: Vector2, color: Color, amount: int = 40) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.8
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 250.0
	p.initial_velocity_max = 650.0
	p.gravity = Vector2(0, 1100)
	p.scale_amount_min = 6.0
	p.scale_amount_max = 14.0
	p.color = color
	p.angular_velocity_min = -400
	p.angular_velocity_max = 400
	_overlay.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


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
	tw.tween_property(cv, "scale", Vector2(1.15, 1.15), 0.1).set_trans(Tween.TRANS_BACK)
	tw.tween_property(cv, "position", to_pos - (from.size - to_size) / 2, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(cv, "scale", Vector2(sc, sc), dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): sfx.play("draw"))
	tw.tween_callback(cv.queue_free)
	return tw


## Big popping text in the middle of the screen.
func toast(text: String, color: Color = Style.GOLD, y: float = 520.0, size: int = 64) -> void:
	var l := Style.label(text, size, color)
	l.add_theme_constant_override("outline_size", 12)
	l.size = Vector2(get_viewport_rect().size.x, 120)
	l.position = Vector2(0, y)
	l.pivot_offset = l.size / 2
	l.scale = Vector2(0.2, 0.2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 95
	add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.15, 1.15), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.1)
	tw.tween_interval(0.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(l, "position:y", y - 60, 0.3)
	tw.tween_callback(l.queue_free)
