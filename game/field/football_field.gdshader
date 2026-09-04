shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, depth_draw_opaque;

uniform sampler2D macro_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D turf_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grain_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_tex : filter_linear_mipmap, repeat_enable;

uniform vec4 grass_tint : source_color = vec4(0.42, 0.58, 0.22, 1.0);
uniform float turf_scale = 32.0;
uniform float macro_scale = 6.0;
uniform float detail_scale = 64.0;
uniform float grain_scale = 90.0;
uniform float stripe_freq = 11.0;
uniform float stripe_strength = 0.12;
uniform float roughness_base = 0.78;
uniform float normal_strength = 0.85;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;

	// Large-scale colour variation from the macro albedo map (pitch_alp).
	vec3 macro = texture(macro_tex, uv * macro_scale).rgb;

	// Mid-scale turf green from the tiling green map.
	vec3 turf_s = texture(turf_tex, uv * turf_scale).rgb;

	// Fine-scale pitch detail from the detail albedo map (pitch_detail_alp).
	vec3 det = texture(detail_tex, uv * detail_scale).rgb;

	// High-res grass detail from the 4096x2048 grain map. Its R and G
	// channels carry the crisp blade detail; B is flat blue filler, so use
	// R+G only to avoid a color cast.
	vec3 g3 = texture(grain_tex, uv * grain_scale).rgb;
	float grain = mix(g3.r, g3.g, 0.5);

	// Layer everything: macro gives large-scale variation, turf gives the
	// green base, detail adds mid-freq structure, grain adds blade crispness.
	vec3 grass = mix(macro, turf_s, 0.55);
	grass = mix(grass, det, 0.25);
	float blade = 1.0 + (grain - 0.5) * 0.20;
	grass *= blade;
	grass *= grass_tint.rgb * 1.35;

	// Mow stripes.
	float stripe = 0.5 + 0.5 * sin(world_pos.x * stripe_freq);
	stripe = mix(0.92, 1.06, stripe);
	grass *= mix(1.0, stripe, stripe_strength);

	vec3 nmap = texture(normal_tex, uv * turf_scale).rgb;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), nmap, normal_strength);
	NORMAL_MAP_DEPTH = 1.1;

	float rtex = texture(rough_tex, uv * turf_scale).r;
	ROUGHNESS = clamp(roughness_base + (1.0 - rtex) * 0.12, 0.62, 0.95);
	METALLIC = 0.0;
	SPECULAR = 0.12;
	ALBEDO = grass;
}