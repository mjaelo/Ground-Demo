extends RefCounted
class_name GroundManager

## Coordinates terrain chunk streaming, threading, and decor placement.
## Delegates generation to ChunkGenerator, boundary to PlayerBoundary.

signal initial_load_complete

# ── Adaptive throughput ───────────────────────────────────────────────
var max_chunks_per_frame: int = GroundConstants.STARTUP_CHUNKS_PER_FRAME
var max_concurrent_threads: int = GroundConstants.STARTUP_THREADS
var max_far_per_frame: int = GroundConstants.STARTUP_FAR_PER_FRAME
var max_far_threads: int = GroundConstants.STARTUP_FAR_THREADS
var _initial_load_done: bool = false

# ── Internal state ────────────────────────────────────────────────────
var _chunks: Dictionary = {} # Vector2i -> GroundChunk
var _generating: Dictionary = {} # Vector2i -> Thread
var _generating_far: Dictionary = {} # Vector2i -> Thread
var _generating_decor: Dictionary = {} # Vector2i -> Thread
var pending_chunk_results: Array[ChunkData]
var pending_far_results: Array[ChunkData]
var pending_decor_results: Array[DecorThreadResult]
var _stream_timer: float = 0.0

# ── References / sub-systems ──────────────────────────────────────────
var _parent: Ground = null
var _player: Player = null
var _shader_material: ShaderMaterial = null
var _chunk_generator: ChunkGenerator = null
var _player_boundary: PlayerBoundary = null

# ── Terrain sampling (inlined from former TerrainSampler) ─────────────
var _noise: FastNoiseLite = null
var _biome_manager: BiomeManager = null

var loaded_textures: = []

func initialize(parent: Ground, player: CharacterBody3D) -> void:
	_parent = parent
	_player = player
	_noise = parent._noise
	_biome_manager = parent._biome_manager

	_chunk_generator = ChunkGenerator.new()
	_chunk_generator.initialize(_noise, _biome_manager)

	_shader_material = _build_shader_material()
	_initial_load_done = false
	max_chunks_per_frame = GroundConstants.STARTUP_CHUNKS_PER_FRAME
	max_concurrent_threads = GroundConstants.STARTUP_THREADS
	max_far_per_frame = GroundConstants.STARTUP_FAR_PER_FRAME
	max_far_threads = GroundConstants.STARTUP_FAR_THREADS

	_player_boundary = PlayerBoundary.new()
	_player_boundary.initialize(player, _chunks)

# ── Terrain sampling ─────────────────────────────────────────────────

func sample_height(world_x: float, world_z: float) -> float:
	var h := _noise.get_noise_2d(world_x, world_z)
	h = (h + 1.0) * 0.5
	h = pow(h, _biome_manager.get_height_curve(world_x, world_z))
	return GroundConstants.height_min + h * (GroundConstants.height_max - GroundConstants.height_min)

func sample_normal(world_x: float, world_z: float) -> Vector3:
	var bh := sample_height(world_x, world_z)
	var dx := sample_height(world_x + 1.0, world_z) - bh
	var dz := sample_height(world_x, world_z + 1.0) - bh
	return Vector3(-dx, 1.0, -dz).normalized()

# ── Public API ────────────────────────────────────────────────────────

func tick(delta: float) -> void:
	_collect_finished_threads()
	_collect_finished_far_threads()
	_collect_finished_decor_threads()
	_apply_far_results()
	_apply_results()
	_apply_decor_results()
	_player_boundary.update()
	_check_initial_load()
	_stream_timer += delta
	if _stream_timer >= GroundConstants.STREAM_CHECK_INTERVAL:
		_stream_timer = 0.0
		_update_visible_chunks()

func get_height_at(world_pos: Vector3) -> float:
	var loc := GroundUtils.world_pos_to_chunk_loc(world_pos)
	var chunk: GroundChunk = _chunks.get(loc, null)
	if chunk && chunk.heightmap:
		return GroundUtils.height_from_heightmap(chunk.heightmap, world_pos, loc)
	return sample_height(world_pos.x, world_pos.z)

# ── Initial load check ────────────────────────────────────────────────

func _check_initial_load() -> void:
	if _initial_load_done:
		return
	var player_loc := GroundUtils.world_pos_to_chunk_loc(_player.global_transform.origin)
	var cr := GroundConstants.close_radius
	for x in range(player_loc.x - cr, player_loc.x + cr + 1):
		for y in range(player_loc.y - cr, player_loc.y + cr + 1):
			var loc := Vector2i(x, y)
			if loc.distance_to(player_loc) > cr:
				continue
			var chunk: GroundChunk = _chunks.get(loc, null)
			if !chunk || chunk.lod_tier > GroundConstants.LOD_LEVELS.CLOSE:
				return
	_initial_load_done = true
	max_chunks_per_frame = GroundConstants.STEADY_CHUNKS_PER_FRAME
	max_concurrent_threads = GroundConstants.STEADY_THREADS
	max_far_per_frame = GroundConstants.STEADY_FAR_PER_FRAME
	max_far_threads = GroundConstants.STEADY_FAR_THREADS
	initial_load_complete.emit()

# ── Chunk streaming ───────────────────────────────────────────────────

func _update_visible_chunks() -> void:
	if not _parent or not _parent.is_inside_tree():
		return
	if not _player.is_inside_tree():
		return
	var player_loc := GroundUtils.world_pos_to_chunk_loc(_player.global_transform.origin)
	var far_r := GroundConstants.far_radius
	var med_r := GroundConstants.medium_radius
	var cls_r := GroundConstants.close_radius

	# 1) FAR chunks — sorted closest first
	var far_needed: Array[FarChunkRequest]
	for x in range(player_loc.x - far_r, player_loc.x + far_r + 1):
		for y in range(player_loc.y - far_r, player_loc.y + far_r + 1):
			var loc := Vector2i(x, y)
			var dist: float = loc.distance_to(player_loc)
			if dist > far_r: continue
			if _chunks.has(loc): continue
			if _generating_far.has(loc) or _generating.has(loc): continue
			far_needed.push_back(FarChunkRequest.new().init(loc, dist))
	far_needed.sort_custom(func(a, b): return a.dist < b.dist)
	var far_slots: int = max_far_threads - _generating_far.size()
	var far_started := 0
	for item in far_needed:
		if far_started >= max_far_per_frame or far_slots <= 0: break
		_start_thread(_generating_far, item.loc, GroundConstants.LOD_LEVELS.FAR)
		far_started += 1; far_slots -= 1

	# 2) CLOSE / MEDIUM upgrades — sorted by tier then distance
	var upgrades: Array[ChunkUpgradeRequest]
	for x in range(player_loc.x - med_r, player_loc.x + med_r + 1):
		for y in range(player_loc.y - med_r, player_loc.y + med_r + 1):
			var loc := Vector2i(x, y)
			var dist: float = loc.distance_to(player_loc)
			if dist > med_r: continue
			var desired: GroundConstants.LOD_LEVELS = GroundConstants.LOD_LEVELS.CLOSE if dist <= cls_r else GroundConstants.LOD_LEVELS.MEDIUM
			var chunk: GroundChunk = _chunks.get(loc, null)
			if chunk && chunk.lod_tier <= desired: continue
			if _generating.has(loc) or _generating_far.has(loc): continue
			upgrades.push_back(ChunkUpgradeRequest.new().init(loc, desired, dist))
	upgrades.sort_custom(func(a, b):
		if a.tier != b.tier: return a.tier < b.tier
		return a.dist < b.dist)
	var slots: int = max_concurrent_threads - _generating.size()
	for item in upgrades:
		if slots <= 0: break
		_start_thread(_generating, item.loc, item.tier)
		slots -= 1

	# 3) Unload distant chunks
	var to_remove: Array[Vector2i] = []
	for loc in _chunks.keys():
		if loc.distance_to(player_loc) > far_r + GroundConstants.UNLOAD_MARGIN:
			to_remove.push_back(loc)
	for loc in to_remove:
		_remove_chunk(loc)

	# 4) Clean decor from CLOSE chunks that moved beyond close radius
	for loc in _chunks.keys():
		var chunk: GroundChunk = _chunks[loc]
		if chunk.lod_tier == GroundConstants.LOD_LEVELS.CLOSE and loc.distance_to(player_loc) > cls_r + 1:
			if chunk.mesh_assets_spawned and _parent._mesh_placement_manager:
				_parent._mesh_placement_manager.clear_scene_meshes(loc)
				chunk.mesh_assets_spawned = false

	# 5) Retry decor generation for CLOSE chunks that haven't spawned yet
	if _parent._mesh_placement_manager:
		for loc in _chunks.keys():
			var chunk: GroundChunk = _chunks[loc]
			if chunk.lod_tier == GroundConstants.LOD_LEVELS.CLOSE and not chunk.mesh_assets_spawned:
				if loc.distance_to(player_loc) <= cls_r + 1:
					if not _generating_decor.has(loc) and _generating_decor.size() < GroundConstants.MAX_DECOR_THREADS:
						_start_decor_thread(loc)

# ── Thread helpers ────────────────────────────────────────────────────

func _start_thread(dict: Dictionary, loc: Vector2i, lod_tier: int) -> void:
	var thread := Thread.new()
	dict[loc] = thread
	if thread.start(_chunk_generator.generate_chunk_data.bind(loc, lod_tier)) != OK:
		dict.erase(loc)

func _start_decor_thread(loc: Vector2i) -> void:
	var thread := Thread.new()
	_generating_decor[loc] = thread
	var chunk_size := GroundConstants.CHUNK_SIZE
	var callable := func() -> DecorThreadResult:
		var region_origin := Vector3(loc.x * chunk_size + chunk_size * 0.5, 0, loc.y * chunk_size + chunk_size * 0.5)
		var tmap: Dictionary = _parent._mesh_placement_manager.generate_transforms(
			region_origin,
			chunk_size,
			sample_height,
			sample_normal,
			_biome_manager)
		return DecorThreadResult.new().init(loc, tmap)
	if thread.start(callable) != OK:
		_generating_decor.erase(loc)

func _collect_finished_chunk(dict: Dictionary, results: Array) -> void:
	var done: Array[Vector2i] = []
	for loc in dict.keys():
		if not dict[loc].is_alive():
			done.push_back(loc)
	for loc in done:
		var result = dict[loc].wait_to_finish()
		dict.erase(loc)
		if result is ChunkData:
			results.push_back(result)

func _collect_finished_decor(dict: Dictionary, results: Array) -> void:
	var done: Array[Vector2i] = []
	for loc in dict.keys():
		if not dict[loc].is_alive():
			done.push_back(loc)
	for loc in done:
		var result = dict[loc].wait_to_finish()
		dict.erase(loc)
		if result is DecorThreadResult:
			results.push_back(result)

func _collect_finished_threads() -> void:
	_collect_finished_chunk(_generating, pending_chunk_results)

func _collect_finished_far_threads() -> void:
	_collect_finished_chunk(_generating_far, pending_far_results)

func _collect_finished_decor_threads() -> void:
	_collect_finished_decor(_generating_decor, pending_decor_results)

# ── Apply results ─────────────────────────────────────────────────────

func _apply_far_results() -> void:
	if not _parent or not _parent.is_inside_tree(): return
	var ploc := GroundUtils.world_pos_to_chunk_loc(_player.global_transform.origin)
	if pending_far_results.size() > 1:
		pending_far_results.sort_custom(func(a, b):
			return (a as ChunkData).loc.distance_to(ploc) < (b as ChunkData).loc.distance_to(ploc))
	var applied := 0
	while pending_far_results.size() > 0 and applied < max_far_per_frame:
		var cd: ChunkData = pending_far_results.pop_front()
		if _chunks.has(cd.loc) and (_chunks[cd.loc] as GroundChunk).lod_tier <= GroundConstants.LOD_LEVELS.FAR:
			applied += 1; continue
		_apply_single_result(cd)
		applied += 1

func _apply_results() -> void:
	if not _parent or not _parent.is_inside_tree(): return
	var ploc := GroundUtils.world_pos_to_chunk_loc(_player.global_transform.origin)
	if pending_chunk_results.size() > 1:
		pending_chunk_results.sort_custom(func(a, b):
			return (a as ChunkData).loc.distance_to(ploc) < (b as ChunkData).loc.distance_to(ploc))
	var applied := 0
	while pending_chunk_results.size() > 0 and applied < max_chunks_per_frame:
		_apply_single_result(pending_chunk_results.pop_front())
		applied += 1

func _apply_single_result(cd: ChunkData) -> void:
	if _chunks.has(cd.loc):
		_remove_chunk(cd.loc)
	var chunk := GroundChunk.build_chunk(cd, _shader_material, cd.lod_tier == GroundConstants.LOD_LEVELS.CLOSE)
	_parent.add_child(chunk.mesh_instance)
	_chunks[cd.loc] = chunk

func _apply_decor_results() -> void:
	if not _parent or not _parent.is_inside_tree(): return
	if not _parent._mesh_placement_manager: return
	while pending_decor_results.size() > 0:
		var result: DecorThreadResult = pending_decor_results.pop_front()
		var loc: Vector2i = result.loc
		if not _chunks.has(loc): continue
		var chunk: GroundChunk = _chunks[loc]
		if chunk.mesh_assets_spawned: continue
		var tmap: Dictionary = result.transforms_by_mesh
		var spawned_names: Array[String] = []
		for mesh_name in tmap.keys():
			if tmap[mesh_name].size() > 0:
				_parent._mesh_placement_manager.spawn_meshes(mesh_name, tmap[mesh_name], _parent, loc)
				spawned_names.append(mesh_name)
		chunk.mesh_assets_spawned = true
		chunk.data.spawned_decor_names = spawned_names

func _remove_chunk(loc: Vector2i) -> void:
	if _chunks.has(loc):
		(_chunks[loc] as GroundChunk).destroy()
		_chunks.erase(loc)
	if _parent._mesh_placement_manager:
		_parent._mesh_placement_manager.clear_scene_meshes(loc)

# ── Shader material setup ────────────────────────────────────────────

func _build_shader_material() -> ShaderMaterial:
	var shader: Shader = load(GroundConstants.TERRAIN_SHADER_PATH)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	for i in loaded_textures.size():
		var tex_data: TextureData = loaded_textures[i]
		if tex_data.texture:
			mat.set_shader_parameter("tex_%d" % i, tex_data.texture)
		else:
			push_warning("TextureData index %d (%s) missing texture resource!" % [i, tex_data.texture_path])
	mat.set_shader_parameter("texture_scale", GroundConstants.TEXTURE_SCALE)
	mat.set_shader_parameter("region_size", float(GroundConstants.CHUNK_SIZE))
	return mat

func load_textures() -> void:
	loaded_textures = Utils.load_from_json(GroundConstants.TEXTURES_FILE_PATH, TextureData, "textures")
	for tex_data in loaded_textures:
		if tex_data.texture_name.is_empty() or tex_data.texture_path.is_empty():
			push_warning("GroundManager: texture entry missing name or path")
			continue
		var tex = load(tex_data.texture_path)
		if tex:
			tex_data.texture = tex
		else:
			push_warning("GroundManager: Could not load texture at %s" % tex_data.texture_path)
