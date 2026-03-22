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
	var h: float = _biome_manager.sample_height(_noise, world_x, world_z)
	return GroundConstants.height_min + h * height_range

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
			var biome_weights: Array[float] = _biome_manager._biome_weights(world_x, world_z)
			cached_biome_weights[x * resolution + y] = biome_weights
			for i in range(biome_count):
				biome_weight_totals[i] += biome_weights[i]
			# Height: per-biome pow() blended with wide margin
			var h: float = _biome_manager.sample_height(_noise, world_x, world_z)
			heightmap.set_pixel(x, y, Color(GroundConstants.height_min + h * height_range, 0, 0, 1))

	# --- Determine dominant biome for the whole chunk ---
	var dominant_biome_idx: int = biome_weight_totals.find(biome_weight_totals.max())
	data.dominant_biome = _biome_manager.biomes[dominant_biome_idx]

	# --- Splatmap generation ---
	# Weight-map encoding: each RGBA channel = weight for one texture layer.
	# R = texture 0, G = texture 1, B = texture 2, A = texture 3.
	# Weights are normalised to sum to 1.0 so the shader can blend directly.
	if data.lod_tier == GroundConstants.LOD_LEVELS.FAR:
		# For far LOD, use LOD texture IDs for splatmap coloring
		for x in range(resolution):
			for y in range(resolution):
				var biome_weights: Array[float] = cached_biome_weights[x * resolution + y]
				var tex_weights: Array[float] = [0.0, 0.0, 0.0, 0.0]
				for i in range(biome_count):
					if biome_weights[i] < 0.01:
						continue
					var tex_id: int = (_biome_manager.biomes[i] as BiomeData).lod_texture_id
					if tex_id >= 0 and tex_id < 4:
						tex_weights[tex_id] += biome_weights[i]
				splatmap.set_pixel(x, y, _encode_weight_pixel(tex_weights))
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
				var tex_weights: Array[float] = [0.0, 0.0, 0.0, 0.0]
				for i in range(biome_count):
					var biome_weight := biome_weights[i]
					if biome_weight < 0.01:
						continue
					var biome_data: BiomeData = (_biome_manager.biomes[i] as BiomeData)
					var flat_w: float = biome_weight * (1.0 - steep_factor)
					var steep_w: float = biome_weight * steep_factor
					if flat_w > 0.001 and biome_data.flat_texture_id >= 0 and biome_data.flat_texture_id < 4:
						tex_weights[biome_data.flat_texture_id] += flat_w
					if steep_w > 0.001 and biome_data.steep_texture_id >= 0 and biome_data.steep_texture_id < 4:
						tex_weights[biome_data.steep_texture_id] += steep_w
				splatmap.set_pixel(x, y, _encode_weight_pixel(tex_weights))

	# --- Assign generated images to chunk data ---
	data.heightmap = heightmap
	data.splatmap = splatmap

## Encode per-texture weights into an RGBA Color.
## tex_weights[0] → R, tex_weights[1] → G, tex_weights[2] → B, tex_weights[3] → A.
## Weights are normalised so they sum to 1.0.
static func _encode_weight_pixel(tex_weights: Array[float]) -> Color:
	var total: float = tex_weights[0] + tex_weights[1] + tex_weights[2] + tex_weights[3]
	if total <= 0.0:
		# Fallback: 100% texture 1 (Grass)
		return Color(0.0, 1.0, 0.0, 0.0)
	var inv: float = 1.0 / total
	return Color(
		tex_weights[0] * inv,
		tex_weights[1] * inv,
		tex_weights[2] * inv,
		tex_weights[3] * inv
	)
