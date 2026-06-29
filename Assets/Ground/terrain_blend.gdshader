shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// All terrain textures packed into one array, indexed by layer.
uniform sampler2DArray terrain_textures : source_color, filter_linear_mipmap, repeat_enable;

// Per-chunk: top-3 texture indices per pixel (R=idx0, G=idx1, B=idx2).
uniform sampler2D splat_indices : filter_nearest, repeat_disable;

// Per-chunk: normalised weights for the 3 layers above (R=w0, G=w1, B=w2).
uniform sampler2D splat_weights : filter_nearest, repeat_disable;

// How many times the ground texture tiles across one chunk.
uniform float texture_scale : hint_range(0.01, 100.0) = 16.0;

// Blend one splatmap texel: sample up to 3 terrain layers weighted by splat weights.
vec3 sample_texel(vec2 uv, vec2 tile_uv) {
	vec3 idx = texture(splat_indices, uv).rgb;
	vec3 w   = texture(splat_weights, uv).rgb;
	float ws = w.r + w.g + w.b;
	if (ws < 0.001) return vec3(0.0);
	w /= ws;
	vec3 col = vec3(0.0);
	if (w.r > 0.001) col += texture(terrain_textures, vec3(tile_uv, round(idx.r * 255.0))).rgb * w.r;
	if (w.g > 0.001) col += texture(terrain_textures, vec3(tile_uv, round(idx.g * 255.0))).rgb * w.g;
	if (w.b > 0.001) col += texture(terrain_textures, vec3(tile_uv, round(idx.b * 255.0))).rgb * w.b;
	return col;
}

void fragment() {
	vec2 tile_uv = UV * texture_scale;

	// Manual bilinear: sample 4 nearest splatmap texels and blend by sub-texel position.
	// This correctly handles neighboring pixels with different texture indices.
	vec2 tex_size = vec2(textureSize(splat_indices, 0));
	vec2 texel_pos = UV * tex_size - 0.5;
	vec2 f = fract(texel_pos);
	vec2 base_uv = (floor(texel_pos) + 0.5) / tex_size;
	vec2 step = 1.0 / tex_size;

	vec3 c00 = sample_texel(base_uv,                        tile_uv);
	vec3 c10 = sample_texel(base_uv + vec2(step.x, 0.0),   tile_uv);
	vec3 c01 = sample_texel(base_uv + vec2(0.0, step.y),   tile_uv);
	vec3 c11 = sample_texel(base_uv + step,                 tile_uv);

	vec3 col = mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);

	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
