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

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 p = world_position.xz;
    
    // Multi-directional harmonic swell waves
    float t = TIME * 0.9;
    float w1 = sin(p.x * 1.40 + p.y * 0.65 + t * 1.3);
    float w2 = sin(p.x * 0.45 - p.y * 1.85 - t * 0.95);
    float w3 = sin(p.x * 4.20 + p.y * 2.80 + t * 2.1);
    float w4 = cos(p.x * 2.80 - p.y * 3.50 + t * 1.6);
    
    // Wave normals
    float dx = -(cos(p.x * 1.40 + p.y * 0.65 + t * 1.3) * 0.12 + cos(p.x * 4.20 + p.y * 2.80 + t * 2.1) * 0.04);
    float dz = -(cos(p.x * 0.45 - p.y * 1.85 - t * 0.95) * 0.14 - sin(p.x * 2.80 - p.y * 3.50 + t * 1.6) * 0.05);
    vec3 wave_normal = normalize(vec3(dx, 1.0, dz));
    NORMAL = normalize((VIEW_MATRIX * vec4(wave_normal, 0.0)).xyz);
    
    // Water color: deep murky harbor water
    vec3 deep_water = vec3(0.022, 0.048, 0.062);
    vec3 shallow_water = vec3(0.045, 0.095, 0.115);
    float ripple = (w1 * w2 + w3 * 0.4) * 0.5 + 0.5;
    vec3 col = mix(deep_water, shallow_water, ripple * 0.5);
    
    // Subtle port chemical iridescence / oil sheen
    float oil_noise = noise(p * 0.45 + vec2(t * 0.05, -t * 0.03));
    if (oil_noise > 0.68) {
        float oil_t = (oil_noise - 0.68) / 0.32;
        vec3 rainbow = 0.5 + 0.5 * cos(oil_t * 6.28 + vec3(0.0, 2.0, 4.0));
        col = mix(col, rainbow * 0.22, oil_t * 0.45);
    }
    
    // Surface froth / foam flecks in troughs
    float foam = smoothstep(0.72, 0.88, abs(w3 * w4));
    col = mix(col, vec3(0.38, 0.52, 0.56), foam * 0.35);
    
    ALBEDO = col;
    ROUGHNESS = clamp(0.18 + foam * 0.45, 0.12, 0.85);
    METALLIC = 0.05;
    SPECULAR = 0.65;
}
