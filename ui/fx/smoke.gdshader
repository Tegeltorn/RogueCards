shader_type canvas_item;
// Drifting, swirling smoke over the page. Domain-warped flow noise: the drift wanders in a slow
// loop (so the smoke moves in every direction over time) and the inner warps rotate, which curls
// the wisps. Original shader written for this project.

uniform vec4 smoke_col : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform vec4 shade_col : source_color = vec4(0.45, 0.32, 0.2, 1.0);
uniform float strength = 0.4;
uniform float shade_strength = 0.14;
uniform float speed = 1.0;

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
	for (int i = 0; i < 3; i++) {
		v += a * noise(p);
		p = p * 2.07 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

mat2 rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

void fragment() {
	float t = TIME * speed;
	// Round blobs on a tall screen: scale y by the aspect ratio.
	vec2 p = UV * vec2(2.3, 4.0);
	// The whole field drifts along a slow loop, so over time it travels in every direction.
	vec2 drift = vec2(sin(t * 0.043) + 0.6 * sin(t * 0.017 + 1.3), cos(t * 0.031) + 0.6 * cos(t * 0.021 + 0.4)) * 2.2;
	vec2 q = vec2(fbm(p + drift), fbm(p + vec2(5.2, 1.3) - drift * 0.7));
	// Rotating the warp vectors makes the wisps curl around instead of just sliding.
	vec2 w = rot(t * 0.11 + q.x * 2.5) * (q - 0.5);
	vec2 r = vec2(fbm(p + 3.2 * w + vec2(1.7, 9.2) + drift * 0.4), fbm(p + 3.2 * w + vec2(8.3, 2.8) - drift * 0.3));
	vec2 w2 = rot(-t * 0.08 + r.y * 3.0) * (r - 0.5);
	float f = fbm(p * 1.3 + 3.6 * w2 + drift * 0.2);
	// Fine curls inside the smoke.
	float detail = mix(0.6, 1.2, fbm(p * 3.5 + 4.0 * w2 - drift * 0.5));
	float d = smoothstep(0.5, 0.82, f) * detail;
	float a = clamp(d, 0.0, 1.0) * strength;
	// A faint warm shade on the thin edges, so the warm white still reads on light vellum.
	float edge = smoothstep(0.42, 0.52, f) * (1.0 - smoothstep(0.52, 0.66, f));
	float sa = edge * shade_strength * strength;
	float total = a + sa;
	COLOR = vec4(mix(shade_col.rgb, smoke_col.rgb, a / max(total, 1e-4)), clamp(total, 0.0, 0.6));
}
