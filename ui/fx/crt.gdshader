shader_type canvas_item;
// "Vignette" setting: a warm, soft darkening at the edges plus a very fine grain, like an old page
// under lamplight. Drawn on top of everything, ignores input.

uniform vec4 tint : source_color = vec4(0.25, 0.14, 0.06, 1.0);
uniform float vignette = 0.28;
uniform float grain = 0.025;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	float v = smoothstep(0.35, 0.95, length(uv * vec2(1.0, 0.8)));
	float n = hash(floor(FRAGCOORD.xy / 2.0));
	COLOR = vec4(tint.rgb, clamp(v * vignette + n * grain, 0.0, 0.6));
}
