shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 warning_color : source_color = vec4(1.0, 0.65, 0.17, 1.0);
uniform vec4 active_color : source_color = vec4(0.38, 0.7, 0.15, 1.0);
uniform float phase = 0.0;
uniform float progress = 0.0;
uniform float fade = 1.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	if (r > 1.0) { discard; }
	float border = smoothstep(0.90, 0.96, r);
	float angle = mod(atan(p.y, p.x) + 6.283185, 6.283185) / 6.283185;
	float countdown = step(angle, progress) * smoothstep(0.78, 0.81, r) * (1.0 - smoothstep(0.85, 0.88, r));
	float active = step(0.5, phase);
	float texture_detail = 0.5 + 0.5 * sin(p.x * 19.0 + TIME * 1.2) * sin(p.y * 17.0 - TIME * 0.8);
	ALBEDO = mix(warning_color.rgb, active_color.rgb, active);
	ALPHA = (border * 0.82 + countdown * (1.0 - active) * 0.65 + (1.0 - border) * mix(0.055, 0.16 + texture_detail * 0.12, active)) * fade;
}
