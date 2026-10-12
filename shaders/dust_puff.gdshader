shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec4 tint : source_color = vec4(0.5, 0.46, 0.4, 0.55);
uniform float opacity = 1.0;
void vertex() {
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}
void fragment() {
    vec2 p = (UV - 0.5) * 2.0;
    float radius = length(p);
    float wisps = 0.78 + sin(p.x * 13.0 + sin(p.y * 9.0)) * 0.12;
    ALBEDO = tint.rgb;
    ALPHA = (1.0 - smoothstep(0.12, 1.0, radius)) * wisps * tint.a * opacity;
}
