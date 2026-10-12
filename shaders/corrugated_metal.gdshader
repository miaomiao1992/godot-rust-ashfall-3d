shader_type spatial;
render_mode specular_schlick_ggx;

// PBR Corrugated Industrial Steel & Container Shader
varying vec3 v_world_pos;
varying vec3 v_local_pos;
varying vec3 v_normal;

uniform vec3 base_color : source_color = vec3(0.55, 0.58, 0.62);
uniform float corrugation_pitch = 0.65;
uniform float corrugation_depth = 0.55;
uniform float metallic = 0.82;
uniform float roughness = 0.42;
uniform bool horizontal_slats = false;

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
    v_local_pos = VERTEX;
    v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    // Choose coordinate axis along which corrugation ripples
    float coord = horizontal_slats ? v_world_pos.y : (abs(v_normal.z) > 0.5 ? v_world_pos.x : v_world_pos.z);
    
    // Trapezoidal / sine wave profile for industrial corrugation
    float phase = (coord / corrugation_pitch) * 6.283185;
    float wave_cos = cos(phase);
    float wave_sin = sin(phase);
    
    // Fine brushed steel texture & surface scratches
    vec2 scratch_uv = vec2(coord * 4.0, (horizontal_slats ? v_world_pos.x : v_world_pos.y) * 1.5);
    float brush_grain = noise(scratch_uv * 12.0) * 0.12;
    float patina = noise(v_world_pos.xz * 0.4 + vec2(v_world_pos.y * 0.2, 0.0)) * 0.22;
    
    // Trough accumulation of industrial grime / oxidation
    float trough = clamp(-wave_cos * 0.5 + 0.5, 0.0, 1.0);
    vec3 col = base_color * (0.90 + brush_grain - patina * 0.3);
    col = mix(col, col * 0.65, trough * 0.45);
    
    // Microfacet normal perturbation from the corrugation slope
    float normal_perturb = -wave_sin * corrugation_depth;
    vec3 tangent_vec = horizontal_slats ? vec3(0.0, 1.0, 0.0) : (abs(v_normal.z) > 0.5 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0));
    vec3 bitangent_vec = cross(v_normal, tangent_vec);
    vec3 perturbed_world_n = normalize(v_normal + tangent_vec * normal_perturb);
    
    ALBEDO = col;
    METALLIC = metallic;
    ROUGHNESS = clamp(roughness + patina * 0.25 + trough * 0.15, 0.15, 0.85);
    SPECULAR = 0.55;
    NORMAL = normalize((VIEW_MATRIX * vec4(perturbed_world_n, 0.0)).xyz);
}
