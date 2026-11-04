shader_type canvas_item;
// Smoke drifting across the page. Two layers of soft noise pan steadily up and to the side, so the
// wisps travel out of view and new ones come in (the far layer slower, for depth). One gentle warp
// keeps the edges soft without the liquid-like swirling. Original shader written for this project.

uniform vec4 smoke_col : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform vec4 shade_col : source_color = vec4(0.45, 0.32, 0.2, 1.0);
uniform float strength = 0.4;
uniform float shade_strength = 0.14;
uniform float speed = 1.0;
// Pan direction and speed in screen heights per second (y < 0 rises).
uniform vec2 pan = vec2(0.012, -0.03);

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
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// One smoke layer: wisps stretched along the drift, slowly changing shape as they pan.
float layer(vec2 uv, float scale, float rate, float t, vec2 seed) {
	// Stretch vertically so the wisps look drawn out by the drift, not round like blobs.
	vec2 p = uv * vec2(scale, scale * 0.9) - pan * vec2(scale, scale * 0.9) * t * rate + seed;
	// A single, small warp: soft edges, no curling.
	vec2 w = vec2(fbm(p * 0.6 + vec2(0.0, t * 0.015)), fbm(p * 0.6 + vec2(4.1, -t * 0.012))) - 0.5;
	float f = fbm(p + w * 0.9);
	return f;
}

void fragment() {
	float t = TIME * speed;
	vec2 uv = UV * vec2(1.0, 1.78);  // tall screen: keep the noise round
	float near = layer(uv, 2.4, 1.0, t, vec2(0.0));
	float far = layer(uv, 3.6, 0.55, t, vec2(13.7, 4.2));
	float d = max(smoothstep(0.52, 0.8, near), smoothstep(0.56, 0.86, far) * 0.6);
	float a = clamp(d, 0.0, 1.0) * strength;
	// A faint warm shade on the thin edges of the near layer, so the smoke reads on light vellum.
	float edge = smoothstep(0.44, 0.52, near) * (1.0 - smoothstep(0.52, 0.64, near));
	float sa = edge * shade_strength * strength;
	float total = a + sa;
	COLOR = vec4(mix(shade_col.rgb, smoke_col.rgb, a / max(total, 1e-4)), clamp(total, 0.0, 0.6));
}
