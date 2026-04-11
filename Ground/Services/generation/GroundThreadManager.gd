extends RefCounted
class_name GroundThreadManager

var chunk_threads: Dictionary = {}        # Vector2i -> Thread
var decor_threads: Dictionary = {}        # Vector2i -> Thread
var pending_chunk_results: Array[ChunkThreadResult] = []
var pending_decor_results: Array[DecorThreadResult] = []
var chunk_requests: Array[ChunkThreadRequest] = []
var decor_requests: Array[DecorThreadRequest] = []

var max_chunk_threads: int  = GroundConstants.STARTUP_CHUNK_THREADS
var max_decor_threads: int  = GroundConstants.STARTUP_DECOR_THREADS
var max_chunks_per_frame: int = GroundConstants.STARTUP_CHUNKS_PER_FRAME
var max_lod_per_frame: int  = GroundConstants.STARTUP_LOD_PER_FRAME

var parent: GroundManager
var _last_player_loc: Vector2i = Vector2i.ZERO

# --- Per-frame frustum visibility cache ---
# Populated once per handle_threads() call; cleared at the start of the next call.
var _vis_cache: Dictionary = {}  # Vector2i -> bool

# --- Chunk-scan throttle ---
var _last_scan_loc: Vector2i = Vector2i(-9999, -9999)
var _scan_timer: float = 0.0
var _chunk_requests_dirty: bool = true
var _decor_requests_dirty: bool = true

func initialize(_parent: GroundManager) -> void:
	parent = _parent

func handle_threads(player_loc: Vector2i, delta: float = 0.016) -> void:
	_last_player_loc = player_loc

	# Rebuild per-frame frustum visibility cache
	_vis_cache.clear()
	var frustum := parent.camera.get_frustum()

	# Mark scan as dirty when the player crosses a chunk boundary
	if player_loc != _last_scan_loc:
		_last_scan_loc = player_loc
		_chunk_requests_dirty = true
		_decor_requests_dirty = true
		_scan_timer = 0.0
	else:
		_scan_timer += delta
		if _scan_timer >= GroundConstants.CHUNK_SCAN_INTERVAL:
			_scan_timer = 0.0
			_chunk_requests_dirty = true
			_decor_requests_dirty = true

	# collect pending results
	_collect_pending_thread_results(chunk_threads, pending_chunk_results)
	_collect_pending_thread_results(decor_threads, pending_decor_results)

	# process pending results
	if pending_chunk_results.size() > 0:
		sort_pending_chunk_results(player_loc, frustum)
		_apply_chunk_results(frustum)
	if pending_decor_results.size() > 0:
		sort_pending_decor_thread_results(player_loc, frustum)
		_apply_decor_results(frustum)

	# update thread requests and start threads for them
	if chunk_threads.size() < max_chunk_threads and _chunk_requests_dirty:
		update_chunk_requests(player_loc, frustum)
		_chunk_requests_dirty = false
		start_chunk_threads()
	elif chunk_threads.size() < max_chunk_threads:
		start_chunk_threads()
	if decor_threads.size() < max_decor_threads and _decor_requests_dirty:
		update_decor_requests(player_loc, frustum)
		_decor_requests_dirty = false
		start_decor_threads(frustum)
	elif decor_threads.size() < max_decor_threads:
		start_decor_threads(frustum)

# CHUNKS 
func update_chunk_requests(player_loc: Vector2i, frustum: Array[Plane]) -> void:	
	var are_requests_dirty:=false
	var far_r   := GroundConstants.FAR_RADIUS
	var close_r := GroundConstants.CLOSE_RADIUS
	var far_r_sq: float = float(far_r * far_r)
	var close_r_sq: float = float(close_r * close_r)
	var request_locs: Dictionary = {}
	for r: ChunkThreadRequest in chunk_requests:
		request_locs[r.loc] = true
	for x in range(player_loc.x - far_r, player_loc.x + far_r + 1):
		for y in range(player_loc.y - far_r, player_loc.y + far_r + 1):
			var loc := Vector2i(x, y)
			var dx: float = float(x - player_loc.x)
			var dy: float = float(y - player_loc.y)
			var dist_sq: float = dx * dx + dy * dy
			if dist_sq > far_r_sq || chunk_threads.has(loc) || request_locs.has(loc):
				continue
			var chunk: GroundChunk = parent.chunk_manager.chunks.get(loc, null)
			var desired_res: int = GroundConstants.LOD_LEVELS.CLOSE if dist_sq <= close_r_sq else GroundConstants.LOD_LEVELS.FAR
			if chunk != null && chunk.lod_tier <= desired_res:
				continue
			if !is_chunk_visible(loc, frustum) && (desired_res != GroundConstants.LOD_LEVELS.CLOSE || (dist_sq > 1.0 && !_is_startup_chunk(loc))):
				continue
			if desired_res == GroundConstants.LOD_LEVELS.CLOSE and parent.chunk_manager.saved_chunk_data.has(loc):
				var chunk_data:ChunkData = parent.chunk_manager.saved_chunk_data[loc]
				const lod_tier := GroundConstants.LOD_LEVELS.CLOSE
				pending_chunk_results.push_back(ChunkThreadResult.new().init(lod_tier, chunk_data))
				continue
			var dist: float = sqrt(dist_sq)
			chunk_requests.push_back(ChunkThreadRequest.new().init(loc, desired_res, dist))
			are_requests_dirty = true
	if are_requests_dirty:
		sort_chunk_requests(frustum)

func start_chunk_threads() -> void:
	var i := 0
	while i < chunk_requests.size():
		if chunk_threads.size() >= max_chunk_threads:
			break
		var req: ChunkThreadRequest = chunk_requests[i]
		if chunk_threads.has(req.loc):
			i += 1
			continue
		chunk_requests.remove_at(i)
		var thread := Thread.new()
		chunk_threads[req.loc] = thread
		if thread.start(parent.chunk_manager.get_chunk_thread_result.bind(req.loc, req.lod_tier)) != OK:
			chunk_threads.erase(req.loc)

func _apply_chunk_results(frustum: Array[Plane]) -> void:
	var close_applied := 0
	var lod_applied   := 0
	var i := 0
	while i < pending_chunk_results.size():
		# Early-out when both budgets are exhausted
		if close_applied >= max_chunks_per_frame and lod_applied >= max_lod_per_frame:
			break
		var thread_result: ChunkThreadResult = pending_chunk_results[i]
		var is_close := thread_result.lod_tier == GroundConstants.LOD_LEVELS.CLOSE
		var chunk_d := thread_result.chunk_data
		if (is_close and close_applied >= max_chunks_per_frame) || (!is_close and lod_applied >= max_lod_per_frame):
			i += 1
			continue
		pending_chunk_results.remove_at(i)
		var existing_chunk: GroundChunk = parent.chunk_manager.chunks.get(chunk_d.loc, null)
		if existing_chunk != null and existing_chunk.lod_tier <= thread_result.lod_tier:
			continue

		if parent.chunk_manager.chunks.has(chunk_d.loc):
			parent.chunk_manager._remove_chunk(chunk_d.loc)
		var chunk: GroundChunk = GroundUtils.build_chunk(chunk_d, parent.texture_manager.shader_material, thread_result.lod_tier)
		
		chunk.lod_tier = thread_result.lod_tier
		chunk.are_decors_spawned = false
		parent.get_node("Chunks").add_child(chunk.mesh_instance)# TODO should add Node3D base with script of GroundChunk and add children to it.
		parent.chunk_manager.chunks[chunk_d.loc] = chunk

		if is_close:
			close_applied += 1
			# start decor generation for this CLOSE chunk
			if is_chunk_visible(chunk_d.loc, frustum) or _is_startup_chunk(chunk_d.loc):
				if chunk_d.decor_transforms.size() == 0: # pending_decor_results are updated with decor_transforms in update_decor_requests
					var idx := get_next_allowed_decor_in_chunk(0, chunk_d.prominent_biome_ids)
					if idx >= 0:
						decor_requests.append(DecorThreadRequest.new().init(chunk_d.loc, idx, {},[])) 
					else:
						chunk.are_decors_spawned = true
						parent.chunk_manager.saved_chunk_data[chunk.data.loc] = chunk.data
		else:
			lod_applied += 1

# DECORS 
func update_decor_requests(player_loc: Vector2i, frustum: Array[Plane]) -> void:
	# update decor thread requests for visible (or startup) CLOSE chunks without decors
	var are_requests_dirty:=false
	var saved_decor_applied := 0
	var loc_from_req: Dictionary = {}
	for req: DecorThreadRequest in decor_requests:
		loc_from_req[req.loc] = true
	for chunk: GroundChunk in parent.chunk_manager.chunks.values():
		if chunk.lod_tier != GroundConstants.LOD_LEVELS.CLOSE || chunk.are_decors_spawned || decor_threads.has(chunk.data.loc) || loc_from_req.has(chunk.data.loc):
			continue
		if !is_chunk_visible(chunk.data.loc, frustum) && !_is_startup_chunk(chunk.data.loc):
			continue
		if chunk.data.decor_transforms.size() > 0:
			if saved_decor_applied >= max_chunks_per_frame:
				continue
			# Instantiate all saved decor layers directly (no threads needed)
			for decor_idx in chunk.data.decor_transforms.keys():
				var decor_d: DecorData = parent.decor_manager.decor_datas[decor_idx]
				var decor_nodes: Array[Node3D] = parent.decor_manager.get_decor_meshes(decor_d, chunk.data.decor_transforms[decor_idx])
				for node in decor_nodes:
					parent.add_child(node)
				chunk.decor_nodes.append_array(decor_nodes)
			chunk.are_decors_spawned = true
			saved_decor_applied += 1
			continue
		var idx := get_next_allowed_decor_in_chunk(0, chunk.data.prominent_biome_ids)
		if idx >= 0:
			decor_requests.append(DecorThreadRequest.new().init(chunk.data.loc, idx, {},[])) 
			are_requests_dirty = true
		else:
			chunk.are_decors_spawned = true
			parent.chunk_manager.saved_chunk_data[chunk.data.loc] = chunk.data
	if are_requests_dirty:
		sort_decor_requests(player_loc, frustum)

func start_decor_threads(frustum: Array[Plane]) -> void:
	var i := 0
	while i < decor_requests.size():
		if decor_threads.size() >= max_decor_threads:
			break
		var req: DecorThreadRequest = decor_requests[i]
		if decor_threads.has(req.loc):
			i += 1
			continue
		if !is_chunk_visible(req.loc, frustum) and !_is_startup_chunk(req.loc):
			i += 1
			continue
		decor_requests.remove_at(i)
		_start_decor_thread(req)

func _start_decor_thread(req: DecorThreadRequest) -> void:
	if decor_threads.has(req.loc):
		return
	var decor_d := parent.decor_manager.decor_datas[req.decor_idx]
	if decor_d.decor_name.is_empty() or !parent.decor_manager.decor_scenes.has(decor_d.decor_name.to_lower()):
		return
	var chunk_size := GroundConstants.CHUNK_SIZE
	var chunk_center := Vector3(req.loc.x * chunk_size + chunk_size * 0.5, 0, req.loc.y * chunk_size + chunk_size * 0.5)
	var thread := Thread.new()
	decor_threads[req.loc] = thread	
	if thread.start(parent.decor_manager.get_decor_thread_result.bind(chunk_center, req.blocked, decor_d, req.decor_idx, req.loc)) != OK:
		push_error("[GroundThreadManager] Failed to start decor thread for %s" % str(req.loc))
		decor_threads.erase(req.loc)

func _apply_decor_results(frustum: Array[Plane]) -> void:
	var applied := 0
	while pending_decor_results.size() > 0 and applied < max_chunks_per_frame:
		var result: DecorThreadResult = pending_decor_results.pop_front()
		var loc: Vector2i = result.loc
		var chunk: GroundChunk = parent.chunk_manager.chunks.get(loc, null)
		if !chunk || chunk.lod_tier != GroundConstants.LOD_LEVELS.CLOSE || chunk.are_decors_spawned:
			continue
		chunk.blocked = result.blocked
		applied += 1
		
		var decor_d: DecorData = parent.decor_manager.decor_datas[result.decor_idx]
		var decor_nodes: Array[Node3D] = parent.decor_manager.get_decor_meshes(decor_d, result.decor_transforms)
		for node in decor_nodes:
			parent.add_child(node)
		chunk.decor_nodes.append_array(decor_nodes)
		chunk.data.decor_transforms[result.decor_idx] = result.decor_transforms

		# Start next decor for this chunk based on priority, skipping blocked areas
		var idx := get_next_allowed_decor_in_chunk(result.decor_idx + 1, chunk.data.prominent_biome_ids)
		if idx != -1 && !chunk.data.decor_transforms.has(idx):
			var req := DecorThreadRequest.new().init(loc, idx, result.blocked, [])
			if is_chunk_visible(loc, frustum) or _is_startup_chunk(loc):
				if !decor_threads.has(loc) and decor_threads.size() < max_decor_threads:
					_start_decor_thread(req)
				else:
					decor_requests.append(req)
			else:
				decor_requests.append(req)
		else:
			chunk.are_decors_spawned = true
			parent.chunk_manager.saved_chunk_data[chunk.data.loc] = chunk.data

# HELPERS 
func _collect_pending_thread_results(dict: Dictionary, results: Array) -> void:
	var done: Array = []
	for key in dict.keys():
		if !dict[key].is_alive():
			done.push_back(key)
	for key in done:
		var result = dict[key].wait_to_finish()
		dict.erase(key)
		results.push_back(result)

func set_steady_values() -> void:
	max_chunk_threads    = GroundConstants.STEADY_CHUNK_THREADS
	max_decor_threads    = GroundConstants.STEADY_DECOR_THREADS
	max_chunks_per_frame = GroundConstants.STEADY_CHUNKS_PER_FRAME
	max_lod_per_frame    = GroundConstants.STEADY_LOD_PER_FRAME

func get_next_allowed_decor_in_chunk(decor_idx: int, prominent_biomes: Array[int]) -> int:
	while decor_idx < parent.decor_manager.decor_datas.size():
		var decor: DecorData = parent.decor_manager.decor_datas[decor_idx]
		var allowed := false
		for id: int in prominent_biomes:
			if decor.decor_name in parent.biome_manager.biomes[id].allowed_decor_ids:
				allowed = true
				break
		if allowed:
			return decor_idx
		decor_idx += 1
	return -1

func _is_startup_chunk(loc: Vector2i) -> bool:
	# should chunk be processed regardless of camera direction.
	if parent.is_ground_startup_done:
		return false
	var d := loc - _last_player_loc # Chebyshev distance - max of per-axis deltas (i don't understand it either, but it works)
	return maxi(absi(d.x), absi(d.y)) <= GroundConstants.STARTUP_RADIUS

# SORTERS
func sort_by_loc(a: Vector2i, b: Vector2i, player_loc: Vector2i, frustum: Array[Plane]) -> bool:
	var a_vis := is_chunk_visible(a, frustum)
	var b_vis := is_chunk_visible(b, frustum)
	if a_vis != b_vis:
		return a_vis
	return a.distance_to(player_loc) < b.distance_to(player_loc)

func sort_pending_chunk_results(player_loc: Vector2i, frustum: Array[Plane]) -> void:
	if pending_chunk_results.size() > 1:
		# Pre-warm cache for all locs in the result set
		for r: ChunkThreadResult in pending_chunk_results:
			is_chunk_visible(r.chunk_data.loc, frustum)
		pending_chunk_results.sort_custom(func(a: ChunkThreadResult, b: ChunkThreadResult) -> bool:
			if a.lod_tier != b.lod_tier:
				return a.lod_tier < b.lod_tier
			var a_vis: bool = _vis_cache.get(a.chunk_data.loc, true)
			var b_vis: bool = _vis_cache.get(b.chunk_data.loc, true)
			if a_vis != b_vis:
				return a_vis
			return a.chunk_data.loc.distance_to(player_loc) < b.chunk_data.loc.distance_to(player_loc))

func sort_pending_decor_thread_results(player_loc: Vector2i, frustum: Array[Plane]) -> void:
	if pending_decor_results.size() > 1:
		for r: DecorThreadResult in pending_decor_results:
			is_chunk_visible(r.loc, frustum)
		pending_decor_results.sort_custom(func(a: DecorThreadResult, b: DecorThreadResult) -> bool:
			var a_vis: bool = _vis_cache.get(a.loc, true)
			var b_vis: bool = _vis_cache.get(b.loc, true)
			if a_vis != b_vis:
				return a_vis
			return a.loc.distance_to(player_loc) < b.loc.distance_to(player_loc))

func sort_decor_requests(player_loc: Vector2i, frustum: Array[Plane]) -> void:
	if decor_requests.size() > 1:
		for r: DecorThreadRequest in decor_requests:
			is_chunk_visible(r.loc, frustum)
		decor_requests.sort_custom(func(a: DecorThreadRequest, b: DecorThreadRequest) -> bool:
			var a_vis: bool = _vis_cache.get(a.loc, true)
			var b_vis: bool = _vis_cache.get(b.loc, true)
			if a_vis != b_vis:
				return a_vis
			return a.loc.distance_to(player_loc) < b.loc.distance_to(player_loc))

func sort_chunk_requests(frustum: Array[Plane]) -> void:
	for r: ChunkThreadRequest in chunk_requests:
		is_chunk_visible(r.loc, frustum)
	chunk_requests.sort_custom(func(a: ChunkThreadRequest, b: ChunkThreadRequest) -> bool:
		if a.lod_tier != b.lod_tier:
			return a.lod_tier < b.lod_tier
		var a_vis: bool = _vis_cache.get(a.loc, true)
		var b_vis: bool = _vis_cache.get(b.loc, true)
		if a_vis != b_vis:
			return a_vis
		return a.dist < b.dist)

func is_chunk_visible(loc: Vector2i, frustum: Array[Plane]) -> bool:
	if _vis_cache.has(loc):
		return _vis_cache[loc]
	var result := _test_chunk_aabb(loc, frustum)
	_vis_cache[loc] = result
	return result

func _test_chunk_aabb(loc: Vector2i, frustum: Array[Plane]) -> bool:
	if frustum.is_empty():
		return true
	var cs: float = GroundConstants.CHUNK_SIZE
	var wx: float = loc.x * cs
	var wz: float = loc.y * cs
	var aabb := AABB(
		Vector3(wx, GroundConstants.HEIGHT_MIN, wz),
		Vector3(cs, GroundConstants.HEIGHT_MAX - GroundConstants.HEIGHT_MIN, cs)
	)
	for plane: Plane in frustum:
		if plane.is_point_over(aabb.get_support(-plane.normal)):
			return false
	return true
