shader_type canvas_item;
// Vellum page: soft mottling, fine fibres and darker edges. In night mode a faint, slow
// candle flicker warms the centre. Original shader written for this project.

uniform vec4 color_a : source_color = vec4(0.94, 0.89, 0.80, 1.0);  // page
uniform vec4 color_b : source_color = vec4(0.87, 0.80, 0.66, 1.0);  // stains and edges
uniform vec4 glow : source_color = vec4(1.0, 0.85, 0.55, 1.0);      // candle light
uniform float glow_strength = 0.0;
uniform float edge = 0.55;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 uv = FRAGCOORD.xy / res.y;
	float mottle = fbm(uv * 3.0);
	float fibre = noise(vec2(uv.x * 220.0, uv.y * 14.0)) * 0.5 + noise(uv * 400.0) * 0.5;
	vec3 col = mix(color_a.rgb, color_b.rgb, smoothstep(0.35, 0.8, mottle) * 0.55);
	col = mix(col, color_b.rgb, (fibre - 0.5) * 0.12);
	vec2 c = SCREEN_UV - 0.5;
	float v = smoothstep(0.25, 0.85, length(c * vec2(1.1, 0.85)));
	col = mix(col, color_b.rgb * 0.92, v * edge);
	float flick = 0.92 + 0.05 * sin(TIME * 1.3) + 0.03 * sin(TIME * 3.7 + 1.0);
	float g = smoothstep(0.75, 0.0, length(c * vec2(1.0, 0.8))) * glow_strength * flick;
	col += glow.rgb * g;
	COLOR = vec4(col, 1.0);
}
