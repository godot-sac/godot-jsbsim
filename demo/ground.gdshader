// Flat demo ground: grass patches with a 100 m / 1 km grid in world coordinates, so the lines stay fixed while
// the plane mesh follows the aircraft.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 grass_a : source_color = vec3(0.30, 0.40, 0.20);
uniform vec3 grass_b : source_color = vec3(0.36, 0.44, 0.24);
uniform vec3 line_color : source_color = vec3(0.86, 0.88, 0.80);

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// 1 on grid lines of the given spacing and half width (metres), antialiased.
float grid(vec2 p, float spacing, float half_width) {
	vec2 distance_to_line = abs(fract(p / spacing - 0.5) - 0.5) * spacing;
	vec2 aa = fwidth(p);
	vec2 line = 1.0 - smoothstep(vec2(half_width) - aa, vec2(half_width) + aa, distance_to_line);
	return max(line.x, line.y);
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 cell = floor(p / 500.0);
	float checker = mod(cell.x + cell.y, 2.0);
	vec3 grass = mix(grass_a, grass_b, checker);
	float distance = length(p - CAMERA_POSITION_WORLD.xz);
	float minor = grid(p, 100.0, 0.5) * (1.0 - smoothstep(1500.0, 5000.0, distance));
	float major = grid(p, 1000.0, 3.0);
	ALBEDO = mix(grass, line_color, max(minor * 0.5, major * 0.8));
	ROUGHNESS = 1.0;
}
