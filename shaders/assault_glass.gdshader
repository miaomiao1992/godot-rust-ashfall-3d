shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D baked_light : filter_linear, repeat_disable;
uniform vec3 atmosphere = vec3(1.0);
void fragment() {
	ALBEDO = texture(base_texture, UV).rgb * clamp(texture(baked_light, UV2).rgb * 1.65, vec3(0.10), vec3(1.5)) * atmosphere;
	ALPHA = 0.28;
}
