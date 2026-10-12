shader_type spatial;
render_mode specular_schlick_ggx, cull_back;

// Physically Based Ocean Water Shader (Gerstner Wave Dynamics + PBR Optical Model)
// Conforming to Microfacet Theory, Schlick Fresnel, SSS Translucency & Wave Crest Whitecaps.

varying vec3 v_world_pos;
varying vec3 v_wave_normal;
varying float v_wave_height;
varying float v_crest_steepness;

// Gerstner Wave Parameters: direction (xy), steepness (Q), amplitude (A), wavelength (L)
// Wave 1: Primary deep ocean swell
const vec4 WAVE_1 = vec4(0.85, 0.53, 0.42, 28.0); // dir_x, dir_z, steepness, wavelength
const float AMP_1 = 0.28;

// Wave 2: Secondary cross swell
const vec4 WAVE_2 = vec4(-0.45, 0.89, 0.38, 16.5);
const float AMP_2 = 0.16;

// Wave 3: Wind-driven chop wave
const vec4 WAVE_3 = vec4(0.92, -0.38, 0.35, 8.2);
const float AMP_3 = 0.085;

// Wave 4: Lateral capillary wave
const vec4 WAVE_4 = vec4(-0.71, -0.71, 0.30, 4.4);
const float AMP_4 = 0.042;

const float GRAVITY = 9.81;

// Procedural 2D hash for micro-foam and ripples
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
    for (int i = 0; i < 3; i++) {
        v += a * value_noise(p);
        p = rot * p * 2.05 + vec2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

void evaluate_gerstner(vec2 pos, float t, vec4 wave_spec, float amp,
                       inout vec3 disp, inout vec3 d_tan, inout vec3 d_bitan, inout float jacobian) {
    vec2 d = normalize(wave_spec.xy);
    float q = wave_spec.z;
    float lambda = wave_spec.w;
    float k = 2.0 * 3.14159265 / lambda;
    float c = sqrt(GRAVITY / k); // dispersion relation
    float phase = k * dot(d, pos) - c * k * t * 0.95;
    
    float cos_p = cos(phase);
    float sin_p = sin(phase);
    
    // Trochoidal horizontal and vertical displacement
    disp.x += q * amp * d.x * cos_p;
    disp.z += q * amp * d.y * cos_p;
    disp.y += amp * sin_p;
    
    // Wave derivatives for analytic normal
    float wa = k * amp;
    d_tan += vec3(-q * d.x * d.x * wa * sin_p,
                  d.x * wa * cos_p,
                  -q * d.x * d.y * wa * sin_p);
    d_bitan += vec3(-q * d.x * d.y * wa * sin_p,
                    d.y * wa * cos_p,
                    -q * d.y * d.y * wa * sin_p);
    
    // Jacobian compression indicator for crest sharpness/foam
    jacobian += q * wa * sin_p;
}

void vertex() {
    vec3 w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float t = TIME;
    
    vec3 disp = vec3(0.0);
    vec3 d_tan = vec3(0.0);
    vec3 d_bitan = vec3(0.0);
    float jacobian = 0.0;
    
    evaluate_gerstner(w_pos.xz, t, WAVE_1, AMP_1, disp, d_tan, d_bitan, jacobian);
    evaluate_gerstner(w_pos.xz, t, WAVE_2, AMP_2, disp, d_tan, d_bitan, jacobian);
    evaluate_gerstner(w_pos.xz, t, WAVE_3, AMP_3, disp, d_tan, d_bitan, jacobian);
    evaluate_gerstner(w_pos.xz, t, WAVE_4, AMP_4, disp, d_tan, d_bitan, jacobian);
    
    w_pos += disp;
    v_world_pos = w_pos;
    v_wave_height = disp.y;
    v_crest_steepness = clamp((disp.y + 0.35) / 0.70 + jacobian * 0.6, 0.0, 1.5);
    
    vec3 tangent = normalize(vec3(1.0, 0.0, 0.0) + d_tan);
    vec3 bitangent = normalize(vec3(0.0, 0.0, 1.0) + d_bitan);
    v_wave_normal = normalize(cross(bitangent, tangent));
    
    VERTEX += disp;
}

void fragment() {
    vec2 p = v_world_pos.xz;
    float t = TIME * 0.85;
    
    // Multi-octave surface tension capillary micro-normals
    vec2 uv1 = p * 0.18 + vec2(t * 0.04, t * 0.025);
    vec2 uv2 = p * 0.42 - vec2(t * 0.035, -t * 0.05);
    vec2 uv3 = p * 1.15 + vec2(-t * 0.07, t * 0.09);
    
    float n1 = fbm(uv1);
    float n2 = fbm(uv2);
    float n3 = fbm(uv3);
    
    // Calculate micro-normal perturbations
    float dnx = (n1 - 0.5) * 0.12 + (n2 - 0.5) * 0.08 + (n3 - 0.5) * 0.04;
    float dnz = (n2 - 0.5) * 0.12 + (n1 - 0.5) * 0.08 - (n3 - 0.5) * 0.04;
    
    vec3 micro_n = normalize(vec3(dnx, 1.0, dnz));
    vec3 blended_normal = normalize(v_wave_normal + micro_n * 0.45);
    NORMAL = normalize((VIEW_MATRIX * vec4(blended_normal, 0.0)).xyz);
    
    // View vector and physical Schlick Fresnel calculation (F0 = 0.02 for water)
    vec3 view_dir = normalize(-VERTEX);
    float NdotV = clamp(dot(NORMAL, view_dir), 0.0, 1.0);
    float fresnel = 0.02 + 0.98 * pow(1.0 - NdotV, 5.0);
    
    // PBR Water Color Model:
    // Deep Ocean Absorption (Murky industrial port water): deep blue-slate navy
    vec3 deep_color = vec3(0.012, 0.038, 0.065);
    // Crest / Shallow water: vibrant turquoise emerald
    vec3 shallow_color = vec3(0.032, 0.145, 0.185);
    // Translucent SSS crest glow: backlit light passing through thin wave peaks
    vec3 crest_sss_color = vec3(0.065, 0.28, 0.32);
    
    float depth_factor = clamp(v_wave_height * 1.8 + 0.5, 0.0, 1.0);
    vec3 base_water = mix(deep_color, shallow_color, depth_factor * 0.65);
    
    // Backlit Subsurface Scattering approximation
    float sss_factor = pow(1.0 - NdotV, 2.5) * clamp(v_wave_height * 2.2 + 0.2, 0.0, 1.0);
    base_water = mix(base_water, crest_sss_color, sss_factor * 0.4);
    
    // Sky reflection color at grazing angles (reflecting the coastal overcast sky)
    vec3 sky_reflection = vec3(0.48, 0.58, 0.68) * 0.95;
    vec3 surface_color = mix(base_water, sky_reflection, fresnel * 0.72);
    
    // Pier and structure contact foam:
    // The main docks are along x = -36, -12, 12, 36, sunken vessel at x ~ 0, z ~ -18
    float dist_p1 = abs(p.x - 12.0);
    float dist_p2 = abs(p.x + 12.0);
    float dist_p3 = abs(p.x - 36.0);
    float dist_p4 = abs(p.x + 36.0);
    float pier_dist = min(min(dist_p1, dist_p2), min(dist_p3, dist_p4));
    float contact_foam = smoothstep(1.8, 0.2, pier_dist) * (0.6 + 0.4 * sin(p.y * 3.0 + t * 2.0));
    
    // Wave Crest Whitecaps / Foam:
    // Waves break into foam when crest steepness exceeds threshold
    float foam_noise = fbm(p * 0.85 + vec2(t * 0.12, -t * 0.08));
    float crest_foam = smoothstep(0.72, 1.15, v_crest_steepness) * smoothstep(0.28, 0.75, foam_noise);
    
    float total_foam = clamp(crest_foam * 0.95 + contact_foam * 0.65, 0.0, 1.0);
    vec3 foam_color = vec3(0.86, 0.92, 0.95);
    
    // Subtle port chemical iridescence in calm wake zones
    float oil_noise = value_noise(p * 0.18 + vec2(t * 0.03, -t * 0.02));
    if (oil_noise > 0.72 && total_foam < 0.2) {
        float oil_t = (oil_noise - 0.72) / 0.28;
        vec3 rainbow = 0.5 + 0.5 * cos(oil_t * 6.283 + vec3(0.0, 2.0, 4.0));
        surface_color = mix(surface_color, rainbow * 0.35, oil_t * 0.38);
    }
    
    // Final albedo and PBR material properties
    ALBEDO = mix(surface_color, foam_color, total_foam * 0.88);
    ROUGHNESS = mix(clamp(0.06 + (1.0 - NdotV) * 0.08, 0.04, 0.25), 0.82, total_foam);
    METALLIC = 0.03;
    SPECULAR = mix(0.85, 0.15, total_foam); // Strong GGX specular shimmer path on water
}
