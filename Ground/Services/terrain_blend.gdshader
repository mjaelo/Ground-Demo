shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Textures loaded from texture_values.json TODO do not hardcode these textures
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_tex : source_color, filter_linear_mipmap, repeat_enable;

// Per-chunk splatmap: R = rock weight, G = grass weight, B = mud weight
uniform sampler2D splatmap  : filter_linear, repeat_disable;

// How many times the ground texture tiles across one region
uniform float texture_scale : hint_range(0.01, 100.0) = 16.0;

// Region size in world units (used to compute UV from vertex position)
uniform float region_size = 256.0;

void fragment() {
	// UV for splatmap lookup: 0-1 across the chunk
	vec2 splat_uv = UV;

	vec3 weights = texture(splatmap, splat_uv).rgb;
	// Normalise weights so they sum to 1 (handles edge cases)
	float w_sum = weights.r + weights.g + weights.b;
	if (w_sum > 0.001) {
		weights /= w_sum;
	} else {
		weights = vec3(0.0, 1.0, 0.0); // default to grass
	}

	// World-space tiling UV for the ground textures
	vec2 tile_uv = UV * texture_scale;

	vec3 rock_col  = texture(rock_tex,  tile_uv).rgb;
	vec3 grass_col = texture(grass_tex, tile_uv).rgb;
	vec3 mud_col   = texture(mud_tex,   tile_uv).rgb;

	ALBEDO = rock_col * weights.r + grass_col * weights.g + mud_col * weights.b;

	// Slight roughness variation by height
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
