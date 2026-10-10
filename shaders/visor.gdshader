shader_type canvas_item;

uniform float hurt = 0.0;
uniform float danger = 0.0;
uniform float clock = 0.0;

void fragment() {
	vec2 uv = UV;
	float edge = pow(clamp(length((uv - vec2(0.5)) * vec2(1.15, 1.0)), 0.0, 1.0), 2.2);
	float grain = fract(sin(dot(uv + clock * 0.007, vec2(12.9898, 78.233))) * 43758.5453);
	float pulse = danger * (0.35 + 0.22 * sin(clock * 7.0));
	vec3 tint = mix(vec3(0.005, 0.015, 0.02), vec3(0.6, 0.015, 0.008), clamp(hurt + pulse, 0.0, 1.0));
	float alpha = edge * (0.58 + hurt * 0.95 + pulse) + grain * 0.022;
	COLOR = vec4(tint, clamp(alpha, 0.0, 0.85));
}
