extends RefCounted
class_name GroundThreadManager

var chunk_threads: Dictionary = {} # Vector2i -> Thread
var LOD_chunk_threads: Dictionary = {} # Vector2i -> Thread
var decor_threads: Dictionary = {} # Vector2i -> Thread
var pending_chunk_results: Array[ChunkData] = []
var pending_LOD_chunk_results: Array[ChunkData] = []
var pending_decor_results: Array[DecorThreadResult] = []

var max_concurrent_threads: int = GroundConstants.STARTUP_THREADS
var max_chunks_per_frame: int = GroundConstants.STARTUP_CHUNKS_PER_FRAME
var max_far_per_frame: int = GroundConstants.STARTUP_LOD_PER_FRAME
var max_far_threads: int = GroundConstants.STARTUP_LOD_THREADS

var parent: GroundManager = null

func initialize(_parent: GroundManager) -> void:
	parent = _parent

func set_steady_values():
	max_chunks_per_frame = GroundConstants.STEADY_CHUNKS_PER_FRAME
	max_concurrent_threads = GroundConstants.STEADY_THREADS
	max_far_per_frame = GroundConstants.STEADY_LOD_PER_FRAME
	max_far_threads = GroundConstants.STEADY_LOD_THREADS

func handle_thread_results(player_loc: Vector2i):
	_collect_thread_results(chunk_threads, pending_chunk_results)
	_collect_thread_results(LOD_chunk_threads, pending_LOD_chunk_results)
	_collect_thread_results(decor_threads, pending_decor_results)
	_apply_LOD_chunk_results(player_loc)
	_apply_chunk_results(player_loc)
	_apply_decor_results(player_loc)

func _collect_thread_results(dict: Dictionary, results: Array) -> void:
	var done: Array[Vector2i] = []
	for loc in dict.keys():
		if not dict[loc].is_alive():
			done.push_back(loc)
	for loc in done:
		var result = dict[loc].wait_to_finish()
		dict.erase(loc)
		results.push_back(result)

# ── Thread helpers ────────────────────────────────────────────────────
func _start_chunk_generation_thread(is_far: bool, loc: Vector2i, lod_tier: int) -> void:
	var thread_dict := LOD_chunk_threads if is_far else chunk_threads
	var thread := Thread.new()
	thread_dict[loc] = thread
	if thread.start(parent.chunk_manager.generate_chunk_data.bind(loc, lod_tier)) != OK:
		thread_dict.erase(loc)

# ── Apply results ─────────────────────────────────────────────────────
func _apply_LOD_chunk_results(player_loc: Vector2i) -> void:
	if pending_LOD_chunk_results.size() > 1:
		pending_LOD_chunk_results.sort_custom(func(a: ChunkData, b: ChunkData):
			return a.loc.distance_to(player_loc) < b.loc.distance_to(player_loc))
	var applied := 0
	while pending_LOD_chunk_results.size() > 0 and applied < max_far_per_frame:
		var cd: ChunkData = pending_LOD_chunk_results.pop_front()
		var existing: GroundChunk = parent.chunk_manager.chunks.get(cd.loc, null)
		if existing != null and existing.lod_tier <= cd.lod_tier:
			applied += 1
			continue
		_apply_chunk_result(cd, player_loc)
		applied += 1

func _apply_chunk_results(player_loc: Vector2i) -> void:
	if pending_chunk_results.size() > 1:
		pending_chunk_results.sort_custom(func(a: ChunkData, b: ChunkData):
			return a.loc.distance_to(player_loc) < b.loc.distance_to(player_loc))
	var applied := 0
	while pending_chunk_results.size() > 0 and applied < max_chunks_per_frame:
		var cd: ChunkData = pending_chunk_results.pop_front()
		var existing: GroundChunk = parent.chunk_manager.chunks.get(cd.loc, null)
		if existing != null and existing.lod_tier <= cd.lod_tier:
			applied += 1
			continue
		_apply_chunk_result(cd, player_loc)
		applied += 1

func _apply_chunk_result(chunk_d: ChunkData, player_loc: Vector2i) -> void:
	parent.chunk_manager._remove_chunk(chunk_d.loc)
	var add_collision: bool = chunk_d.lod_tier == GroundConstants.LOD_LEVELS.CLOSE
	var chunk := GroundChunk.build_chunk(chunk_d, parent.texture_manager.shader_material, add_collision)
	chunk.lod_tier = chunk_d.lod_tier
	chunk.are_decors_spawned = false
	parent.add_child(chunk.mesh_instance)
	parent.chunk_manager.chunks[chunk_d.loc] = chunk

	if chunk_d.lod_tier == GroundConstants.LOD_LEVELS.CLOSE:
		var dist: float = chunk_d.loc.distance_to(player_loc)
		if dist <= GroundConstants.close_radius + 1:
			if not decor_threads.has(chunk_d.loc) and decor_threads.size() < GroundConstants.MAX_DECOR_THREADS:
				_start_decor_thread_for_decor_id(chunk_d.loc, 0, {})

func _apply_decor_results(player_loc: Vector2i) -> void:
	if pending_decor_results.size() > 1:
		pending_decor_results.sort_custom(func(a, b):
			return (a as DecorThreadResult).loc.distance_to(player_loc) < (b as DecorThreadResult).loc.distance_to(player_loc))
	var applied := 0
	while pending_decor_results.size() > 0 and applied < GroundConstants.MAX_DECOR_CHUNKS_PER_FRAME:
		var result: DecorThreadResult = pending_decor_results.pop_front()
		var loc: Vector2i = result.loc
		var chunk: GroundChunk = parent.chunk_manager.chunks.get(loc, null)
		if not chunk or chunk.lod_tier != GroundConstants.LOD_LEVELS.CLOSE or chunk.are_decors_spawned:
			continue
		# Spawn meshes produced by this decor thread.
		var tmap: Dictionary = result.transforms_by_mesh
		for mesh_name in tmap.keys():
			if tmap[mesh_name].size() > 0:
				parent.decor_manager.spawn_meshes(mesh_name.to_lower(), tmap[mesh_name], loc)
		# Chain the next decor priority, or mark the chunk as done.
		var all_decors: Array[DecorData] = parent.decor_manager.decor_datas_sorted
		var next_idx: int = result.decor_idx + 1
		if next_idx >= all_decors.size():
			#var biome_names := chunk.data.prominent_biomes.map(func(b: BiomeData): return b.biome_name)
			#print("[GroundThreadManager] Chunk ", loc, " decors done for biomes ", biome_names)
			chunk.are_decors_spawned = true
		else:
			var allow_chain: bool = not parent.is_activated or loc.distance_to(player_loc) <= GroundConstants.close_radius + 1
			if allow_chain and decor_threads.size() < GroundConstants.MAX_DECOR_THREADS:
				_start_decor_thread_for_decor_id(loc, next_idx, result.blocked)
			elif not allow_chain:
				# Chunk moved out of range mid-pipeline, mark as done to unblock initial load check.
				chunk.are_decors_spawned = true
		applied += 1
	# After applying results, fill any free decor-thread slots with chunks that haven't started yet.
	_try_start_pending_decors(player_loc)

# ── Public entry points called by ChunkManager ────────────────────────
func start_far_chunk_generation(far_needed: Array[FarChunkRequest]) -> void:
	var far_slots: int = max_far_threads - LOD_chunk_threads.size()
	var far_started := 0
	for item: FarChunkRequest in far_needed:
		if far_started >= max_far_per_frame or far_slots <= 0:
			break
		_start_chunk_generation_thread(true, item.loc, GroundConstants.LOD_LEVELS.FAR)
		far_started += 1
		far_slots -= 1

func start_close_chunk_generation(upgrades: Array[ChunkUpgradeRequest]) -> void:
	var slots: int = max_concurrent_threads - chunk_threads.size()
	for item: ChunkUpgradeRequest in upgrades:
		if slots <= 0:
			break
		_start_chunk_generation_thread(false, item.loc, item.lod_tier)
		slots -= 1

func _try_start_pending_decors(player_loc: Vector2i) -> void:
	if decor_threads.size() >= GroundConstants.MAX_DECOR_THREADS:
		return
	# Build a set of locs that already have a pending result so we don't start a duplicate thread.
	var locs_with_pending: Dictionary = {}
	for r in pending_decor_results:
		locs_with_pending[(r as DecorThreadResult).loc] = true
	var candidates: Array = []
	for loc in parent.chunk_manager.chunks.keys():
		var chunk: GroundChunk = parent.chunk_manager.chunks[loc]
		if chunk.lod_tier == GroundConstants.LOD_LEVELS.CLOSE \
				and not chunk.are_decors_spawned \
				and not decor_threads.has(loc) \
				and not locs_with_pending.has(loc):
			candidates.append(loc)
	candidates.sort_custom(func(a, b): return a.distance_to(player_loc) < b.distance_to(player_loc))
	for loc in candidates:
		if decor_threads.size() >= GroundConstants.MAX_DECOR_THREADS:
			break
		_start_decor_thread_for_decor_id(loc, 0, {})

func _start_decor_thread_for_decor_id(loc: Vector2i, decor_idx: int, blocked_in: Dictionary) -> void:
	if decor_threads.has(loc):
		return
	var chunk: GroundChunk = parent.chunk_manager.chunks.get(loc, null)
	if not chunk:
		return
	var all_decors: Array[DecorData] = parent.decor_manager.decor_datas_sorted
	if all_decors.is_empty():
		chunk.are_decors_spawned = true
		return
	# Advance past any decors not allowed by the chunk's prominent biomes.
	var prominent_biomes: Array = chunk.data.prominent_biomes if chunk.data else []
	while decor_idx < all_decors.size():
		var candidate: DecorData = all_decors[decor_idx]
		var allowed: bool = false
		for biome: BiomeData in prominent_biomes:
			if candidate.decor_name in biome.allowed_decor_ids:
				allowed = true
				break
		if allowed:
			break
		decor_idx += 1
	if decor_idx >= all_decors.size():
		# All decors exhausted for this chunk's biomes.
		#var biome_names := prominent_biomes.map(func(b: BiomeData): return b.biome_name)
		#print("[GroundThreadManager] Chunk ", loc, " decors done for biomes ", biome_names)
		chunk.are_decors_spawned = true
		return

	var decor: DecorData = all_decors[decor_idx]
	var chunk_size := GroundConstants.CHUNK_SIZE
	var chunk_center := Vector3(loc.x * chunk_size + chunk_size * 0.5, 0, loc.y * chunk_size + chunk_size * 0.5)
	var blocked_copy: Dictionary = blocked_in.duplicate(true)
	# Create thread-local noise snapshots BEFORE entering the thread.
	# FastNoiseLite is not thread-safe; each thread needs its own copy.
	var thread_bm: BiomeManager = parent.biome_manager.make_thread_local()
	var thread_noise: FastNoiseLite = parent.noise.duplicate() as FastNoiseLite
	var thread := Thread.new()
	decor_threads[loc] = thread
	var callable := func() -> DecorThreadResult:
		var tmap: Dictionary = parent.decor_manager.generate_transforms_for_decor(chunk_center, chunk_size, blocked_copy, decor, thread_bm, thread_noise)
		return DecorThreadResult.new().init(loc, tmap, decor, blocked_copy, decor_idx)
	#print("[GroundThreadManager] Starting decor thread for decor ", decor.decor_name, " at ", loc)
	if thread.start(callable) != OK:
		push_error("[GroundThreadManager] Failed to start decor thread for %s" % str(loc))
		decor_threads.erase(loc)
