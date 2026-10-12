shader_type spatial;
varying vec3 world_position;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    v += 0.500 * noise(p); p *= 2.02;
    v += 0.250 * noise(p); p *= 2.03;
    v += 0.125 * noise(p);
    return v;
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 p = world_position.xz;
    
    // Macro tar patches and wear
    float patches = noise(p * 0.28) * 0.65 + noise(p * 1.1) * 0.35;
    
    // Fine asphalt aggregate grain
    float grain = noise(p * 7.5);
    float fine_grain = hash(floor(p * 24.0)) * 0.12;
    
    // Road cracking network
    float crack_noise = abs(noise(p * 2.6) - 0.48);
    float cracks = 1.0 - smoothstep(0.0, 0.045, crack_noise);
    
    // Tar sealant lines filling old fissures
    float tar_seal = 1.0 - smoothstep(0.0, 0.07, abs(noise(p * 0.9 + vec2(1.7, 3.4)) - 0.5));
    
    // Volcanic ash / grit accumulation in crevices
    float ash_dust = smoothstep(0.45, 0.75, fbm(p * 0.85 + 4.2)) * 0.22;

    // Base asphalt albedo
    vec3 base_color = vec3(0.115, 0.122, 0.128);
    vec3 albedo = base_color * (0.82 + patches * 0.38 + grain * 0.08 + fine_grain);
    
    // Darken tar fills, lighten ash accumulation
    albedo = mix(albedo, vec3(0.045, 0.047, 0.05), tar_seal * 0.65);
    albedo = mix(albedo, vec3(0.18, 0.16, 0.15), ash_dust);
    albedo -= vec3(cracks * 0.025);
    
    ALBEDO = albedo;
    
    // Surface roughness variation: smoother worn tar vs rough stone aggregate
    ROUGHNESS = clamp(0.78 + grain * 0.14 - tar_seal * 0.25 + ash_dust * 0.1, 0.55, 0.96);
    SPECULAR = 0.25;
    
    // Procedural normal perturbation for asphalt pebble relief
    float eps = 0.04;
    float h_c = grain;
    float h_r = noise((p + vec2(eps, 0.0)) * 7.5);
    float h_u = noise((p + vec2(0.0, eps)) * 7.5);
    vec3 local_n = normalize(vec3((h_c - h_r) * 1.2, 1.0, (h_c - h_u) * 1.2));
    
    NORMAL = normalize((VIEW_MATRIX * vec4(local_n.x, local_n.y, local_n.z, 0.0)).xyz);
}
