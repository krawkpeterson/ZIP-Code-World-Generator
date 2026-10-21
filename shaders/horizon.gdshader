shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

global uniform vec2 wind_dir;

uniform sampler2D dirt_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 biome = vec3(0.55, 0.48, 0.36);
uniform vec3 haze : source_color = vec3(0.74, 0.76, 0.78);

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = clamp(1.0 - world_n.y, 0.0, 1.0);
	float rock_w = smoothstep(0.08, 0.42, slope);
	float high = smoothstep(40.0, 520.0, world.y);
	vec2 uv = world.xz * 0.0065 + wind_dir * 0.0;
	vec3 dirt = texture(dirt_alb, uv).rgb;
	vec3 rock = texture(rock_alb, uv * 0.48).rgb;
	vec3 meso = mix(dirt, rock, max(rock_w, high * 0.7));
	float lum = max(dot(biome, vec3(0.3, 0.59, 0.11)), 0.12);
	vec3 tint = biome / lum;
	vec3 alb = meso * mix(vec3(1.0), tint, 0.62);
	float dist = length(VERTEX);
	float far = smoothstep(1800.0, 14000.0, dist);
	alb = mix(alb, haze, far * 0.48);
	ALBEDO = alb;
	ROUGHNESS = mix(0.97, 0.78, rock_w);
	SPECULAR = 0.06;
	NORMAL_MAP = texture(rock_nor, uv * 0.48).rgb;
	NORMAL_MAP_DEPTH = mix(0.2, 0.7, rock_w) * (1.0 - far);
}
