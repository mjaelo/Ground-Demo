extends RefCounted
class_name ChunkGenerator

## Generates heightmap, splatmap, and biome data for terrain chunks on worker threads.

var _noise: FastNoiseLite = null
var _biome_manager: BiomeManager = null

func initialize(noise: FastNoiseLite, biome_manager: BiomeManager) -> void:
	_noise = noise
	_biome_manager = biome_manager

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
	var biome_weight_totals: Array = range(biome_count).map(func(a): return 0.0)
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
				height_curve_weighted += _biome_manager.biomes[i].height_curve * biome_weights[i]
			# Generate height value using noise and curve
			var noise_val: float = _noise.get_noise_2d(world_x, world_z)
			noise_val = (noise_val + 1.0) * 0.5
			noise_val = pow(noise_val, height_curve_weighted)
			heightmap.set_pixel(x, y, Color(GroundConstants.height_min + noise_val * height_range, 0, 0, 1))

	# --- Determine dominant biome for the whole chunk ---
	var dominant_biome_idx: int = biome_weight_totals.find(biome_weight_totals.max())
	data.dominant_biome = _biome_manager.biomes[dominant_biome_idx]

	# --- Splatmap generation ---
	if data.lod_tier == GroundConstants.LOD_LEVELS.FAR:
		# For far LOD, use LOD texture IDs for splatmap coloring
		for x in range(resolution):
			for y in range(resolution):
				var biome_weights: Array[float] = cached_biome_weights[x * resolution + y]
				var red_weight: float = 0.0
				var green_weight: float = 0.0
				var blue_weight: float = 0.0
				for i in range(biome_count):
					if biome_weights[i] < 0.01:
						continue
					var biome_texture_id: int = _biome_manager.biomes[i].get_lod_texture_id()
					match biome_texture_id:
						0:
							red_weight += biome_weights[i]
						1:
							green_weight += biome_weights[i]
						2:
							blue_weight += biome_weights[i]
				splatmap.set_pixel(x, y, Color(red_weight, green_weight, blue_weight, 1.0))
	else:
		# For close/medium LOD, use slope to select between flat/steep textures
		var cell_size: float = float(chunk_size) / float(resolution - 1)
		for x in range(resolution):
			for y in range(resolution):
				var height_center: float = heightmap.get_pixel(x, y).r
				var height_right: float = height_center if x + 1 >= resolution else heightmap.get_pixel(x + 1, y).r
				var height_down: float = height_center if y + 1 >= resolution else heightmap.get_pixel(x, y + 1).r
				# Calculate slope in degrees
				var slope: float = rad_to_deg(acos(clampf(Vector3(-(height_right - height_center) / cell_size, 1.0, -(height_down - height_center) / cell_size).normalized().dot(Vector3.UP), -1.0, 1.0)))
				var biome_weights: Array[float] = cached_biome_weights[x * resolution + y]
				var red_weight: float = 0.0
				var green_weight: float = 0.0
				var blue_weight: float = 0.0
				for i in range(biome_count):
					var biome_weight := biome_weights[i]
					if biome_weight < 0.01:
						continue
					var biome_data: BiomeData = _biome_manager.biomes[i]
					var biome_texture_id: int = biome_data.steep_texture_id if slope > GroundConstants.STEEP_THRESHOLD else biome_data.flat_texture_id
					match biome_texture_id:
						0:
							red_weight += biome_weight
						1:
							green_weight += biome_weight
						2:
							blue_weight += biome_weight
				splatmap.set_pixel(x, y, Color(red_weight, green_weight, blue_weight, 1.0))

	# --- Assign generated images to chunk data ---
	data.heightmap = heightmap
	data.splatmap = splatmap
