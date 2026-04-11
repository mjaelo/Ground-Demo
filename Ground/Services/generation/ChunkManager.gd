extends RefCounted
class_name ChunkManager

## Generates heightmap, splatmap and biome data for terrain chunks.
var chunks: Dictionary = {} # Vector2i -> GroundChunk
var saved_chunk_data: Dictionary = {} # Vector2i -> ChunkData
var parent: GroundManager

func initialize( _parent: GroundManager) -> void:
	parent = _parent

# GENERATION
## Returns a ChunkData populated with heightmap, splatmap, and dominant biomes.
func get_chunk_thread_result(loc: Vector2i, lod_tier: int) -> ChunkThreadResult:
	var chunk_data := ChunkData.new()
	chunk_data.loc = loc
	var resolution: int = GroundConstants.CLOSE_RESOLUTION if lod_tier == GroundConstants.LOD_LEVELS.CLOSE else GroundConstants.FAR_RESOLUTION
	var base_x: float = chunk_data.loc.x * GroundConstants.CHUNK_SIZE
	var base_z: float = chunk_data.loc.y * GroundConstants.CHUNK_SIZE
	var inv_res: float = 1.0 / float(resolution - 1)

	var heightmap_and_weight_totals := get_heightmap_and_biome_weights(resolution, inv_res, base_x, base_z)
	var biome_weight_totals: Array = heightmap_and_weight_totals.biome_weight_totals
	var cached_biome_weights: Array = heightmap_and_weight_totals.cached_biome_weights
	
	chunk_data.heightmap = heightmap_and_weight_totals.heightmap
	chunk_data.splatmap = get_far_splatmap(cached_biome_weights, resolution) if lod_tier == GroundConstants.LOD_LEVELS.FAR else get_close_splatmap(cached_biome_weights, resolution, chunk_data.heightmap, inv_res, base_x, base_z)
	chunk_data.prominent_biome_ids = get_prominent_biomes_ids(biome_weight_totals)
	chunk_data.has_water = chunk_data.prominent_biome_ids.any(func(id: int) -> bool: return parent.biome_manager.biomes[id].has_water)
	
	return ChunkThreadResult.new().init(lod_tier, chunk_data)

func get_prominent_biomes_ids(biome_weight_totals: Array) -> Array[int]:
	# --- Determine prominent biomes: biomes whose total weight exceeds a threshold ---
	var total_weight: float = 0.0
	for weight in biome_weight_totals:
		total_weight += weight
	var prominent_biomes_ids:Array[int]= []
	for i in range(parent.biome_manager.biomes.size()):
		if biome_weight_totals[i] >= total_weight * GroundConstants.BIOME_PROMINENCE_TRESHOLD:
			prominent_biomes_ids.append(i)
	return prominent_biomes_ids

func get_heightmap_and_biome_weights(resolution: int, inv_res:float, base_x: float, base_z: float) ->Dictionary:
	# Cache biome weights for each pixel
	var biome_weight_totals: Array = [] # gets filled in get_heightmap
	biome_weight_totals.resize(parent.biome_manager.biomes.size())
	for i in range(parent.biome_manager.biomes.size()):
		biome_weight_totals[i] = 0.0
	var cached_biome_weights: Array = []
	cached_biome_weights.resize(resolution * resolution)
	
	# --- Heightmap generation and biome weight accumulation ---
	var heightmap: Image = Image.create_empty(resolution, resolution, false, Image.FORMAT_RF)
	var chunk_size: int = GroundConstants.CHUNK_SIZE
	var biome_count: int = parent.biome_manager.biomes.size()
	for x in range(resolution):
		var world_x: float = float(x) * inv_res * chunk_size + base_x
		for y in range(resolution):
			var world_z: float = float(y) * inv_res * chunk_size + base_z
			var biome_scores: Array[float] = parent.biome_manager._compute_biome_scores(world_x, world_z)
			var biome_weights: Array[float] = parent.biome_manager._weights_with_sharpness(biome_scores, GroundConstants.TEXTURE_BLEND_SHARPNESS)
			cached_biome_weights[x * resolution + y] = biome_weights
			for i in range(biome_count):
				biome_weight_totals[i] += biome_weights[i]
			var h_world: float = parent.biome_manager.get_height_at(world_x, world_z, biome_scores)
			heightmap.set_pixel(x, y, Color(h_world, 0, 0, 1))
	return {"heightmap": heightmap, "biome_weight_totals": biome_weight_totals, "cached_biome_weights": cached_biome_weights}
			
func get_close_splatmap(cached_biome_weights: Array, resolution: int, heightmap:Image, inv_res:float, base_x: float, base_z: float) ->Image:
	# For close LOD, use slope to blend between flat/steep textures
	var splatmap: Image = Image.create_empty(resolution, resolution, false, Image.FORMAT_RGBA8)
	var chunk_size: int = GroundConstants.CHUNK_SIZE
	var cell_size: float = float(chunk_size) / float(resolution - 1)
	var slope_lo: float = GroundConstants.STEEP_THRESHOLD - GroundConstants.STEEP_BLEND_RANGE
	var slope_hi: float = GroundConstants.STEEP_THRESHOLD + GroundConstants.STEEP_BLEND_RANGE
	for x in range(resolution):
		for y in range(resolution):
			var height_center: float = heightmap.get_pixel(x, y).r
			var height_right: float
			var height_down: float
			if x + 1 < resolution:
				height_right = heightmap.get_pixel(x + 1, y).r
			else:
				var wx: float = float(x + 1) * inv_res * chunk_size + base_x
				var wz: float = float(y) * inv_res * chunk_size + base_z
				height_right = parent.biome_manager.get_height_at(wx, wz)
			if y + 1 < resolution:
				height_down = heightmap.get_pixel(x, y + 1).r
			else:
				var wx: float = float(x) * inv_res * chunk_size + base_x
				var wz: float = float(y + 1) * inv_res * chunk_size + base_z
				height_down = parent.biome_manager.get_height_at(wx, wz)
			# Calculate slope in degrees (either fast gradient-based or original normal->acos)
			var slope := rad_to_deg(acos(clampf(Vector3(-(height_right - height_center) / cell_size, 1.0, -(height_down - height_center) / cell_size).normalized().dot(Vector3.UP), -1.0, 1.0)))
			# Smooth blend factor: 0 = fully flat texture, 1 = fully steep texture
			var steep_factor: float = clampf((slope - slope_lo) / (slope_hi - slope_lo), 0.0, 1.0)
			steep_factor = steep_factor * steep_factor * (3.0 - 2.0 * steep_factor) # smoothstep
			var biome_weights: Array[float] = cached_biome_weights[x * resolution + y]
			var texture_weights: Array[float] = [0.0, 0.0, 0.0, 0.0]
			for i in range(parent.biome_manager.biomes.size()):
				var biome_weight := biome_weights[i]
				if biome_weight < GroundConstants.BIOME_WEIGHT_THRESHOLD:
					continue
				var biome_data: BiomeData = (parent.biome_manager.biomes[i] as BiomeData)
				var flat_w: float = biome_weight * (1.0 - steep_factor)
				var steep_w: float = biome_weight * steep_factor
				if flat_w > 0.001 and biome_data.flat_texture_id >= 0 and biome_data.flat_texture_id < 4:
					texture_weights[biome_data.flat_texture_id] += flat_w
				if steep_w > 0.001 and biome_data.steep_texture_id >= 0 and biome_data.steep_texture_id < 4:
					texture_weights[biome_data.steep_texture_id] += steep_w
			splatmap.set_pixel(x, y, convert_weights_to_color(texture_weights))
	return splatmap

func get_far_splatmap(cached_biome_weights: Array, resolution: int) ->Image:
	var splatmap: Image = Image.create_empty(resolution, resolution, false, Image.FORMAT_RGBA8)
	for x in range(resolution):
		for y in range(resolution):
			var biome_weights: Array[float] = cached_biome_weights[x * resolution + y]
			var tex_weights: Array[float] = [0.0, 0.0, 0.0, 0.0]
			for i in range(parent.biome_manager.biomes.size()):
				if biome_weights[i] < GroundConstants.BIOME_WEIGHT_THRESHOLD:
					continue
				var tex_id: int = (parent.biome_manager.biomes[i] as BiomeData).lod_texture_id
				if tex_id >= 0 and tex_id < 4:
					tex_weights[tex_id] += biome_weights[i]
			splatmap.set_pixel(x, y, convert_weights_to_color(tex_weights))
	return splatmap

func convert_weights_to_color(tex_weights: Array[float]) -> Color:
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

# MANAGEMENT 
func update_distant_chunks(player_loc: Vector2i) -> void:
	# Remove chunks beyond far_radius that are also out of the frustum.
	var remove_r: float = GroundConstants.FAR_RADIUS + GroundConstants.REMOVE_CHUNKS_MARGIN
	for chunk: GroundChunk in chunks.values():
		var loc := chunk.data.loc
		var dist: float = loc.distance_to(player_loc)
		if dist > remove_r:
			_remove_chunk(loc)
		elif chunk.lod_tier == GroundConstants.LOD_LEVELS.CLOSE \
				and dist > GroundConstants.CLOSE_RADIUS + 1 \
				and chunk.are_decors_spawned and parent.decor_manager:
			parent.decor_manager.clear_decors(loc, chunk.decor_nodes)
			chunk.decor_nodes = []
			chunk.are_decors_spawned = false

func _remove_chunk(loc: Vector2i) -> void:
	if !chunks.has(loc):
		return
	var chunk: GroundChunk = chunks[loc]
	chunks.erase(loc)
	if is_instance_valid(chunk.mesh_instance):
		chunk.mesh_instance.queue_free()
	parent.decor_manager.clear_decors(loc, chunk.decor_nodes)
	chunk.decor_nodes = []
	chunk.mesh_instance = null
	chunk.collision_body = null

# SAMPLING
func sample_normal(world_x: float, world_z: float) -> Vector3:
	var world_pos := Vector3(world_x, 0 , world_z)
	var loc := GroundUtils.world_pos_to_chunk_loc(world_pos)
	var chunk: GroundChunk = chunks.get(loc, null)
	if chunk && chunk.data.heightmap:
		var bh :float= GroundUtils.height_from_heightmap(chunk.data.heightmap, world_x, world_z, loc)
		var dx :float= GroundUtils.height_from_heightmap(chunk.data.heightmap, world_x+1.0,  world_z, loc) - bh
		var dz :float= GroundUtils.height_from_heightmap(chunk.data.heightmap, world_x, world_z+1.0, loc) - bh
		return Vector3(-dx, 1.0, -dz).normalized()
	var bh2 :float= parent.biome_manager.get_height_at(world_x, world_z)
	var dx2 :float= parent.biome_manager.get_height_at(world_x + 1.0, world_z) - bh2
	var dz2 :float= parent.biome_manager.get_height_at(world_x, world_z + 1.0) - bh2
	return Vector3(-dx2, 1.0, -dz2).normalized()

func get_height_at(world_pos: Vector3) -> float:
	var loc := GroundUtils.world_pos_to_chunk_loc(world_pos)
	var chunk: GroundChunk = chunks.get(loc, null)
	if chunk && chunk.data.heightmap:
		return GroundUtils.height_from_heightmap(chunk.data.heightmap, world_pos.x, world_pos.z, loc)
	return parent.biome_manager.get_height_at(world_pos.x, world_pos.z)
