shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// All terrain textures packed into one array, indexed by layer.
uniform sampler2DArray terrain_textures : source_color, filter_linear_mipmap, repeat_enable;

// Per-chunk splatmap: each channel = weight for one texture layer.
// R = texture 0, G = texture 1, B = texture 2, A = texture 3.
// Using filter_linear so the GPU smoothly interpolates weights between texels.
uniform sampler2D splatmap : filter_linear, repeat_disable;

// Number of texture layers stored in terrain_textures (max 4 for RGBA encoding).
uniform int texture_count = 4;

// How many times the ground texture tiles across one chunk.
uniform float texture_scale : hint_range(0.01, 100.0) = 16.0;

// Chunk size in world units (used to compute UV from vertex position).
uniform float region_size = 256.0;

void fragment() {
	vec2 tile_uv = UV * texture_scale;

	// Sample the weight map — GPU bilinear gives us smooth interpolation for free.
	vec4 w = texture(splatmap, UV);

	// Normalise weights so they sum to 1 (guards against rounding drift).
	float w_sum = w.r + w.g + w.b + w.a;
	if (w_sum > 0.001) {
		w /= w_sum;
	} else {
		w = vec4(0.0, 1.0, 0.0, 0.0); // fallback: texture 1 (Grass)
	}

	// Blend all texture layers by their weights.
	vec3 col = vec3(0.0);
	if (texture_count > 0 && w.r > 0.001) col += texture(terrain_textures, vec3(tile_uv, 0.0)).rgb * w.r;
	if (texture_count > 1 && w.g > 0.001) col += texture(terrain_textures, vec3(tile_uv, 1.0)).rgb * w.g;
	if (texture_count > 2 && w.b > 0.001) col += texture(terrain_textures, vec3(tile_uv, 2.0)).rgb * w.b;
	if (texture_count > 3 && w.a > 0.001) col += texture(terrain_textures, vec3(tile_uv, 3.0)).rgb * w.a;

	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
