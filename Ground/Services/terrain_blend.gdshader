shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Terrain textures — assigned dynamically from texture_values.json by index.
// tex_0, tex_1, tex_2 correspond to texture indices 0, 1, 2.
uniform sampler2D tex_0 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_2 : source_color, filter_linear_mipmap, repeat_enable;

// Per-chunk splatmap: R = tex_0 weight, G = tex_1 weight, B = tex_2 weight
uniform sampler2D splatmap : filter_linear, repeat_disable;

// How many times the ground texture tiles across one region
uniform float texture_scale : hint_range(0.01, 100.0) = 16.0;

// Region size in world units (used to compute UV from vertex position)
uniform float region_size = 256.0;

void fragment() {
	vec2 splat_uv = UV;

	vec3 weights = texture(splatmap, splat_uv).rgb;
	float w_sum = weights.r + weights.g + weights.b;
	if (w_sum > 0.001) {
		weights /= w_sum;
	} else {
		weights = vec3(0.0, 1.0, 0.0);
	}

	vec2 tile_uv = UV * texture_scale;

	vec3 col_0 = texture(tex_0, tile_uv).rgb;
	vec3 col_1 = texture(tex_1, tile_uv).rgb;
	vec3 col_2 = texture(tex_2, tile_uv).rgb;

	ALBEDO = col_0 * weights.r + col_1 * weights.g + col_2 * weights.b;

	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
