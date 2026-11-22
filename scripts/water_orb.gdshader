shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec4 deep_color : source_color = vec4(0.01, 0.18, 0.45, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.3, 0.75, 0.95, 1.0);
uniform vec4 foam_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float wobble = 0.12;
uniform float refraction = 0.02;
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
	
	// High-speed rushing current flow along the stream
	float flow = TIME * 10.0;
	
	// Create an organic water-whip spiral twist along the Z-axis
	float angle = VERTEX.z * 3.0 - flow;
	float c = cos(angle);
	float s = sin(angle);
	mat2 twist = mat2(vec2(c, -s), vec2(s, c));
	VERTEX.xy = twist * VERTEX.xy;
	
	// Procedural turbulence to warp the shape like splashing water
	float n = noise(VERTEX * 5.0 + vec3(0.0, 0.0, -flow * 0.5));
	VERTEX += NORMAL * (n - 0.5) * wobble * 2.5;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.8);
	
	// Multi-layered bubbling water currents
	float s1 = noise(local_pos * 12.0 + vec3(TIME * 2.0, -TIME * 4.0, TIME * 1.5));
	float s2 = noise(local_pos * 24.0 - vec3(TIME * 3.5, TIME * 1.0, TIME * 2.5));
	
	// Sharp, glowing foam peaks (classic water bending aesthetic)
	float caustic = smoothstep(0.45, 0.7, s1) * 0.8 + smoothstep(0.5, 0.75, s2) * 0.6;
	
	vec3 behind = texture(screen_tex, SCREEN_UV + NORMAL.xy * refraction * (0.5 + s1)).rgb;
	
	// Fluid color blending
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, clamp(fres * 0.8 + s1 * 0.4, 0.0, 1.0));
	col = mix(behind * col * 1.2, col, 0.35); // Lowered reflection mix for more transparency
	
	// Add churning foam and crest highlights
	col += foam_color.rgb * caustic * 0.7;
	col += foam_color.rgb * smoothstep(0.65, 0.9, fres) * 0.8;
	
	ALBEDO = col;
	ALPHA = clamp(0.5 + fres * 0.4 + caustic * 0.2, 0.0, 0.95);
	ROUGHNESS = 0.1;
	SPECULAR = 0.3; // Lowered specular so it looks like wet liquid instead of chrome/glass
	EMISSION = shallow_color.rgb * (fres * 0.3 + caustic * 0.4);
}