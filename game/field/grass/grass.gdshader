shader_type spatial;
render_mode cull_disabled;

// ---------------------------------------------------------------
// Pitch grass — ported from karl/godot-grass (Unlicense) and
// adapted for a mown football pitch:
//   - mown: blades are cut to `mow_height` (flat-ish top)
//   - wind disabled (static mown turf)
//   - player interaction enabled: blades bend away from
//     `object_position` within `object_radius` (driven by the player)
// ---------------------------------------------------------------

uniform float size_small = 0.2;
uniform float size_large = 0.6;

uniform float blade_bend = 0.5;

uniform vec3 color_small : source_color = vec3(0.3, 0.6, 0.1);
uniform vec3 color_large : source_color = vec3(0.9, 0.9, 0.2);

uniform sampler2D patch_noise;
uniform float patch_scale = 5.0;
varying float patch_factor;

// Mowing
uniform float mow_height = 0.5;          // 0..1 fraction of a blade that remains (in blade units)

// Player interaction (bend away)
uniform float object_radius = 1.0;
uniform vec3 object_position;

instance uniform float alpha = 1.0;

varying float bottom_to_top;
varying float cut_height;

void vertex() {
	// UV.y runs 0 (base) -> 1 (tip). bottom_to_top is largest at the ground.
	bottom_to_top = 1.0 - UV.y;
	cut_height = mow_height;

	// Mowing: clip so only the bottom `mow_height` fraction remains.
	VERTEX.y = min(VERTEX.y, cut_height);

	// General appearance
	VERTEX.z += blade_bend * pow(bottom_to_top, 2.0);

	patch_factor = texture(patch_noise, NODE_POSITION_WORLD.xz / patch_scale).r;
	VERTEX *= mix(size_small, size_large, patch_factor);

	// Bend away from the player object
	float object_distance = distance(object_position, NODE_POSITION_WORLD);
	float bend_away_strength = max(object_radius - object_distance, 0.0) / max(object_radius, 0.0001);
	vec2 bend_direction = normalize(object_position.xz - NODE_POSITION_WORLD.xz);
	if (object_distance < 0.0001) {
		bend_direction = vec2(0.0, 0.0);
	}
	mat4 inv_model = inverse(MODEL_MATRIX);
	float bend_strength = bend_away_strength * bottom_to_top;
	VERTEX.xz -= (inv_model * vec4(bend_direction.x, 0.0, bend_direction.y, 0.0)).xz
			* bend_strength;
	VERTEX.y -= bend_away_strength * bottom_to_top * 0.5;

	// Face / shadow trick so blades stay lit like upright grass.
	// NORMAL = mix(NORMAL, vec3(0.0, 1.0, 0.0), mix(1.0, bottom_to_top, alpha + 0.2));
	// Note: for a mown carpet we keep the mesh normals (3D blades), so no flatten op.
}

void fragment() {
	if (!FRONT_FACING) NORMAL = -NORMAL;

	AO = bottom_to_top;
	AO_LIGHT_AFFECT = mix(0.2, 1.0, alpha);

	ALBEDO = mix(color_small, color_large, patch_factor);
	BACKLIGHT = vec3(0.2);

	ROUGHNESS = 0.4;
	SPECULAR = 0.12;

	ALPHA = alpha;
	ALPHA_HASH_SCALE = 1.0;
}