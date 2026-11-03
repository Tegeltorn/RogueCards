shader_type canvas_item;
// Subtle scanlines + vignette overlay. Drawn on top of everything, ignores input.

uniform float line_strength = 0.12;
uniform float vignette = 0.35;

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	float line = 0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159 * 0.5);
	vec2 uv = SCREEN_UV - 0.5;
	float v = smoothstep(0.8, 0.2, length(uv * vec2(1.0, 0.8)));
	float dark = line * line_strength + (1.0 - v) * vignette;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(dark, 0.0, 0.8));
}
