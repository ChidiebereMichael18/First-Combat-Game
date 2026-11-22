shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 ice_color : source_color = vec4(0.55, 0.82, 1.0, 1.0);
uniform vec4 frost_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float refraction = 0.03;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;

varying vec3 local_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i + vec3(0.0, 0.0, 0.0)), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float frost = noise(local_pos * 5.0);
	float cracks = 1.0 - smoothstep(0.0, 0.05, abs(noise(local_pos * 3.5 + vec3(7.0)) - 0.5));
	vec3 behind = texture(screen_tex, SCREEN_UV + NORMAL.xy * refraction).rgb;
	vec3 col = mix(behind * ice_color.rgb * 1.3, ice_color.rgb, 0.4);
	col = mix(col, frost_color.rgb, clamp(fres * 0.6 + frost * 0.25, 0.0, 1.0));
	col += vec3(cracks) * 0.35;
	ALBEDO = col;
	ALPHA = clamp(0.5 + fres * 0.4 + frost * 0.2, 0.0, 0.95);
	ROUGHNESS = mix(0.05, 0.4, frost);
	SPECULAR = 1.0;
	EMISSION = ice_color.rgb * 0.15 + frost_color.rgb * fres * 0.3;
}