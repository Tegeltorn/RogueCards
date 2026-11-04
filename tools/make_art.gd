extends SceneTree
## Renders the app icon and the loading-screen image with the game's own card drawing and fonts,
## so they always match the theme. Needs a display:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/make_art.gd -- icon
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/make_art.gd -- splash

const Style := preload("res://ui/style.gd")
const CardView := preload("res://ui/card_view.gd")


func _init() -> void:
	var what: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "icon"
	# A SubViewport renders at exact pixels (the game window itself stretches a 720x1280 canvas).
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512) if what == "icon" else Vector2i(720, 660)
	vp.transparent_bg = what != "icon"
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var stage := Control.new()
	stage.theme = Style.theme()
	vp.add_child(stage)
	stage.size = Vector2(vp.size)
	if what == "icon":
		_icon(stage)
	else:
		_splash(stage)
	for i in 8:
		await process_frame
	var img := vp.get_texture().get_image()
	var out := "res://icon.png" if what == "icon" else "res://assets/splash.png"
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	quit()


func _card(parent: Control, rank: int, suit: String, sz: Vector2, pos: Vector2, rot: float) -> void:
	var cv := CardView.new()
	cv.set_interactive(false)
	cv.breathing = false
	cv.rank = rank
	cv.suit = suit
	cv.setup(null, sz)
	cv.position = pos
	cv.rotation = rot
	parent.add_child(cv)


func _icon(stage: Control) -> void:
	var bg := ColorRect.new()
	var m := ShaderMaterial.new()
	m.shader = load("res://ui/fx/background.gdshader")
	m.set_shader_parameter("color_a", Style.BG_A)
	m.set_shader_parameter("color_b", Style.BG_B)
	m.set_shader_parameter("edge", 0.9)
	bg.material = m
	stage.add_child(Style.full(bg))
	var sz := Vector2(250, 350)
	_card(stage, 14, "H", sz, Vector2(60, 100), -0.26)
	_card(stage, 14, "S", sz, Vector2(200, 70), 0.14)


func _splash(stage: Control) -> void:
	var W := stage.size.x
	var sz := Vector2(150, 210)
	var suits := ["S", "H", "C", "D"]
	for i in 4:
		var x := W / 2 - 2 * 92 + i * 92 - sz.x / 2 + 46
		_card(stage, 14, suits[i], sz, Vector2(x, 60 + absf(i - 1.5) * 20), (i - 1.5) * 0.18)
	var title := Style.label("RogueCards", 96, Style.GOLD)
	title.position = Vector2(0, 340)
	title.size = Vector2(W, 140)
	stage.add_child(title)
	var orn := Style.ornament(0)
	orn.position = Vector2(W * 0.18, 500)
	orn.size = Vector2(W * 0.64, 18)
	stage.add_child(orn)
	var sub := Style.label("A roguelike deckbuilder with a standard deck of cards", 30, Style.MUTED)
	sub.position = Vector2(0, 540)
	sub.size = Vector2(W, 60)
	stage.add_child(sub)
