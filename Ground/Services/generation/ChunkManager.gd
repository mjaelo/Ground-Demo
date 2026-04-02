extends RefCounted
class_name ChunkManager

## Generates heightmap, splatmap and biome data for terrain chunks.
var chunks: Dictionary = {} # Vector2i -> GroundChunk
var parent: GroundManager

const BIOME_WEIGHT_THRESHOLD: float = 0.01
const prominence_threshold: float = 0.1 # biome must cover at least 10% of pixels


func initialize( _parent: GroundManager) -> void:
	parent = _parent

# ── Chunk generation ───────────────────────────────────────────────────
## Returns a ChunkData populated with heightmap, splatmap, and dominant biomes.
func generate_chunk_data(loc: Vector2i, lod_tier: int) -> ChunkData:
	var data := ChunkData.new()
	data.loc = loc
	data.lod_tier = lod_tier
	var resolution: int = GroundConstants.close_resolution if lod_tier == GroundConstants.LOD_LEVELS.CLOSE else GroundConstants.far_resolution
	var chunk_size: int = GroundConstants.CHUNK_SIZE
	var base_x: float = data.loc.x * chunk_size
	var base_z: float = data.loc.y * chunk_size
	var inv_res: float = 1.0 / float(resolution - 1)

	# Cache biome weights for each pixel
	var biome_count: int = parent.biome_manager.biomes.size()
	var biome_weight_totals: Array = []
	biome_weight_totals.resize(biome_count)
	for i in range(biome_count):
		biome_weight_totals[i] = 0.0
	var cached_biome_weights: Array = []
	cached_biome_weights.resize(resolution * resolution)
	# --- Heightmap generation and biome weight accumulation ---
	var heightmap: Image = Image.create_empty(resolution, resolution, false, Image.FORMAT_RF)
	heightmap = get_heightmap(heightmap, cached_biome_weights, biome_count, resolution, inv_res, chunk_size, base_x, base_z,biome_weight_totals)
	# --- Determine prominent biomes: biomes whose total weight exceeds a threshold ---
	var total_weight: float = 0.0
	for w in biome_weight_totals:
		total_weight += w
	data.prominent_biomes = []
	for i in range(biome_count):
		var bd: BiomeData = parent.biome_manager.biomes[i]
		if bd.has_water:
			data.has_water = true
		if biome_weight_totals[i] >= total_weight * prominence_threshold:
			data.prominent_biomes.append(bd)
	# Splatmap generation (RGBA = texture weights)
	var splatmap: Image = Image.create_empty(resolution, resolution, false, Image.FORMAT_RGBA8)
	splatmap = get_splatmap(splatmap, heightmap, cached_biome_weights, biome_count, resolution, inv_res, chunk_size, base_x, base_z,lod_tier)
	# --- Assign generated images to chunk data ---
	data.heightmap = heightmap
	data.splatmap = splatmap
	return data

func create_chunk(chunk_data: ChunkData) -> GroundChunk:
	if chunks.has(chunk_data.loc):
		_remove_chunk(chunk_data.loc)
	return GroundChunk.build_chunk(chunk_data, parent.texture_manager.shader_material) # TODO move from GroundChunk

func get_heightmap(heightmap, cached_biome_weights, biome_count, resolution, inv_res, chunk_size, base_x, base_z,biome_weight_totals) ->Image:
	for x in range(resolution):
		var world_x: float = float(x) * inv_res * chunk_size + base_x
		for y in range(resolution):
			var world_z: float = float(y) * inv_res * chunk_size + base_z
			var biome_weights: Array[float] = parent.biome_manager._biome_weights(world_x, world_z)
			cached_biome_weights[x * resolution + y] = biome_weights
			for i in range(biome_count):
				biome_weight_totals[i] += biome_weights[i]
			# Height: sample via helper and convert to world Y (preserve existing behaviour)
			var h01: float =  parent.biome_manager.sample_height(parent.noise, world_x, world_z)
			var h_world: float = GroundConstants.HEIGHT_MIN + h01 * (GroundConstants.HEIGHT_MAX - GroundConstants.HEIGHT_MIN)
			heightmap.set_pixel(x, y, Color(h_world, 0, 0, 1))
	return heightmap
			
func get_splatmap(splatmap, heightmap, cached_biome_weights, biome_count, resolution, inv_res, chunk_size, base_x, base_z,lod_tier) ->Image:
	if lod_tier == GroundConstants.LOD_LEVELS.FAR:
		for x in range(resolution):
			for y in range(resolution):
				var biome_weights: Array[float] = cached_biome_weights[x * resolution + y]
				var tex_weights: Array[float] = [0.0, 0.0, 0.0, 0.0]
				for i in range(biome_count):
					if biome_weights[i] < BIOME_WEIGHT_THRESHOLD:
						continue
					var tex_id: int = (parent.biome_manager.biomes[i] as BiomeData).lod_texture_id
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
					height_right = sample_height(wx, wz)
				if y + 1 < resolution:
					height_down = heightmap.get_pixel(x, y + 1).r
				else:
					var wx: float = float(x) * inv_res * chunk_size + base_x
					var wz: float = float(y + 1) * inv_res * chunk_size + base_z
					height_down = sample_height(wx, wz)
				# Calculate slope in degrees (either fast gradient-based or original normal->acos)
				var slope := rad_to_deg(acos(clampf(Vector3(-(height_right - height_center) / cell_size, 1.0, -(height_down - height_center) / cell_size).normalized().dot(Vector3.UP), -1.0, 1.0)))
				# Smooth blend factor: 0 = fully flat texture, 1 = fully steep texture
				var steep_factor: float = clampf((slope - slope_lo) / (slope_hi - slope_lo), 0.0, 1.0)
				steep_factor = steep_factor * steep_factor * (3.0 - 2.0 * steep_factor) # smoothstep
				var biome_weights: Array[float] = cached_biome_weights[x * resolution + y]
				var tex_weights: Array[float] = [0.0, 0.0, 0.0, 0.0]
				for i in range(biome_count):
					var biome_weight := biome_weights[i]
					if biome_weight < BIOME_WEIGHT_THRESHOLD:
						continue
					var biome_data: BiomeData = (parent.biome_manager.biomes[i] as BiomeData)
					var flat_w: float = biome_weight * (1.0 - steep_factor)
					var steep_w: float = biome_weight * steep_factor
					if flat_w > 0.001 and biome_data.flat_texture_id >= 0 and biome_data.flat_texture_id < 4:
						tex_weights[biome_data.flat_texture_id] += flat_w
					if steep_w > 0.001 and biome_data.steep_texture_id >= 0 and biome_data.steep_texture_id < 4:
						tex_weights[biome_data.steep_texture_id] += steep_w
				splatmap.set_pixel(x, y, _encode_weight_pixel(tex_weights))
	return splatmap

func _encode_weight_pixel(tex_weights: Array[float]) -> Color:
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

# ── Chunk management ───────────────────────────────────────────────────
func update_distant_chunks(player_loc: Vector2i) -> void:
	# Remove chunks beyond far_radius that are also out of the frustum.
	var remove_r: float = GroundConstants.far_radius + GroundConstants.REMOVE_CHUNKS_MARGIN
	for chunk: GroundChunk in chunks.values():
		var loc := chunk.loc
		var dist: float = loc.distance_to(player_loc)
		if dist > remove_r:
			_remove_chunk(loc)
		if chunk.lod_tier == GroundConstants.LOD_LEVELS.CLOSE \
				and loc.distance_to(player_loc) > GroundConstants.close_radius + 1 \
				and chunk.are_decors_spawned and parent.decor_manager:
			parent.decor_manager.clear_decors(loc)
			chunk.are_decors_spawned = false

func _remove_chunk(loc: Vector2i) -> void:
	if !chunks.has(loc):
		return
	var chunk: GroundChunk = chunks[loc]
	chunks.erase(loc)
	chunk.destroy()
	parent.decor_manager.clear_decors(loc)

# ── Terrain sampling ─────────────────────────────────────────────────
func sample_height(world_x: float, world_z: float) -> float:
	var h: float = parent.biome_manager.sample_height(parent.noise, world_x, world_z)
	return GroundConstants.HEIGHT_MIN + h * (GroundConstants.HEIGHT_MAX - GroundConstants.HEIGHT_MIN)

## Thread-safe variant: uses a caller-owned BiomeManager/noise snapshot.
func sample_height_ts(world_x: float, world_z: float, noise: FastNoiseLite) -> float:
	var h: float = parent.biome_manager.sample_height(noise, world_x, world_z)
	return GroundConstants.HEIGHT_MIN + h * (GroundConstants.HEIGHT_MAX - GroundConstants.HEIGHT_MIN)

func sample_normal(world_x: float, world_z: float) -> Vector3:
	var bh := sample_height(world_x, world_z)
	var dx := sample_height(world_x + 1.0, world_z) - bh
	var dz := sample_height(world_x, world_z + 1.0) - bh
	return Vector3(-dx, 1.0, -dz).normalized()

## Thread-safe variant.
func sample_normal_ts(world_x: float, world_z: float, noise: FastNoiseLite) -> Vector3:
	var bh := sample_height_ts(world_x, world_z, noise)
	var dx := sample_height_ts(world_x + 1.0, world_z, noise) - bh
	var dz := sample_height_ts(world_x, world_z + 1.0, noise) - bh
	return Vector3(-dx, 1.0, -dz).normalized()
	
func get_height_at(world_pos: Vector3) -> float:
	var loc := GroundUtils.world_pos_to_chunk_loc(world_pos)
	var chunk: GroundChunk = chunks.get(loc, null)
	if chunk && chunk.heightmap:
		return GroundUtils.height_from_heightmap(chunk.heightmap, world_pos, loc)
	return sample_height(world_pos.x, world_pos.z)
