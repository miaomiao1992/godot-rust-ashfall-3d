shader_type sky;
uniform vec3 sun_direction = vec3(0.4, 0.8, 0.2);
uniform vec3 moon_direction = vec3(-0.4, -0.8, -0.2);
uniform float daylight = 1.0;
uniform float sunset = 0.0;
const float EARTH_RADIUS = 6360000.0;
const float ATMOSPHERE_RADIUS = 6420000.0;
const vec3 BETA_R = vec3(5.8e-6, 13.5e-6, 33.1e-6);
const vec3 BETA_M = vec3(21.0e-6);

vec2 sphere_interval(vec3 origin, vec3 direction, float radius) {
	float b = dot(origin, direction);
	float c = dot(origin, origin) - radius * radius;
	float discriminant = b * b - c;
	if (discriminant < 0.0) { return vec2(-1.0); }
	float root = sqrt(discriminant);
	return vec2(-b - root, -b + root);
}

vec3 atmosphere_scatter(vec3 ray, vec3 light_direction) {
	vec3 origin = vec3(0.0, EARTH_RADIUS + 500.0, 0.0);
	float length_ray = sphere_interval(origin, ray, ATMOSPHERE_RADIUS).y;
	vec2 ground = sphere_interval(origin, ray, EARTH_RADIUS);
	if (ground.x > 0.0) { length_ray = min(length_ray, ground.x); }
	float step_length = length_ray / 8.0;
	vec2 optical_depth = vec2(0.0);
	vec3 accumulated_r = vec3(0.0);
	vec3 accumulated_m = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		vec3 point = origin + ray * ((float(i) + 0.5) * step_length);
		float altitude = max(0.0, length(point) - EARTH_RADIUS);
		vec2 density = exp(-vec2(altitude / 8000.0, altitude / 1200.0)) * step_length;
		optical_depth += density;
		float light_length = sphere_interval(point, light_direction, ATMOSPHERE_RADIUS).y;
		float light_step = light_length / 4.0;
		vec2 light_depth = vec2(0.0);
		bool shadow = false;
		for (int j = 0; j < 4; j++) {
			vec3 sample_point = point + light_direction * ((float(j) + 0.5) * light_step);
			float height = length(sample_point) - EARTH_RADIUS;
			if (height < 0.0) { shadow = true; break; }
			light_depth += exp(-vec2(height / 8000.0, height / 1200.0)) * light_step;
		}
		if (!shadow) {
			vec3 transmittance = exp(-(BETA_R * (optical_depth.x + light_depth.x) + BETA_M * 1.1 * (optical_depth.y + light_depth.y)));
			accumulated_r += transmittance * density.x;
			accumulated_m += transmittance * density.y;
		}
	}
	float cosine = dot(ray, light_direction);
	float phase_r = 3.0 / (16.0 * PI) * (1.0 + cosine * cosine);
	float g = 0.76;
	float phase_m = 3.0 / (8.0 * PI) * ((1.0 - g * g) * (1.0 + cosine * cosine)) / ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * cosine, 1.5));
	return 22.0 * (accumulated_r * BETA_R * phase_r + accumulated_m * BETA_M * phase_m);
}
void sky() {
	vec3 ray = normalize(EYEDIR);
	float elevation = clamp(ray.y, 0.0, 1.0);
	vec3 horizon = mix(vec3(0.055, 0.075, 0.14), vec3(0.58, 0.68, 0.78), daylight);
	vec3 zenith = mix(vec3(0.007, 0.012, 0.035), vec3(0.11, 0.28, 0.52), daylight);
	horizon = mix(horizon, vec3(0.66, 0.30, 0.17), clamp(sunset, 0.0, 1.0) * 0.7);
	vec3 night = mix(vec3(0.025, 0.035, 0.07), vec3(0.003, 0.006, 0.018), pow(elevation, 0.45));
	vec3 scattered = atmosphere_scatter(vec3(ray.x, max(ray.y, 0.002), ray.z), normalize(sun_direction));
	vec3 sky = night + scattered;
	float sun_dot = dot(ray, normalize(sun_direction));
	float moon_dot = dot(ray, normalize(moon_direction));
	float sun_disc = smoothstep(cos(0.032), cos(0.027), sun_dot);
	float moon_disc = smoothstep(cos(0.038), cos(0.034), moon_dot);
	float sun_up = smoothstep(-0.03, 0.04, sun_direction.y);
	float moon_up = smoothstep(-0.03, 0.04, moon_direction.y);
	sky += vec3(1.0, 0.62, 0.30) * pow(max(sun_dot, 0.0), 64.0) * 0.18 * sun_up;
	sky += vec3(1.0, 0.88, 0.64) * sun_disc * 4.0 * sun_up;
	float craters = 0.82 + 0.18 * sin(ray.x * 1200.0) * sin(ray.z * 900.0);
	sky += vec3(0.65, 0.75, 0.92) * moon_disc * craters * moon_up;
	sky += vec3(0.22, 0.30, 0.50) * pow(max(moon_dot, 0.0), 200.0) * 0.16 * moon_up;
	vec3 star_cell = floor(ray * 650.0);
	float star_hash = fract(sin(dot(star_cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	sky += vec3(0.48, 0.55, 0.70) * step(0.9994, star_hash) * (1.0 - daylight) * smoothstep(0.05, 0.4, elevation);
	COLOR = ray.y < 0.0 ? horizon * 0.45 : sky;
}
