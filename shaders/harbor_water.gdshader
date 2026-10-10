shader_type spatial;
varying vec3 world_position;

void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec2 p = world_position.xz;
    float a = p.x * 1.65 + p.y * 0.54 + TIME * 1.1;
    float b = p.x * 0.39 - p.y * 2.3 - TIME * 0.8;
    float c = p.x * 6.1 + p.y * 4.3 + TIME * 2.0;
    vec3 wave_normal = normalize(vec3(-cos(a) * 0.11 - cos(c) * 0.025, 1.0, -cos(b) * 0.10 - cos(c) * 0.025));
    NORMAL = normalize((VIEW_MATRIX * vec4(wave_normal, 0.0)).xyz);
    float ripple = sin(a) * sin(b) * 0.5 + 0.5;
    ALBEDO = mix(vec3(0.018, 0.050, 0.063), vec3(0.038, 0.091, 0.105), ripple * 0.45);
    ROUGHNESS = 0.30;
    METALLIC = 0.04;
    SPECULAR = 0.55;
}
