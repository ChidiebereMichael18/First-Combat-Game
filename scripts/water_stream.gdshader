shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec4 deep_color : source_color = vec4(0.12, 0.6, 0.95, 1.0);
uniform vec4 light_color : source_color = vec4(0.8, 0.96, 1.0, 1.0);
uniform float length_m = 4.0;
uniform float flow_speed = 4.0;
uniform float wiggle = 0.6;

varying float along;   // 0 at the head, 1 at the tail

void vertex() {
	along = clamp((VERTEX.y + length_m * 0.5) / length_m, 0.0, 1.0);
	float t = TIME * flow_speed;
	// lumpy thickness, so it has no fixed shape
	float lump = 1.0 + 0.35 * sin(along * 16.0 - t * 2.0) * sin(along * 5.0 + t);
	VERTEX.x *= lump;
	VERTEX.z *= lump;
	// the stream snakes from side to side
	VERTEX.x += sin(along * 9.0 - t) * wiggle * along;
	VERTEX.z += cos(along * 7.0 - t * 1.3) * wiggle * along;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float streak = sin(UV.x * 6.28318 * 6.0 + along * 14.0 - TIME * flow_speed * 2.0);
	float lines = smoothstep(0.35, 0.95, streak);
	vec3 col = mix(deep_color.rgb, light_color.rgb, clamp(lines * 0.7 + fres * 0.6, 0.0, 1.0));
	ALBEDO = col;
	EMISSION = light_color.rgb * (lines * 0.35 + fres * 0.3);
	ROUGHNESS = 0.1;
	SPECULAR = 0.8;
	ALPHA = clamp((1.0 - along) * 1.3, 0.0, 1.0) * (0.5 + lines * 0.35 + fres * 0.25);
}
