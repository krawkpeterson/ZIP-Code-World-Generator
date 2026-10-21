shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha, diffuse_burley, specular_disabled;

global uniform vec2 wind_dir;
global uniform float wind_gust;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float has_normal = 0.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.32;
uniform float height_ref = 7.0;
uniform float inflate = 0.01;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += NORMAL * inflate;
	float h = clamp(VERTEX.y / max(height_ref, 0.5), 0.0, 1.2);
	float bend = h * h * wind_gust * 0.16;
	float gust = sin(TIME * 1.35 + world_pos.x * 0.17 + world_pos.z * 0.11);
	float gust2 = sin(TIME * 0.62 + world_pos.z * 0.09);
	VERTEX.x += (gust * wind_dir.x + gust2 * 0.35) * bend;
	VERTEX.z += (gust * wind_dir.y + gust2 * 0.2) * bend;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	float mask = tex.a;
	if (tex.a > 0.97 && lum < 0.035) {
		mask = 0.0;
	}
	ALPHA = mask;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	vec3 alb = tex.rgb * tint;
	alb = pow(max(alb, vec3(0.001)), vec3(0.9));
	ALBEDO = alb;
	ROUGHNESS = 0.74;
	SPECULAR = 0.04;
	if (has_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = 0.55;
	}
	if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	NORMAL = normalize(mix(NORMAL, up, 0.48));
}

void light() {
	float ndotl = dot(NORMAL, LIGHT);
	float wrap = clamp((ndotl + 0.7) / 1.7, 0.0, 1.0);
	float shadow = mix(1.0, ATTENUATION, 0.42);
	float trans = pow(clamp(dot(VIEW, LIGHT), 0.0, 1.0), 1.6) * 0.28;
	DIFFUSE_LIGHT += (wrap * LIGHT_COLOR + trans * LIGHT_COLOR * vec3(0.62, 0.78, 0.42)) * shadow;
}
