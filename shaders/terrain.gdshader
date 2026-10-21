shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

global uniform vec2 wind_dir;
global uniform float wind_gust;

uniform sampler2D satellite : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D grass_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_rough : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_rough : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D duff_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D duff_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D duff_rough : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_rough : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float forest = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec3 dual(sampler2D tex, vec2 uv) {
	vec3 a = texture(tex, uv).rgb;
	vec2 r = vec2(uv.x * 0.82 + uv.y * 0.57, -uv.x * 0.57 + uv.y * 0.82);
	vec3 b = texture(tex, r * 2.35 + vec2(19.2, 6.4)).rgb;
	return mix(a, b, 0.42);
}

vec3 triplanar(sampler2D tex, vec3 world, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.0001);
	vec3 xs = texture(tex, world.zy * scale).rgb;
	vec3 ys = texture(tex, world.xz * scale).rgb;
	vec3 zs = texture(tex, world.xy * scale).rgb;
	return xs * w.x + ys * w.y + zs * w.z;
}

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = clamp(1.0 - world_n.y, 0.0, 1.0);
	float dist = length(VERTEX);
	float near = smoothstep(140.0, 8.0, dist);
	vec3 sat = textureLod(satellite, UV, mix(4.8, 1.6, near)).rgb;
	float sat_lum = max(dot(sat, vec3(0.299, 0.587, 0.114)), 0.025);
	vec3 sat_tint = sat / sat_lum;
	float moisture = clamp((sat.g - sat.r) * 3.4 + (sat.g - sat.b) * 0.6, -0.2, 1.0);

	vec2 uv = world.xz * 0.36;
	float macro = vnoise(world.xz * 0.012);
	float patch = vnoise(world.xz * 0.047 + vec2(11.0, 4.0));
	float grain = vnoise(world.xz * 0.19);
	float rock_w = smoothstep(0.22, 0.58, slope + (patch - 0.5) * 0.18);
	rock_w = clamp(rock_w, 0.0, 1.0);
	float grass_w = smoothstep(-0.02, 0.16, moisture + (patch - 0.48) * 0.22);
	grass_w *= (1.0 - rock_w);
	grass_w = clamp(grass_w + forest * 0.5 * (1.0 - rock_w), 0.0, 1.0);
	float duff_w = smoothstep(0.04, 0.2, moisture) * smoothstep(0.35, 0.7, patch);
	duff_w *= (1.0 - rock_w) * (1.0 - grass_w * 0.45);
	duff_w = clamp(duff_w + forest * 0.28 * (1.0 - rock_w), 0.0, 1.0);

	float anti_tile = 1.0 - smoothstep(90.0, 130.0, dist);
	bool use_grass = grass_w > 0.002 || forest > 0.002;
	bool use_duff = duff_w > 0.002 || forest > 0.002;
	vec3 dirt = texture(dirt_alb, uv).rgb;
	vec3 grass = vec3(0.0);
	vec3 duff = vec3(0.0);
	vec3 rock = vec3(0.0);
	float dirt_vis = (1.0 - grass_w) * (1.0 - forest * 0.62) * (1.0 - rock_w);
	if (anti_tile > 0.001 && dirt_vis > 0.04) {
		dirt = mix(dirt, dual(dirt_alb, uv), anti_tile);
	}
	if (use_grass) {
		vec2 guv = uv * 0.92 + vec2(4.0, 1.5);
		grass = texture(grass_alb, guv).rgb;
		if (anti_tile > 0.001) {
			grass = mix(grass, dual(grass_alb, guv), anti_tile);
		}
	}
	if (use_duff) {
		duff = texture(duff_alb, uv * 0.8 + vec2(8.0, 3.0)).rgb;
	}
	if (rock_w > 0.002) {
		rock = triplanar(rock_alb, world, world_n, 0.22);
	}
	vec3 dirt_far = texture(dirt_alb, world.xz * 0.042).rgb;

	vec3 alb = mix(dirt, grass, grass_w);
	alb = mix(alb, duff, clamp(duff_w, 0.0, 1.0));
	alb = mix(alb, grass, forest * 0.62);
	alb = mix(alb, duff, forest * 0.22);
	float ground_l = dot(alb, vec3(0.333));
	vec3 meadow = vec3(ground_l) * vec3(0.8, 0.96, 0.5) * 1.12;
	alb = mix(alb, meadow, forest * mix(0.5, 0.82, patch));
	alb = mix(alb, rock, rock_w);
	alb = mix(alb, dirt_far, smoothstep(45.0, 170.0, dist) * mix(0.58, 0.08, forest));
	alb *= mix(0.7, 1.2, macro);
	alb *= mix(0.92, 1.06, grain);
	alb *= mix(vec3(1.0), sat_tint, mix(0.48, 0.16, near) * (1.0 - forest * 0.7));
	alb = mix(alb, sat, smoothstep(70.0, 260.0, dist) * 0.28);
	float cloud = smoothstep(0.38, 0.78, vnoise(world.xz * 0.0032 + wind_dir * TIME * 0.06));
	alb *= mix(0.86, 1.0, mix(cloud, 1.0, 0.55)) * mix(0.94, 1.0, clamp(wind_gust, 0.0, 1.5));
	float cavity = mix(0.82, 1.0, smoothstep(0.05, 0.4, world_n.y));
	ALBEDO = alb * cavity;

	float detail = 1.0 - smoothstep(110.0, 140.0, dist);
	float rough = 0.92;
	vec3 nmap = vec3(0.5, 0.5, 1.0);
	if (detail > 0.001) {
		float grass_mix = 1.0 - (1.0 - grass_w) * (1.0 - forest * 0.62);
		if (dirt_vis > 0.04 || !use_grass) {
			rough = texture(dirt_rough, uv).r;
			nmap = texture(dirt_nor, uv).rgb;
		} else {
			grass_mix = 1.0;
		}
		if (use_grass) {
			rough = mix(rough, texture(grass_rough, uv * 0.92).r, grass_mix);
			nmap = mix(nmap, texture(grass_nor, uv * 0.92).rgb, grass_mix);
		}
		if (use_duff) {
			rough = mix(rough, texture(duff_rough, uv * 0.8).r, clamp(duff_w, 0.0, 1.0));
			nmap = mix(nmap, texture(duff_nor, uv * 0.8).rgb, clamp(duff_w, 0.0, 1.0) * 0.65);
		}
		if (rock_w > 0.002) {
			rough = mix(rough, texture(rock_rough, world.xz * 0.22).r, rock_w);
			nmap = mix(nmap, texture(rock_nor, world.xz * 0.22).rgb, rock_w);
		}
		rough = mix(0.92, rough, detail);
	}
	ROUGHNESS = clamp(rough, 0.55, 1.0);
	SPECULAR = mix(0.12, 0.22, rock_w);
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = mix(0.5, 1.45, smoothstep(90.0, 5.0, dist)) * detail;
}
