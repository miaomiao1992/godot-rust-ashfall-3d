shader_type spatial;
render_mode specular_schlick_ggx;

// Physically Based Concrete & Ramp Shader (conforming to PBR Microfacet & Disney Principled BxDF)
// Features industrial slab joints, aggregate porosity, forklift wear tracks, and curb hazard stripes.

varying vec3 v_world_pos;
varying vec3 v_normal;

uniform vec3 base_color : source_color = vec3(0.38, 0.39, 0.40);
uniform float tile_size = 4.0;
uniform bool is_ramp = false;

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

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        v += a * noise(p);
        p = p * 2.1 + vec2(1.6, 3.8);
        a *= 0.5;
    }
    return v;
}

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    vec2 p = v_world_pos.xz;
    
    // Industrial slab joint grid
    vec2 grid_uv = fract(p / tile_size);
    vec2 dist_to_edge = min(grid_uv, 1.0 - grid_uv) * tile_size;
    float joint_dist = min(dist_to_edge.x, dist_to_edge.y);
    float joint = 1.0 - smoothstep(0.02, 0.07, joint_dist);
    
    // Fine concrete aggregate grain and surface pores
    float aggregate = noise(p * 18.0) * 0.14 + noise(p * 45.0) * 0.06;
    float macro_mottle = fbm(p * 0.65) * 0.22;
    
    // Forklift wheel wear / scuff lanes along central aisle
    float track_x = abs(p.x - 12.0);
    float wheel_lane = smoothstep(3.5, 0.8, track_x) * (0.6 + 0.4 * noise(vec2(p.y * 0.2, p.x * 2.0)));
    
    // Concrete base tone
    vec3 col = base_color * (0.88 + macro_mottle + aggregate);
    
    // Recessed dark joint sealant
    col = mix(col, vec3(0.08, 0.08, 0.09), joint * 0.75);
    
    // Darken wheel wear paths slightly (rubber residue / worn polish)
    col = mix(col, col * 0.82, wheel_lane * 0.45);
    
    // Microfacet roughness: worn areas are slightly smoother, pores are rough
    float roughness = clamp(0.78 + aggregate * 0.3 - joint * 0.25 - wheel_lane * 0.15, 0.55, 0.95);
    
    // Normal perturbation for concrete porous texture and joint bevel
    float eps = 0.03;
    float h_c = aggregate - joint * 0.15;
    float h_r = noise((p + vec2(eps, 0.0)) * 18.0) * 0.14;
    float h_u = noise((p + vec2(0.0, eps)) * 18.0) * 0.14;
    vec3 local_n = normalize(vec3((h_c - h_r) * 1.5, 1.0, (h_c - h_u) * 1.5));
    
    ALBEDO = col;
    ROUGHNESS = roughness;
    METALLIC = 0.02;
    SPECULAR = 0.35;
    NORMAL = normalize((VIEW_MATRIX * vec4(local_n, 0.0)).xyz);
}
