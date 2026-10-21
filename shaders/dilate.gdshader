shader_type canvas_item;

uniform sampler2D source : filter_nearest, repeat_disable;
uniform float radius = 3.0;

void fragment() {
	vec2 ts = 1.0 / vec2(textureSize(source, 0));
	vec4 best = texture(source, UV);
	if (best.a < 0.45) {
		bool hit = false;
		for (float y = -4.0; y <= 4.0; y += 1.0) {
			if (abs(y) > radius) {
				continue;
			}
			for (float x = -4.0; x <= 4.0; x += 1.0) {
				if (abs(x) > radius) {
					continue;
				}
				vec4 tap = texture(source, UV + vec2(x, y) * ts);
				if (tap.a > 0.5) {
					best = vec4(tap.rgb, 1.0);
					hit = true;
				}
			}
		}
		if (!hit) {
			best = vec4(0.0);
		}
	}
	COLOR = best;
}
