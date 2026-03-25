extends RefCounted
class_name GroundThreadManager

var chunk_threads: Dictionary = {} # Vector2i -> Thread
var LOD_chunk_threads: Dictionary = {} # Vector2i -> Thread
var decor_threads: Dictionary = {} # Vector2i -> Thread
var _decor_priority_index_by_loc: Dictionary = {} # Vector2i -> int TODO what is that?
var _decor_blocked_by_loc: Dictionary = {} # Vector2i -> Dictionary TODO what is that?
var pending_chunk_results: Array[ChunkData] = []
var pending_LOD_chunk_results: Array[ChunkData] = []
var pending_decor_results: Array[DecorThreadResult] = []

var max_concurrent_threads: int = GroundConstants.STARTUP_THREADS
var max_chunks_per_frame: int = GroundConstants.STARTUP_CHUNKS_PER_FRAME
var max_far_per_frame: int = GroundConstants.STARTUP_LOD_PER_FRAME
var max_far_threads: int = GroundConstants.STARTUP_LOD_THREADS

var parent: Ground = null

func initialize(_parent: Ground) -> void:
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
	_apply_LOD_chunk_results( player_loc)
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

func _start_decor_priority_thread(loc: Vector2i) -> void:
	# If a decor thread is already running for this chunk, do nothing.
	if decor_threads.has(loc):
		return

	var chunk_size := GroundConstants.CHUNK_SIZE
	var chunk_center := Vector3(loc.x * chunk_size + chunk_size * 0.5, 0, loc.y * chunk_size + chunk_size * 0.5)

	# Initialize pipeline state for this chunk if needed.
	var allowed_decors: Array[DecorData] = []
	var chunk: GroundChunk = parent.chunk_manager.chunks[loc]
	# If chunk.allowed_decors is null or empty, compute allowed decors for this biome.
	if chunk.allowed_decors == null or (chunk.allowed_decors is Array and chunk.allowed_decors.is_empty()):
		var biome := parent.biome_manager.get_biome_at(chunk_center.x, chunk_center.z)
		allowed_decors = parent.decor_manager.get_allowed_decors_for_biome(biome) # TODO this checks only biome of the center point of the chunk. it should check biome per point
		var names := []
		for d in allowed_decors:
			names.append(d.decor_name)
		if allowed_decors.is_empty():
			# No priorities means there's nothing to place for this biome.
			chunk.are_decors_spawned = true
			return
		chunk.allowed_decors = allowed_decors
		_decor_priority_index_by_loc[loc] = 0
		_decor_blocked_by_loc[loc] = {}
	else:
		# Use existing allowed_decors stored on chunk
		allowed_decors = chunk.allowed_decors

	var idx: int = int(_decor_priority_index_by_loc.get(loc, 0))
	if idx >= allowed_decors.size():
		chunk.are_decors_spawned = true
		return
	var decor: DecorData = allowed_decors[idx]
	var blocked_in: Dictionary = _decor_blocked_by_loc.get(loc, {})
	var blocked_copy: Dictionary = blocked_in.duplicate(true)

	var thread := Thread.new()
	decor_threads[loc] = thread
	var callable := func() -> DecorThreadResult:
		var tmap: Dictionary = parent.decor_manager.generate_transforms_for_decor(chunk_center, chunk_size, blocked_copy, decor)
		return DecorThreadResult.new().init(loc, tmap, decor, blocked_copy)
	# Start decor thread; if it fails, log an error
	if thread.start(callable) != OK:
		push_error("[GroundManager] Failed to start decor thread for %s" % str(loc))
		decor_threads.erase(loc)

# ── Apply results ─────────────────────────────────────────────────────
func _apply_LOD_chunk_results(player_loc: Vector2i) -> void:
	if pending_LOD_chunk_results.size() > 1:
		pending_LOD_chunk_results.sort_custom(func(a, b):
			return (a as ChunkData).loc.distance_to(player_loc) < (b as ChunkData).loc.distance_to(player_loc))
	var applied := 0
	while pending_LOD_chunk_results.size() > 0 and applied < max_far_per_frame:
		var cd: ChunkData = pending_LOD_chunk_results.pop_front()
		var chunk: GroundChunk = parent.chunk_manager.chunks[cd.loc] if parent.chunk_manager.chunks.has(cd.loc) else null
		if chunk && chunk.lod_tier <= GroundConstants.LOD_LEVELS.FAR:
			applied += 1; continue
		_apply_chunk_result(cd,player_loc)
		applied += 1

		# After applying decor results, try to kick off any pending decor threads for close chunks
		_try_start_pending_decors(player_loc)

func _apply_chunk_results(player_loc: Vector2i) -> void:
	if pending_chunk_results.size() > 1:
		pending_chunk_results.sort_custom(func(a, b):
			return (a as ChunkData).loc.distance_to(player_loc) < (b as ChunkData).loc.distance_to(player_loc))
	var applied := 0
	while pending_chunk_results.size() > 0 and applied < max_chunks_per_frame:
		_apply_chunk_result(pending_chunk_results.pop_front(),player_loc)
		applied += 1

func _apply_chunk_result(chunk_d: ChunkData,player_loc: Vector2i) -> void:
	parent.chunk_manager._remove_chunk(chunk_d.loc)
	var chunk := GroundChunk.build_chunk(chunk_d, parent.texture_manager.shader_material, chunk_d.lod_tier == GroundConstants.LOD_LEVELS.CLOSE)
	parent.add_child(chunk.mesh_instance)
	parent.chunk_manager.chunks[chunk_d.loc] = chunk
	# If this is a CLOSE chunk, try to start decor generation immediately (prioritise player proximity)
	if chunk_d.lod_tier == GroundConstants.LOD_LEVELS.CLOSE:
		var dist := chunk_d.loc.distance_to(player_loc)
		if dist <= GroundConstants.close_radius + 1:
			if not decor_threads.has(chunk_d.loc) and decor_threads.size() < GroundConstants.MAX_DECOR_THREADS:
				_start_decor_priority_thread(chunk_d.loc)

func _apply_decor_results(player_loc: Vector2i) -> void:
	if pending_decor_results.size() > 1:
		pending_decor_results.sort_custom(func(a, b): return (a as DecorThreadResult).loc.distance_to(player_loc) < (b as DecorThreadResult).loc.distance_to(player_loc))
	# Apply up to N decor-priority results per frame to avoid hitches.
	var applied := 0
	while pending_decor_results.size() > 0 and applied < GroundConstants.MAX_DECOR_CHUNKS_PER_FRAME:
		var result: DecorThreadResult = pending_decor_results.pop_front()
		var loc: Vector2i = result.loc
		var chunk: GroundChunk = parent.chunk_manager.chunks[loc] if parent.chunk_manager.chunks.has(loc) else null
		if !chunk || chunk.lod_tier != GroundConstants.LOD_LEVELS.CLOSE || chunk.are_decors_spawned:
			continue
		# Spawn this priority's meshes now.
		var tmap: Dictionary = result.transforms_by_mesh
		for mesh_name in tmap.keys():
			if tmap[mesh_name].size() > 0:
				parent.decor_manager.spawn_meshes(mesh_name.to_lower(), tmap[mesh_name], loc)
				chunk.data.spawned_decor_names.append(mesh_name)
		# Persist blocked state and advance to next priority.
		_decor_blocked_by_loc[loc] = result.blocked
		_decor_priority_index_by_loc[loc] = int(_decor_priority_index_by_loc.get(loc, 0)) + 1
		var prios: Array = chunk.allowed_decors
		var next_idx: int = int(_decor_priority_index_by_loc.get(loc, 0))
		if next_idx >= prios.size():
			chunk.are_decors_spawned = true
		else:
			# Start the next (lower) priority as soon as there is capacity.
			if decor_threads.size() < GroundConstants.MAX_DECOR_THREADS:
				_start_decor_priority_thread(loc)
		applied += 1


func start_far_chunk_generation(far_needed:Array[FarChunkRequest]):
	var far_slots: int = max_far_threads - LOD_chunk_threads.size()
	var far_started := 0
	for item:FarChunkRequest in far_needed:
		if far_started >= max_far_per_frame || far_slots <= 0: break
		_start_chunk_generation_thread(true, item.loc, GroundConstants.LOD_LEVELS.FAR)
		far_started += 1; far_slots -= 1

func start_close_chunk_generation(upgrades:Array[ChunkUpgradeRequest]):
	var slots: int = max_concurrent_threads - chunk_threads.size()
	for item:ChunkUpgradeRequest in upgrades:
		if slots <= 0: break
		_start_chunk_generation_thread(false, item.loc, item.lod_tier)
		slots -= 1

func _try_start_pending_decors(player_loc: Vector2i) -> void:
	# Try to start decor threads for CLOSE chunks near the player until capacity is reached.
	var needed := GroundConstants.MAX_DECOR_THREADS - decor_threads.size()
	if needed <= 0:
		return
	# Find CLOSE chunks that haven't spawned decors yet and don't already have decor threads.
	var candidates: Array = []
	for loc in parent.chunk_manager.chunks.keys():
		var chunk: GroundChunk = parent.chunk_manager.chunks[loc]
		if chunk.lod_tier == GroundConstants.LOD_LEVELS.CLOSE and !chunk.are_decors_spawned and !decor_threads.has(loc):
			candidates.append(loc)
	# Sort by distance to player
	candidates.sort_custom(func(a, b): return a.distance_to(player_loc) < b.distance_to(player_loc))
	for loc in candidates:
		if decor_threads.size() >= GroundConstants.MAX_DECOR_THREADS:
			break
		_start_decor_priority_thread(loc)
