extends ColorRect
## Drifting smoke over the page, drawn entirely by ui/fx/smoke.gdshader (no CPU work).


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://ui/fx/smoke.gdshader")
	material = m


func set_colors(smoke: Color, shade: Color, strength: float) -> void:
	var m := material as ShaderMaterial
	m.set_shader_parameter("smoke_col", smoke)
	m.set_shader_parameter("shade_col", shade)
	m.set_shader_parameter("strength", strength)
