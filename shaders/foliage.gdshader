shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

global uniform vec2 wind_dir;
global uniform float wind_gust;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float has_normal = 0.0;
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.25;
uniform float height_ref = 1.0;
uniform float scissor : hint_range(0.0, 1.0) = 0.2;
uniform float roughness_val = 0.78;
uniform float lift = 0.012;
uniform float up_normal = 0.0;
uniform float clip_black = 0.0;
uniform float normal_up_bias = 0.22;

varying vec3 inst_col;

void vertex() {
	vec3 col = COLOR.rgb;
	if (dot(col, vec3(1.0)) < 0.04) {
		col = vec3(1.0);
	}
	inst_col = col;
	float phase = COLOR.a * 6.2831853;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = clamp(VERTEX.y / max(height_ref, 0.15), 0.0, 1.25);
	float gust = sin(TIME * wind_speed + world.x * 0.15 + world.z * 0.11 + phase);
	float gust2 = sin(TIME * wind_speed * 0.41 + world.z * 0.07 + phase * 1.7);
	float bend = wind_strength * wind_gust * h * h;
	VERTEX.x += (gust * wind_dir.x + gust2 * 0.25) * bend;
	VERTEX.z += (gust * wind_dir.y + gust2 * 0.45) * bend;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	float up_mix = clamp(up_normal, 0.0, 1.0);
	if (up_mix > 0.001) {
		vec3 world_n = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
		world_n = normalize(mix(world_n, vec3(0.0, 1.0, 0.0), up_mix));
		NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
	}
	ALPHA = tex.a;
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	if (clip_black > 0.5 && lum < 0.045) {
		ALPHA = 0.0;
	}
	ALPHA_SCISSOR_THRESHOLD = scissor;
	ALBEDO = tex.rgb * inst_col * mix(1.0, 0.88, clamp(UV.y, 0.0, 1.0));
	ROUGHNESS = roughness_val;
	SPECULAR = 0.05;
	if (has_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 0.55;
	}
	if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float bias = clamp(normal_up_bias, 0.0, 0.85);
	NORMAL = normalize(mix(NORMAL, up, bias));
	EMISSION = ALBEDO * lift * (1.0 - clamp(up_normal, 0.0, 1.0));
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	float wrap = clamp((ndotl + 0.32) / 1.32, 0.0, 1.0);
	float shadow = mix(1.0, ATTENUATION, 0.38);
	float trans = pow(clamp(dot(VIEW, LIGHT), 0.0, 1.0), 1.7) * 0.22;
	DIFFUSE_LIGHT += (wrap * LIGHT_COLOR + trans * LIGHT_COLOR * vec3(0.7, 0.8, 0.48)) * shadow;
}
