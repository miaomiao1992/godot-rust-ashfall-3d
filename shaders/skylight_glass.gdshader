shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// Industrial Wire-Reinforced Skylight Glass Shader
varying vec3 v_world_pos;
varying vec3 v_normal;

uniform vec3 glass_tint : source_color = vec3(0.68, 0.78, 0.85);
uniform float wire_pitch = 0.35;

float hash21(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    vec2 p = v_world_pos.xz;
    
    // Internal diamond wire mesh reinforcement
    vec2 wire_uv = fract((p.x + vec2(p.y, -p.y) * 0.707) / wire_pitch);
    float d_wire = min(min(wire_uv.x, 1.0 - wire_uv.x), min(wire_uv.y, 1.0 - wire_uv.y));
    float wire = 1.0 - smoothstep(0.015, 0.045, d_wire);
    
    // Industrial soot and rain water spots
    float dust = noise(p * 2.8) * 0.4 + noise(p * 9.5) * 0.15;
    
    // Schlick Fresnel calculation for glass (F0 = 0.04)
    vec3 view_dir = normalize(-VERTEX);
    float NdotV = clamp(dot(NORMAL, view_dir), 0.0, 1.0);
    float fresnel = 0.04 + 0.96 * pow(1.0 - NdotV, 5.0);
    
    vec3 col = mix(glass_tint, vec3(0.18, 0.19, 0.21), wire * 0.85);
    col = mix(col, vec3(0.45, 0.42, 0.38), dust * 0.35);
    
    ALBEDO = col;
    ALPHA = clamp(0.35 + fresnel * 0.55 + wire * 0.45 + dust * 0.25, 0.25, 0.92);
    ROUGHNESS = mix(0.12, 0.65, dust);
    METALLIC = wire * 0.75;
    SPECULAR = 0.85;
}
