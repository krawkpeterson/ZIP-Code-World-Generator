shader_type spatial;
render_mode blend_mix, diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;
uniform vec3 deep_tint : source_color = vec3(0.45, 0.55, 0.52);
uniform float clarity = 0.35;

varying vec3 world_pos;
varying vec3 water_col;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(w.x * 0.42 + TIME * 0.85) * 0.035;
	wave += sin(w.z * 0.31 - TIME * 0.62 + w.x * 0.08) * 0.028;
	wave += sin((w.x + w.z) * 0.85 + TIME * 1.15) * 0.012;
	VERTEX.y += wave;
	world_pos = w + vec3(0.0, wave, 0.0);
	water_col = COLOR.rgb;
}

void fragment() {
	float dx = cos(world_pos.x * 0.42 + TIME * 0.85) * 0.42 * 0.035;
	dx += cos((world_pos.x + world_pos.z) * 0.85 + TIME * 1.15) * 0.85 * 0.012;
	float dz = cos(world_pos.z * 0.31 - TIME * 0.62 + world_pos.x * 0.08) * 0.31 * 0.028;
	dz += cos((world_pos.x + world_pos.z) * 0.85 + TIME * 1.15) * 0.85 * 0.012;
	vec3 n = normalize(vec3(-dx, 1.0, -dz));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, normalize(VIEW)), 0.0, 1.0), 4.0);
	float scene_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	scene_view.xyz /= max(scene_view.w, 0.0001);
	float water_depth = max(VERTEX.z - scene_view.z, 0.0);
	float shore = smoothstep(0.6, 0.02, water_depth);
	float foam_n = sin(world_pos.x * 1.7 + world_pos.z * 0.6 + TIME * 1.4);
	foam_n += sin(world_pos.z * 1.3 - world_pos.x * 0.9 - TIME * 0.9);
	foam_n += sin((world_pos.x + world_pos.z) * 2.3 + TIME * 0.7);
	float foam = shore * smoothstep(0.55, 0.9, foam_n * 0.1667 + 0.5);
	vec3 deep = water_col * deep_tint;
	deep = mix(deep * 0.45, deep, clamp(water_depth * 0.35, 0.0, 1.0));
	vec3 sky = vec3(0.62, 0.68, 0.72);
	vec3 alb = mix(deep, sky, fres * 0.78);
	alb = mix(alb, vec3(0.78, 0.8, 0.74), foam * 0.72);
	ALBEDO = alb;
	ROUGHNESS = mix(0.16, 0.04, fres);
	ROUGHNESS = mix(ROUGHNESS, 0.55, foam);
	SPECULAR = mix(0.55, 0.82, fres);
	METALLIC = 0.0;
	ALPHA = mix(0.55, 0.94, fres);
	ALPHA = mix(ALPHA, 0.72, shore * 0.45);
	ALPHA *= 0.72 + clarity * 0.4;
}
