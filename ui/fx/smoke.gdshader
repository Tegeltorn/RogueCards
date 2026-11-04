shader_type canvas_item;
// Smoke over the page. With `simulated`, the shape comes from the small fluid-sim density texture
// (ui/fx/smoke.gd) and this shader only adds fine wisps. Without it, the shape is drifting,
// domain-warped flow noise (no CPU work). Original shader written for this project.

uniform sampler2D density : filter_linear, repeat_disable;
uniform bool simulated = true;
uniform vec4 smoke_col : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform vec4 shade_col : source_color = vec4(0.45, 0.32, 0.2, 1.0);
uniform float strength = 0.4;
uniform float shade_strength = 0.35;

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

float flow(vec2 uv, float t) {
	vec2 p = uv * vec2(2.2, 3.2);
	vec2 q = vec2(fbm(p + vec2(0.0, t * 0.05)), fbm(p + vec2(5.2, 1.3) - vec2(t * 0.03, 0.0)));
	float r = fbm(p + 2.6 * q + vec2(0.0, t * 0.09));
	return smoothstep(0.38, 0.72, r) * (0.6 + 0.5 * uv.y);
}

float dens_at(vec2 uv, float t) {
	if (simulated) {
		// 4 taps half a cell apart: hides the coarse grid's bilinear diamonds.
		vec2 h = vec2(0.5 / 36.0, 0.5 / 64.0);
		float s = texture(density, uv + vec2(-h.x, -h.y)).r + texture(density, uv + vec2(h.x, -h.y)).r
			+ texture(density, uv + vec2(-h.x, h.y)).r + texture(density, uv + vec2(h.x, h.y)).r;
		return s * 0.55;
	}
	return flow(uv, t);
}

void fragment() {
	float t = TIME;
	vec2 uv = UV;
	// Wisps: wobble the lookup and break the density into curls with finer noise.
	vec2 wob = vec2(fbm(uv * 7.0 + vec2(0.0, t * 0.12)), fbm(uv * 7.0 + vec2(4.0, -t * 0.1))) - 0.5;
	vec2 uv2 = uv + wob * 0.06;
	float detail = mix(0.55, 1.25, fbm(uv * vec2(11.0, 16.0) + wob * 2.0 + vec2(0.0, t * 0.06)));
	float d = clamp(dens_at(uv2, t) * detail, 0.0, 1.0);
	// A faint shade a little below the smoke, so warm white still reads on light vellum.
	float sd = clamp(dens_at(uv2 - vec2(0.004, 0.008), t) * detail, 0.0, 1.0);
	float a = smoothstep(0.03, 0.75, d) * strength;
	float sa = max(sd - d, 0.0) * shade_strength * strength;
	float total = a + sa;
	COLOR = vec4(mix(shade_col.rgb, smoke_col.rgb, a / max(total, 1e-4)), clamp(total, 0.0, 0.6));
}
