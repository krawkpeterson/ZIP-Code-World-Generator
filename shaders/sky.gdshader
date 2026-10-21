shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.16, 0.34, 0.68);
uniform vec3 horizon_color : source_color = vec3(0.78, 0.74, 0.66);
uniform vec3 ground_color : source_color = vec3(0.28, 0.24, 0.18);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.72);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.46;
uniform float cloud_scale = 0.42;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.4);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	float up = clamp(h, 0.0, 1.0);
	vec3 col = mix(horizon_color, zenith_color, pow(up, 0.48));
	col = mix(col, horizon_color * vec3(1.02, 0.98, 0.92), pow(1.0 - up, 4.0) * 0.16);
	float sun_d = 0.0;
	if (LIGHT0_ENABLED) {
		sun_d = dot(dir, LIGHT0_DIRECTION);
		float disk = smoothstep(0.9992, 0.99972, sun_d);
		float glow = pow(clamp(sun_d, 0.0, 1.0), 180.0);
		float wide = pow(clamp(sun_d, 0.0, 1.0), 6.0);
		col += sun_color * (disk * 1.6 + glow * 0.18);
		col += vec3(1.0, 0.62, 0.32) * wide * pow(1.0 - up, 1.6) * 0.42;
	}
	if (h > 0.015) {
		vec2 plane = dir.xz / max(h, 0.05);
		vec3 p = vec3(plane * cloud_scale, TIME * 0.012);
		float n = fbm(p);
		float ridge = fbm(p * 1.8 + vec3(4.0, 0.0, 2.0));
		float cover = smoothstep(0.58 - cloud_cover * 0.28, 0.78, n);
		float height_fade = smoothstep(0.02, 0.16, h) * (1.0 - smoothstep(0.82, 0.98, h));
		float shade = smoothstep(0.35, 0.8, ridge);
		vec3 cloud = mix(vec3(0.55, 0.58, 0.62), vec3(0.97, 0.97, 0.96), shade);
		cloud = mix(cloud, vec3(1.0, 0.78, 0.58), pow(clamp(sun_d, 0.0, 1.0), 4.0) * (1.0 - shade) * 0.45);
		col = mix(col, cloud, cover * height_fade);
	}
	if (h < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-h * 1.35, 0.0, 1.0));
	}
	COLOR = col;
}
