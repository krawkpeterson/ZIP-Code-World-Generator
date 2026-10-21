shader_type canvas_item;

void fragment() {
	vec2 uv = UV;
	float dusk = smoothstep(0.0, 1.0, uv.y);
	vec3 top = vec3(0.015, 0.02, 0.028);
	vec3 horizon = vec3(0.16, 0.09, 0.055);
	vec3 ground = vec3(0.03, 0.025, 0.02);
	vec3 col = mix(top, horizon, smoothstep(0.15, 0.72, uv.y));
	col = mix(col, ground, smoothstep(0.62, 1.0, uv.y));
	float ridge = sin(uv.x * 7.0 + 0.6) * 0.035 + sin(uv.x * 17.0) * 0.012;
	float hill = smoothstep(0.58 + ridge, 0.46 + ridge, uv.y);
	col = mix(col, vec3(0.05, 0.045, 0.04), hill * 0.85);
	float grain = fract(sin(dot(uv * vec2(1920.0, 1080.0) + TIME * 13.0, vec2(12.9898, 78.233))) * 43758.5453);
	col += (grain - 0.5) * 0.025;
	float vig = smoothstep(1.15, 0.25, length((uv - vec2(0.5, 0.45)) * vec2(1.15, 1.0)));
	col *= mix(0.55, 1.0, vig);
	COLOR = vec4(col, 1.0);
}
