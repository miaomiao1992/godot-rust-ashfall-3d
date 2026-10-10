shader_type spatial;
varying vec3 world_position;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1,0)), f.x), mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec2 p = world_position.xz;
    float patches = noise(p * 0.32) * 0.65 + noise(p * 1.2) * 0.35;
    float grain = noise(p * 8.0);
    float cracks = 1.0 - smoothstep(0.0, 0.045, abs(noise(p * 2.7) - 0.48));
    ALBEDO = vec3(0.105, 0.112, 0.117) * (0.78 + patches * 0.45 + grain * 0.10) - vec3(cracks * 0.010);
    ROUGHNESS = 0.90;
}
