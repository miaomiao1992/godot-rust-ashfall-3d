shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
uniform int kind = 0; // 0 concrete, 1 metal, 2 wood, 3 scorch, 4 chemical spill
uniform float seed = 1.0;
uniform float opacity = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
void fragment() {
    vec2 p = (UV - 0.5) * 2.0;
    float a = atan(p.y, p.x);
    float noise = hash(floor(UV * 48.0));
    float r = length(p);
    float ragged = r + sin(a * 11.0 + seed) * 0.05 + sin(a * 23.0) * 0.025;
    vec3 color = vec3(0.17, 0.16, 0.14);
    float alpha;
    if (kind < 3) {
        float crater = 1.0 - smoothstep(0.25, 0.38, r);
        float rim = smoothstep(0.26, 0.39, r) * (1.0 - smoothstep(0.49, 0.62, ragged));
        float chip = (1.0 - smoothstep(0.54, 0.92, ragged)) * step(0.65, noise);
        color = mix(vec3(0.028, 0.025, 0.021), kind == 1 ? vec3(0.53, 0.57, 0.6) : kind == 2 ? vec3(0.54, 0.36, 0.18) : vec3(0.51, 0.49, 0.43), rim);
        alpha = max(crater * 0.96, max(rim * 0.85, chip * 0.43));
        METALLIC = kind == 1 ? rim * 0.8 : 0.0;
        ROUGHNESS = kind == 1 ? 0.38 : 0.96;
    } else if (kind == 3) {
        float soot = (1.0 - smoothstep(0.30, 0.98, ragged)) * (0.67 + noise * 0.33);
        float radial = pow(max(0.0, sin(a * 17.0 + seed)), 12.0) * (1.0 - smoothstep(0.4, 1.0, r));
        alpha = max(soot, radial * 0.5) * 0.88;
        color = mix(vec3(0.028, 0.022, 0.016), vec3(0.20, 0.14, 0.08), smoothstep(0.12, 0.76, r));
        ROUGHNESS = 1.0;
    } else {
        alpha = (1.0 - smoothstep(0.65, 0.92, ragged)) * 0.87;
        color = mix(vec3(0.025, 0.07, 0.025), vec3(0.21, 0.27, 0.07), noise * 0.3 + sin(r * 28.0) * 0.14);
        ROUGHNESS = 0.24;
    }
    ALBEDO = color;
    ALPHA = alpha * opacity;
}
