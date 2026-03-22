extends RefCounted
class_name ChunkGenerator

## Generates heightmap, splatmap, and biome data for terrain chunks on worker threads.

var _noise: FastNoiseLite = null
var _biome_manager: BiomeManager = null

func initialize(noise: FastNoiseLite, biome_manager: BiomeManager) -> void:
	_noise = noise
	_biome_manager = biome_manager

## Compute the raw heightmap value at an arbitrary world position.
## Mirrors the logic inside _generate_heightmap_and_splatmap so that
## edge pixels can look one step beyond the chunk boundary.
func _sample_height(world_x: float, world_z: float, height_range: float) -> float:
	var bw: Array[float] = _biome_manager._biome_weights(world_x, world_z)
	var exponent: float = 0.0
	for i in bw.size():
		exponent += _biome_manager.biomes[i].get_height_exponent() * bw[i]
	var n: float = (_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
	n = pow(n, exponent)
	return GroundConstants.height_min + n * height_range

## Returns a ChunkData populated with heightmap, splatmap, and dominant biome.
## Safe to call from a worker thread.
func generate_chunk_data(loc: Vector2i, lod_tier: int) -> ChunkData:
	var resolution: int
	match lod_tier:
		GroundConstants.LOD_LEVELS.CLOSE:
			resolution = GroundConstants.close_resolution
		GroundConstants.LOD_LEVELS.MEDIUM:
			resolution = GroundConstants.medium_resolution
		_:
			resolution = GroundConstants.far_resolution

	var data := ChunkData.new()
	data.loc = loc
	data.lod_tier = lod_tier
	_generate_heightmap_and_splatmap(data, resolution)
	return data

func _generate_heightmap_and_splatmap(data: ChunkData, resolution: int) -> void:
	var chunk_size: int = GroundConstants.CHUNK_SIZE
	var base_x: float = data.loc.x * chunk_size
	var base_z: float = data.loc.y * chunk_size
	var inv_res: float = 1.0 / float(resolution - 1)
	var height_range: float = GroundConstants.height_max - GroundConstants.height_min
	var heightmap: Image = Image.create_empty(resolution, resolution, false, Image.FORMAT_RF)
	var splatmap: Image = Image.create_empty(resolution, resolution, false, Image.FORMAT_RGBA8)

	# Cache biome weights for each pixel
	var biome_count: int = _biome_manager.biomes.size()
	var biome_weight_totals: Array = range(biome_count).map(func(_a): return 0.0)
	var cached_biome_weights: Array = []
	cached_biome_weights.resize(resolution * resolution)

	# --- Heightmap generation and biome weight accumulation ---
	for x in range(resolution):
		var world_x: float = float(x) * inv_res * chunk_size + base_x
		for y in range(resolution):
			var world_z: float = float(y) * inv_res * chunk_size + base_z
			# Get biome weights for this pixel
			var biome_weights: Array[float] = _biome_manager._biome_weights(world_x, world_z)
			cached_biome_weights[x * resolution + y] = biome_weights
			# Accumulate biome weights for dominant biome detection
			for i in range(biome_count):
				biome_weight_totals[i] += biome_weights[i]
			# Compute weighted height curve
			var height_curve_weighted: float = 0.0
			for i in range(biome_count):
				height_curve_weighted += _biome_manager.biomes[i].get_height_exponent() * biome_weights[i]
			# Generate height value using noise and curve
			var noise_val: float = _noise.get_noise_2d(world_x, world_z)
			noise_val = (noise_val + 1.0) * 0.5
			noise_val = pow(noise_val, height_curve_weighted)
			heightmap.set_pixel(x, y, Color(GroundConstants.height_min + noise_val * height_range, 0, 0, 1))

	# --- Determine dominant biome for the whole chunk ---
	var dominant_biome_idx: int = biome_weight_totals.find(biome_weight_totals.max())
	data.dominant_biome = _biome_manager.biomes[dominant_biome_idx]

	# --- Splatmap generation ---
	# Splatmap encoding: R = tex_index_a / 255, G = tex_index_b / 255, B = blend (0=all A, 1=all B)
	if data.lod_tier == GroundConstants.LOD_LEVELS.FAR:
		# For far LOD, use LOD texture IDs for splatmap coloring
		for x in range(resolution):
			for y in range(resolution):
				var biome_weights: Array[float] = cached_biome_weights[x * resolution + y]
				var tex_weights: Dictionary = {}  # texture_id -> accumulated weight
				for i in range(biome_count):
					if biome_weights[i] < 0.01:
						continue
					var tex_id: int = _biome_manager.biomes[i].get_lod_texture_id()
					tex_weights[tex_id] = tex_weights.get(tex_id, 0.0) + biome_weights[i]
				splatmap.set_pixel(x, y, _encode_splatmap_pixel(tex_weights))
	else:
		# For close/medium LOD, use slope to blend between flat/steep textures
		var cell_size: float = float(chunk_size) / float(resolution - 1)
		var slope_lo: float = GroundConstants.STEEP_THRESHOLD - GroundConstants.STEEP_BLEND_RANGE
		var slope_hi: float = GroundConstants.STEEP_THRESHOLD + GroundConstants.STEEP_BLEND_RANGE
		for x in range(resolution):
			for y in range(resolution):
				var height_center: float = heightmap.get_pixel(x, y).r
				# For edge pixels, compute the neighbour height from noise
				# instead of clamping to center (which would give slope = 0).
				var height_right: float
				var height_down: float
				if x + 1 < resolution:
					height_right = heightmap.get_pixel(x + 1, y).r
				else:
					var wx: float = float(x + 1) * inv_res * chunk_size + base_x
					var wz: float = float(y) * inv_res * chunk_size + base_z
					height_right = _sample_height(wx, wz, height_range)
				if y + 1 < resolution:
					height_down = heightmap.get_pixel(x, y + 1).r
				else:
					var wx: float = float(x) * inv_res * chunk_size + base_x
					var wz: float = float(y + 1) * inv_res * chunk_size + base_z
					height_down = _sample_height(wx, wz, height_range)
				# Calculate slope in degrees
				var slope: float = rad_to_deg(acos(clampf(Vector3(-(height_right - height_center) / cell_size, 1.0, -(height_down - height_center) / cell_size).normalized().dot(Vector3.UP), -1.0, 1.0)))
				# Smooth blend factor: 0 = fully flat texture, 1 = fully steep texture
				var steep_factor: float = clampf((slope - slope_lo) / (slope_hi - slope_lo), 0.0, 1.0)
				steep_factor = steep_factor * steep_factor * (3.0 - 2.0 * steep_factor) # smoothstep
				var biome_weights: Array[float] = cached_biome_weights[x * resolution + y]
				var tex_weights: Dictionary = {}  # texture_id -> accumulated weight
				for i in range(biome_count):
					var biome_weight := biome_weights[i]
					if biome_weight < 0.01:
						continue
					var biome_data: BiomeData = _biome_manager.biomes[i]
					var flat_w: float = biome_weight * (1.0 - steep_factor)
					var steep_w: float = biome_weight * steep_factor
					if flat_w > 0.001:
						tex_weights[biome_data.flat_texture_id] = tex_weights.get(biome_data.flat_texture_id, 0.0) + flat_w
					if steep_w > 0.001:
						tex_weights[biome_data.steep_texture_id] = tex_weights.get(biome_data.steep_texture_id, 0.0) + steep_w
				splatmap.set_pixel(x, y, _encode_splatmap_pixel(tex_weights))

	# --- Assign generated images to chunk data ---
	data.heightmap = heightmap
	data.splatmap = splatmap

## Encode a {texture_id: weight} dictionary into a splatmap Color.
## Picks the two highest-weight textures and encodes:
##   R = (tex_index_a + 1) / 255.0,  G = (tex_index_b + 1) / 255.0,  B = blend (0 = all A, 1 = all B)
## IDs are stored +1 so that texture index 0 maps to byte 1 (avoiding all-zero pixels).
## The shader subtracts 1 when decoding.
static func _encode_splatmap_pixel(tex_weights: Dictionary) -> Color:
	if tex_weights.is_empty():
		# default: Grass (id 1) → encoded as (1+1)/255 = 2/255
		return Color(2.0 / 255.0, 2.0 / 255.0, 0.0, 1.0)

	# Find best and second-best texture by weight
	var best_id: int = -1
	var best_w: float = -1.0
	var second_id: int = -1
	var second_w: float = -1.0
	for tex_id in tex_weights:
		var w: float = tex_weights[tex_id]
		if w > best_w:
			second_id = best_id
			second_w = best_w
			best_id = tex_id
			best_w = w
		elif w > second_w:
			second_id = tex_id
			second_w = w

	if second_id < 0 or second_w <= 0.0:
		# Single texture, no blending
		var enc: float = float(best_id + 1) / 255.0
		return Color(enc, enc, 0.0, 1.0)

	# blend = proportion of second texture: second / (best + second)
	var total: float = best_w + second_w
	var blend: float = second_w / total
	return Color(float(best_id + 1) / 255.0, float(second_id + 1) / 255.0, blend, 1.0)
