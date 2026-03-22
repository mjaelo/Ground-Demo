shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// All terrain textures packed into one array, indexed by layer.
uniform sampler2DArray terrain_textures : source_color, filter_linear_mipmap, repeat_enable;

// Per-chunk splatmap (filter_nearest so encoded indices stay intact).
uniform sampler2D splatmap : filter_nearest, repeat_disable;

// How many times the ground texture tiles across one chunk
uniform float texture_scale : hint_range(0.01, 100.0) = 16.0;

// Chunk size in world units (used to compute UV from vertex position)
uniform float region_size = 256.0;

// Decode a single splatmap texel into a final terrain colour.
vec3 decode_splat(vec3 splat, vec2 tile_uv) {
	float idx_a = round(splat.r * 255.0) - 1.0;
	float idx_b = round(splat.g * 255.0) - 1.0;
	idx_a = max(idx_a, 0.0);
	idx_b = max(idx_b, 0.0);
	vec3 col_a = texture(terrain_textures, vec3(tile_uv, idx_a)).rgb;
	vec3 col_b = texture(terrain_textures, vec3(tile_uv, idx_b)).rgb;
	return mix(col_a, col_b, splat.b);
}

void fragment() {
	vec2 tile_uv = UV * texture_scale;

	// Manual bilinear interpolation of the splatmap:
	// Decode each of the 4 nearest texels independently (preserving
	// integer texture indices), then bilinearly blend the final colours.
	vec2 splat_size = vec2(textureSize(splatmap, 0));
	vec2 texel_pos  = UV * splat_size - 0.5;
	vec2 base       = floor(texel_pos);
	vec2 f          = texel_pos - base;

	vec2 uv00 = (base + vec2(0.5, 0.5)) / splat_size;
	vec2 uv10 = (base + vec2(1.5, 0.5)) / splat_size;
	vec2 uv01 = (base + vec2(0.5, 1.5)) / splat_size;
	vec2 uv11 = (base + vec2(1.5, 1.5)) / splat_size;

	vec3 c00 = decode_splat(texture(splatmap, uv00).rgb, tile_uv);
	vec3 c10 = decode_splat(texture(splatmap, uv10).rgb, tile_uv);
	vec3 c01 = decode_splat(texture(splatmap, uv01).rgb, tile_uv);
	vec3 c11 = decode_splat(texture(splatmap, uv11).rgb, tile_uv);

	ALBEDO = mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);

	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
