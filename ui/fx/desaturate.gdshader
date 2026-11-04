shader_type canvas_item;
// Fades a card's colours to a dull, warm grey (like faded ink) as `amount` goes 0 -> 1.

uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = COLOR;
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 faded = vec3(l) * vec3(1.0, 0.96, 0.88) * 0.9 + 0.04;
	COLOR = vec4(mix(c.rgb, faded, amount), c.a);
}
