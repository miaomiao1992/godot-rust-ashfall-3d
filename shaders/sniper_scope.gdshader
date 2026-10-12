shader_type canvas_item;
uniform float active = 0.0;
uniform vec2 viewport_size = vec2(1440.0, 900.0);
void fragment() {
    vec2 p = (UV - 0.5) * vec2(viewport_size.x / viewport_size.y, 1.0);
    float r = length(p);
    float rim = smoothstep(0.34, 0.385, r);
    float outside = smoothstep(0.375, 0.385, r);
    COLOR = vec4(mix(vec3(0.03, 0.10, 0.12), vec3(0.004), outside), active * max(outside, rim * 0.45));
}
