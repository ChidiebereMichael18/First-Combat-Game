shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float streaks = 6.0;
uniform float speed = 8.0;

void fragment() {
	float spiral = sin(UV.x * TAU * streaks + UV.y * 10.0 - TIME * speed);
	float lines = smoothstep(0.2, 0.95, spiral);
	float fade = sin(UV.y * PI);
	ALBEDO = tint.rgb;
	ALPHA = lines * fade * 0.85;
}