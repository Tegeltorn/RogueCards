shader_type canvas_item;
// Slow saturated swirl. Original shader written for this project.

uniform vec4 color_a : source_color = vec4(0.11, 0.06, 0.20, 1.0);
uniform vec4 color_b : source_color = vec4(0.05, 0.27, 0.20, 1.0);
uniform vec4 color_c : source_color = vec4(0.30, 0.08, 0.32, 1.0);
uniform float speed = 0.06;
uniform float pixel = 6.0;
uniform float intensity = 1.0;

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 px = floor(FRAGCOORD.xy / pixel) * pixel;
	vec2 uv = (px - 0.5 * res) / res.y;
	float t = TIME * speed;
	float r = length(uv);
	float a = atan(uv.y, uv.x);
	float swirl = a + r * 3.2 - t * 6.0;
	float w = sin(swirl * 3.0 + sin(r * 6.0 - t * 4.0) * 1.4);
	float w2 = sin(uv.x * 4.0 + t * 3.0 + sin(uv.y * 5.0 - t * 2.0));
	float m = smoothstep(-1.0, 1.0, w * 0.7 + w2 * 0.3);
	vec3 col = mix(color_a.rgb, color_b.rgb, m);
	col = mix(col, color_c.rgb, smoothstep(0.55, 1.0, sin(swirl * 1.5 + t) * 0.5 + 0.5) * 0.5);
	col *= 1.0 - r * 0.45;
	col = floor(col * 24.0) / 24.0;
	COLOR = vec4(mix(color_a.rgb, col, intensity), 1.0);
}
