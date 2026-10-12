shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float seed = 0.0;
uniform float density = 0.0;
varying vec3 point;
void vertex() { point = VERTEX; }
void fragment() {
	float noise = sin(point.x * 3.1 + TIME * 0.32 + seed) * sin(point.y * 3.7 - TIME * 0.2) * sin(point.z * 3.3 + seed);
	float facing = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 0.7);
	ALBEDO = vec3(0.40, 0.42, 0.43) + noise * 0.045;
	ALPHA = density * facing * (0.30 + noise * 0.08);
}
