shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform sampler2D asphalt_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D gravel_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float line_mode = 1.0;
uniform float shoulder = 0.14;
uniform vec3 line_color : source_color = vec3(0.82, 0.8, 0.72);
uniform vec3 center_color : source_color = vec3(0.78, 0.58, 0.16);

void fragment() {
	float across = UV.x;
	float along = UV.y;
	vec2 auv = vec2(across * 2.4, along * 0.16);
	vec3 asphalt = texture(asphalt_alb, auv).rgb;
	asphalt *= 0.78;
	float wear = fract(sin(dot(floor(auv * vec2(3.0, 1.4)), vec2(19.1, 47.7))) * 13758.5);
	float lane = smoothstep(0.18, 0.32, abs(across - 0.5));
	asphalt *= 0.82 + wear * 0.14;
	asphalt *= mix(0.78, 1.0, lane);
	float crack = smoothstep(0.72, 0.78, fract(sin(floor(along * 0.37) * 91.7) * 0.5 + across * 3.0));
	asphalt = mix(asphalt, asphalt * vec3(0.72, 0.7, 0.66), crack);
	vec3 gravel = texture(gravel_alb, auv * vec2(1.6, 1.15)).rgb * 0.72;
	float inner = smoothstep(shoulder - 0.01, shoulder + 0.025, across);
	inner *= smoothstep(1.0 - shoulder + 0.01, 1.0 - shoulder - 0.025, across);
	float paved = clamp(inner, 0.0, 1.0);
	vec3 alb = mix(gravel, asphalt, paved);
	float edge_l = smoothstep(shoulder + 0.02, shoulder + 0.035, across) * smoothstep(shoulder + 0.055, shoulder + 0.04, across);
	float edge_r = smoothstep(1.0 - shoulder - 0.02, 1.0 - shoulder - 0.035, across) * smoothstep(1.0 - shoulder - 0.055, 1.0 - shoulder - 0.04, across);
	float edge = max(edge_l, edge_r) * paved;
	float center = smoothstep(0.485, 0.498, across) * smoothstep(0.515, 0.502, across);
	float dash = step(0.45, fract(along * 0.08));
	float paint = 0.0;
	vec3 paint_col = line_color;
	if (line_mode > 1.5) {
		paint = max(edge, center * dash);
		paint_col = mix(line_color, center_color, center * dash);
	} else if (line_mode > 0.5) {
		paint = edge;
	}
	alb = mix(alb, paint_col, paint * 0.92);
	ALBEDO = alb;
	ROUGHNESS = mix(0.94, mix(0.78, 0.42, paint), paved);
	SPECULAR = mix(0.08, 0.28, paint);
	NORMAL_MAP = mix(texture(gravel_nor, auv * 1.4).rgb, texture(asphalt_nor, auv).rgb, paved);
	NORMAL_MAP_DEPTH = mix(0.85, 0.45, paved);
}
