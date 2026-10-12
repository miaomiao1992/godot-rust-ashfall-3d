shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D baked_light : filter_linear, repeat_disable;
uniform bool masked = false;
uniform vec3 atmosphere = vec3(1.0);
void fragment() {
	vec4 base = texture(base_texture, UV);
	if (masked && base.a < 0.5) { discard; }
	vec3 lighting = texture(baked_light, UV2).rgb;
	// Preserve original face lightmaps rather than inventing uniform room lighting.
	ALBEDO = base.rgb * clamp(lighting * 1.65, vec3(0.10), vec3(1.5)) * atmosphere;
}
