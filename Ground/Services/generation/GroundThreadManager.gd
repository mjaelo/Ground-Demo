extends RefCounted
class_name GroundThreadManager

var chunk_threads: Dictionary = {}        # Vector2i -> Thread
var decor_threads: Dictionary = {}        # Vector2i -> Thread
var pending_chunk_results: Array[ChunkThreadResult] = []
var pending_decor_results: Array[DecorThreadResult] = []
var chunk_requests: Array[ChunkThreadRequest] = []
var decor_requests: Array[DecorThreadRequest] = []
var is_decor_request_list_dirty: bool = false # when true, decor requests need sorting

var max_chunk_threads: int  = GroundConstants.STARTUP_CHUNK_THREADS
var max_decor_threads: int  = GroundConstants.STARTUP_DECOR_THREADS
var max_chunks_per_frame: int = GroundConstants.STARTUP_CHUNKS_PER_FRAME
var max_lod_per_frame: int  = GroundConstants.STARTUP_LOD_PER_FRAME

var parent: GroundManager
var _last_player_loc: Vector2i = Vector2i.ZERO

func initialize(_parent: GroundManager) -> void:
	parent = _parent

func handle_threads(player_loc: Vector2i) -> void:
	_last_player_loc = player_loc
	_collect_pending_thread_results(chunk_threads, pending_chunk_results)
	_collect_pending_thread_results(decor_threads, pending_decor_results)

	var frustum := parent.camera.get_frustum()

	if pending_chunk_results.size() > 0:
		sort_pending_chunk_results(player_loc, frustum)
		_apply_chunk_results(frustum)

	if pending_decor_results.size() > 0:
		sort_pending_decor_thread_results(player_loc, frustum)
		_apply_decor_results()

	start_decor_threads_for_close_chunks(frustum)

	if chunk_threads.size() < max_chunk_threads:
		update_chunk_requests(player_loc, frustum)
		start_chunk_threads()

	if is_decor_request_list_dirty:
		sort_decor_requests(player_loc, frustum)
		is_decor_request_list_dirty = false

	start_decor_threads(frustum)

# CHUNKS 
func update_chunk_requests(player_loc: Vector2i, frustum: Array[Plane]) -> void:
	var far_r   := GroundConstants.FAR_RADIUS
	var close_r := GroundConstants.CLOSE_RADIUS
	var started_chunk_threads: Array[Vector2i]
	for r: ChunkThreadRequest in chunk_requests:
		started_chunk_threads.append(r.loc)
	for loc in chunk_threads:
		if !started_chunk_threads.has(loc):
			started_chunk_threads.append(loc)
	for x in range(player_loc.x - far_r, player_loc.x + far_r + 1):
		for y in range(player_loc.y - far_r, player_loc.y + far_r + 1):
			var loc := Vector2i(x, y)
			var dist: float = loc.distance_to(player_loc)
			if dist > far_r || started_chunk_threads.has(loc):
				continue
			var chunk: GroundChunk = parent.chunk_manager.chunks.get(loc, null)
			var desired_res: int = GroundConstants.LOD_LEVELS.CLOSE if dist <= close_r else GroundConstants.LOD_LEVELS.FAR
			if chunk != null && chunk.lod_tier <= desired_res:
				continue
			if !is_chunk_visible(loc, frustum) && (desired_res != GroundConstants.LOD_LEVELS.CLOSE || (dist > 1.0 && !_is_startup_chunk(loc))):
				continue
			chunk_requests.push_back(ChunkThreadRequest.new().init(loc, desired_res, dist))
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
		parent.get_node("Chunks").add_child(chunk.mesh_instance)
		parent.chunk_manager.chunks[chunk_d.loc] = chunk

		if is_close:
			close_applied += 1
			if is_chunk_visible(chunk_d.loc, frustum) or _is_startup_chunk(chunk_d.loc):
				var idx := get_next_allowed_decor_in_chunk(0, chunk_d)
				if idx >= 0:
					_push_decor_request(DecorThreadRequest.new().init(chunk_d.loc, idx, {}))
				else:
					chunk.are_decors_spawned = true
		else:
			lod_applied += 1

# DECORS 
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
		_start_decor_thread(req.loc, req.decor_idx, req.blocked)

func _start_decor_thread(loc: Vector2i, decor_idx: int, blocked_in: Dictionary) -> void:
	if decor_threads.has(loc):
		return
	var decor := parent.decor_manager.decor_datas[decor_idx]
	var chunk_size := GroundConstants.CHUNK_SIZE
	var chunk_center := Vector3(loc.x * chunk_size + chunk_size * 0.5, 0, loc.y * chunk_size + chunk_size * 0.5)
	var thread := Thread.new()
	decor_threads[loc] = thread
	var callable := func() -> DecorThreadResult:
		var tmap: Array[Transform3D] = parent.decor_manager.generate_transforms_for_decor(chunk_center, blocked_in, decor)
		return DecorThreadResult.new().init(loc, tmap, blocked_in, decor_idx)
	if thread.start(callable) != OK:
		push_error("[GroundThreadManager] Failed to start decor thread for %s" % str(loc))
		decor_threads.erase(loc)

func _apply_decor_results() -> void:
	while pending_decor_results.size() > 0:
		var result: DecorThreadResult = pending_decor_results.pop_front()
		var loc: Vector2i = result.loc
		var chunk: GroundChunk = parent.chunk_manager.chunks.get(loc, null)
		if !chunk || chunk.lod_tier != GroundConstants.LOD_LEVELS.CLOSE || chunk.are_decors_spawned:
			continue

		var decor_d: DecorData = parent.decor_manager.decor_datas[result.decor_idx]
		var decor_nodes: Array[Node3D] = parent.decor_manager.get_decor_meshes(decor_d, result.transforms_by_mesh)
		for node in decor_nodes:
			parent.add_child(node)
		chunk.decor_nodes = decor_nodes

		# Start next decor for this chunk based on priority, skipping blocked areas
		var idx := get_next_allowed_decor_in_chunk(result.decor_idx + 1, chunk.data)
		if idx != -1:
			var req := DecorThreadRequest.new().init(loc, idx, result.blocked)
			var frustum_now := parent.camera.get_frustum()
			if is_chunk_visible(loc, frustum_now) or _is_startup_chunk(loc):
				if !decor_threads.has(loc) and decor_threads.size() < max_decor_threads:
					_start_decor_thread(req.loc, req.decor_idx, req.blocked)
				else:
					_push_decor_request(req)
			else:
				_push_decor_request(req)
		else:
			chunk.are_decors_spawned = true

# DECOR HELPERS
func start_decor_threads_for_close_chunks(frustum: Array[Plane]) -> void:
	# start decor threads for visible (or startup) CLOSE chunks without decors
	var started_decor_threads: Array[Vector2i] = [] # loc -> is decor thread started
	for req: DecorThreadRequest in decor_requests:
		started_decor_threads.append(req.loc)
	for loc in decor_threads:
		if !started_decor_threads.has(loc):
			started_decor_threads.append(loc)

	for chunk: GroundChunk in parent.chunk_manager.chunks.values():
		if chunk.lod_tier != GroundConstants.LOD_LEVELS.CLOSE || chunk.are_decors_spawned || started_decor_threads.has(chunk.data.loc):
			continue
		if !is_chunk_visible(chunk.data.loc, frustum) && !_is_startup_chunk(chunk.data.loc):
			continue
		var idx := get_next_allowed_decor_in_chunk(0, chunk.data)
		if idx >= 0:
			_push_decor_request(DecorThreadRequest.new().init(chunk.data.loc, idx, {}))
		else:
			chunk.are_decors_spawned = true

func _push_decor_request(req: DecorThreadRequest) -> void:
	decor_requests.append(req)
	is_decor_request_list_dirty = true

func get_next_allowed_decor_in_chunk(decor_idx: int, chunk_data: ChunkData) -> int:
	while decor_idx < parent.decor_manager.decor_datas.size():
		var decor: DecorData = parent.decor_manager.decor_datas[decor_idx]
		if is_decor_allowed_in_chunk(decor, chunk_data):
			return decor_idx
		decor_idx += 1
	return -1

func is_decor_allowed_in_chunk(decor: DecorData, chunk_d: ChunkData) -> bool:
	return chunk_d.prominent_biomes.any(func(b: BiomeData) -> bool: return decor.decor_name in b.allowed_decor_ids)

# GENERAL HELPERS 
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

# should chunk be processed regardless of camera direction.
func _is_startup_chunk(loc: Vector2i) -> bool:
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
		pending_chunk_results.sort_custom(func(a: ChunkThreadResult, b: ChunkThreadResult) -> bool:
			if a.lod_tier != b.lod_tier:
				return a.lod_tier < b.lod_tier
			return sort_by_loc(a.chunk_data.loc, b.chunk_data.loc, player_loc, frustum))

func sort_pending_decor_thread_results(player_loc: Vector2i, frustum: Array[Plane]) -> void:
	if pending_decor_results.size() > 1:
		pending_decor_results.sort_custom(func(a: DecorThreadResult, b: DecorThreadResult) -> bool:
			return sort_by_loc(a.loc, b.loc, player_loc, frustum))

func sort_decor_requests(player_loc: Vector2i, frustum: Array[Plane]) -> void:
	if decor_requests.size() > 1:
		# visible first, then by proximity
		decor_requests.sort_custom(func(a: DecorThreadRequest, b: DecorThreadRequest) -> bool:
			var a_vis := is_chunk_visible(a.loc, frustum)
			var b_vis := is_chunk_visible(b.loc, frustum)
			if a_vis != b_vis:
				return a_vis
			return a.loc.distance_to(player_loc) < b.loc.distance_to(player_loc))

func sort_chunk_requests(frustum: Array[Plane]) -> void:
	chunk_requests.sort_custom(func(a: ChunkThreadRequest, b: ChunkThreadRequest) -> bool:
		if a.lod_tier != b.lod_tier:
			return a.lod_tier < b.lod_tier
		var a_vis := is_chunk_visible(a.loc, frustum)
		var b_vis := is_chunk_visible(b.loc, frustum)
		if a_vis != b_vis:
			return a_vis
		return a.dist < b.dist)

func is_chunk_visible(loc: Vector2i, frustum: Array[Plane]) -> bool:
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
