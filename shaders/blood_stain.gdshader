shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform vec4 blood_color : source_color = vec4(0.08, 0.018, 0.013, 0.65);
uniform float spread : hint_range(0.0, 1.0) = 1.0;
void fragment() {
    vec2 p = (UV - 0.5) * 2.0;
    float angle = atan(p.y, p.x);
    float radius = length(p) + sin(angle * 7.0) * 0.065 + sin(angle * 13.0) * 0.025;
    ALBEDO = blood_color.rgb;
    ROUGHNESS = 0.93;
    ALPHA = (1.0 - smoothstep(0.60, 0.98, radius / max(spread, 0.01))) * blood_color.a;
}
