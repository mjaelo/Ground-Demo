extends RefCounted
class_name RegionStreamManager

## Manages region streaming: tracks which regions are loaded / in-flight,
## starts generation threads, collects results, and applies them in priority order.

# ── Configuration ─────────────────────────────────────────────────────
var stream_radius_chunks: int = 20
var stream_check_interval: float = 0.15
var max_concurrent_threads: int = 8
var max_results_per_frame: int = 6
var max_region_distance: int = 25
var close_region_reserved_slots: int = 2

# ── Internal state ────────────────────────────────────────────────────
var _stream_timer := 0.0
var _backfill_timer := 0.0
var _loaded_regions: Dictionary = {}
var _loading_regions: Dictionary = {}
var _generation_threads: Dictionary = {}
var _backfill_threads: Dictionary = {}
var _backfill_loading: Dictionary = {}
var _thread_results: Array = []

# ── References ────────────────────────────────────────────────────────
var _terrain: Terrain3D = null
var _player: Node3D = null
var _generation_job: GenerationJob = null
var _mesh_placement_manager: MeshPlacementManager = null

func initialize(terrain: Terrain3D, player: Node3D, generation_job: GenerationJob, mesh_placement_manager: MeshPlacementManager) -> void:
	_terrain = terrain
	_player = player
	_generation_job = generation_job
	_mesh_placement_manager = mesh_placement_manager

## Scan Terrain3D for regions that already exist on disk (e.g. editor-
## pregenerated) and register them as loaded so the streaming system
## doesn't regenerate or create LOD placeholders for them.
func register_existing_regions() -> void:
	if not _terrain or not _terrain.data:
		return
	var active_regions = _terrain.data.get_regions_active()
	var count := 0
	for region in active_regions:
		var loc: Vector2i = _get_region_location(region)
		_loaded_regions[loc] = true
		count += 1
	if count > 0:
		print("[RegionStream] Pre-registered %d existing terrain regions" % count)

# ── Public API ────────────────────────────────────────────────────────

## Call every frame from the main node's _process.  Returns true when work
## was done (results applied or threads started).
func tick(delta: float) -> void:
	_collect_finished_threads()
	_collect_finished_backfill_threads()
	_apply_thread_results()
	_stream_timer += delta
	if _stream_timer >= stream_check_interval:
		_stream_timer = 0.0
		start_missing_generation_threads()
	# Mesh backfill runs less frequently (every ~1s).
	_backfill_timer += delta
	if _backfill_timer >= 1.0:
		_backfill_timer = 0.0
		_start_mesh_backfill_threads()

func mark_loaded(loc: Vector2i) -> void:
	_loaded_regions[loc] = true
	_loading_regions.erase(loc)

## Start generation for any missing regions around the player.
func start_missing_generation_threads() -> void:
	var player_pos: Vector3 = _player.global_transform.origin
	var player_region: Vector2i = _terrain.data.get_region_location(player_pos)

	# Collect all needed locations.
	var needed_loc: Array[Vector2i] = []
	for x in range(player_region.x - stream_radius_chunks, player_region.x + stream_radius_chunks + 1):
		for y in range(player_region.y - stream_radius_chunks, player_region.y + stream_radius_chunks + 1):
			var loc := Vector2i(x, y)
			if not _loaded_regions.has(loc) and not _loading_regions.has(loc):
				needed_loc.push_back(loc)

	needed_loc.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_to(player_region) < b.distance_to(player_region)
	)

	# Split into close (≤2 chunks) and far.
	var close_needed: Array[Vector2i] = []
	var far_needed: Array[Vector2i] = []
	for loc in needed_loc:
		if loc.distance_to(player_region) <= 2.0:
			close_needed.push_back(loc)
		else:
			far_needed.push_back(loc)

	# Fill thread slots — close regions get priority but far regions can use
	# remaining slots.  We always reserve `close_region_reserved_slots` slots
	# for close regions so an arriving player isn't starved.
	var slots_available: int = max_concurrent_threads - _generation_threads.size()
	var close_used := 0
	for loc in close_needed:
		if slots_available <= 0:
			break
		_start_region_generation(loc)
		slots_available -= 1
		close_used += 1

	# Far regions fill whatever slots remain (but never dip into reserved close slots).
	var far_slots: int = mini(slots_available, max_concurrent_threads - close_region_reserved_slots - (close_used + _count_close_threads(player_region)))
	if far_slots < 0:
		far_slots = 0
	# If there are no close regions at all, let far regions use every slot.
	if close_needed.size() == 0:
		far_slots = slots_available
	for loc in far_needed:
		if far_slots <= 0:
			break
		_start_region_generation(loc)
		far_slots -= 1

	# Remove distant regions.
	for loc in _loaded_regions.keys():
		if loc.distance_to(player_region) > max_region_distance:
			_remove_region(loc)
			_loaded_regions.erase(loc)

## Wait for all in-flight threads and return pending results (used by world shift).
func drain_threads() -> Array:
	for loc in _generation_threads.keys():
		var thread: Thread = _generation_threads[loc]
		thread.wait_to_finish()
	_generation_threads.clear()
	var old := _thread_results.duplicate()
	_thread_results.clear()
	return old

## Re-key all dictionaries after a world shift.
func shift_regions(shift_loc: Vector2i) -> void:
	var new_loaded: Dictionary = {}
	for loc in _loaded_regions.keys():
		new_loaded[loc - shift_loc] = true
	_loaded_regions = new_loaded

	var new_loading: Dictionary = {}
	for loc in _loading_regions.keys():
		new_loading[loc - shift_loc] = true
	_loading_regions = new_loading

## Re-key and spatially shift pending thread results after a world shift.
func shift_pending_results(old_results: Array, shift: Vector3, shift_loc: Vector2i) -> void:
	for result in old_results:
		var old_loc: Vector2i = result.get("loc", Vector2i.ZERO)
		result["loc"] = old_loc - shift_loc
		result["region_origin"] = result.get("region_origin", Vector3.ZERO) - shift
		var transforms_by_mesh: Dictionary = result.get("transforms_by_mesh", {})
		for asset_name in transforms_by_mesh.keys():
			var transforms: Array = transforms_by_mesh[asset_name]
			var shifted_transforms: Array = []
			for t in transforms:
				var st: Transform3D = t as Transform3D
				st.origin -= shift
				shifted_transforms.push_back(st)
			transforms_by_mesh[asset_name] = shifted_transforms
		_thread_results.push_back(result)

# ── Private helpers ───────────────────────────────────────────────────

## Returns the number of currently running generation threads for regions
## within 2 chunks of the given centre.
func _count_close_threads(center: Vector2i) -> int:
	var count := 0
	for loc in _generation_threads.keys():
		if loc.distance_to(center) <= 2.0:
			count += 1
	return count

## Read-only access to the loaded regions dictionary (used by LOD manager).
func get_loaded_regions() -> Dictionary:
	return _loaded_regions

func _start_region_generation(loc: Vector2i) -> void:
	var thread := Thread.new()
	_loading_regions[loc] = true
	_generation_threads[loc] = thread
	var err := thread.start(Callable(_generation_job, "_generate_region_job").bind(loc, _terrain.region_size))
	if err != OK:
		_loading_regions.erase(loc)
		_generation_threads.erase(loc)
		push_error("Failed to start region generation thread: %s" % err)

## Start mesh-backfill threads for regions whose heightmap is loaded but
## decorations were skipped because they were far away at generation time.
func _start_mesh_backfill_threads() -> void:
	if not _terrain or not _terrain.data:
		return
	var player_region: Vector2i = _terrain.data.get_region_location(_player.global_transform.origin)
	var candidates: Array[Vector2i] = _generation_job.get_regions_needing_mesh_backfill(player_region)
	# Use at most 2 concurrent backfill threads to avoid starving new-region generation.
	var max_backfill := 2
	var running := _backfill_threads.size()
	for loc in candidates:
		if running >= max_backfill:
			break
		if _backfill_threads.has(loc) or _backfill_loading.has(loc):
			continue
		var thread := Thread.new()
		_backfill_loading[loc] = true
		_backfill_threads[loc] = thread
		var err := thread.start(Callable(_generation_job, "_generate_mesh_backfill_job").bind(loc, _terrain.region_size))
		if err != OK:
			_backfill_loading.erase(loc)
			_backfill_threads.erase(loc)
		else:
			running += 1

func _collect_finished_backfill_threads() -> void:
	for loc in _backfill_threads.keys():
		var thread: Thread = _backfill_threads[loc]
		if thread.is_alive():
			continue
		var result = thread.wait_to_finish()
		_backfill_threads.erase(loc)
		_backfill_loading.erase(loc)
		if typeof(result) != TYPE_DICTIONARY:
			continue
		_thread_results.push_back(result)

func _collect_finished_threads() -> void:
	var player_region := Vector2i.ZERO
	var has_terrain: bool = _terrain != null and _terrain.data != null
	if has_terrain:
		player_region = _terrain.data.get_region_location(_player.global_transform.origin)

	for loc in _generation_threads.keys():
		var thread: Thread = _generation_threads[loc]
		if thread.is_alive():
			continue
		var result = thread.wait_to_finish()
		_generation_threads.erase(loc)
		if typeof(result) != TYPE_DICTIONARY:
			_loading_regions.erase(loc)
			continue
		if has_terrain and loc.distance_to(player_region) > max_region_distance:
			_loading_regions.erase(loc)
			continue
		_thread_results.push_back(result)

func _apply_thread_results() -> void:
	var has_terrain: bool = _terrain != null and _terrain.data != null
	var player_region := Vector2i.ZERO
	if has_terrain:
		player_region = _terrain.data.get_region_location(_player.global_transform.origin)
	# Sort by proximity to player.
	if has_terrain and _thread_results.size() > 1:
		_thread_results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var la: Vector2i = a.get("loc", Vector2i.ZERO)
			var lb: Vector2i = b.get("loc", Vector2i.ZERO)
			return la.distance_to(player_region) < lb.distance_to(player_region)
		)
	var applied := 0
	while _thread_results.size() > 0 and applied < max_results_per_frame:
		var result: Dictionary = _thread_results.pop_front()
		var loc: Vector2i = result.get("loc", Vector2i.ZERO)
		if has_terrain and loc.distance_to(player_region) > max_region_distance:
			_loading_regions.erase(loc)
			continue
		var is_backfill: bool = result.get("mesh_backfill", false)
		_generation_job.apply_generation_result(result)
		if is_backfill:
			_generation_job.mark_mesh_backfill_complete(loc)
		applied += 1

func _remove_region(loc: Vector2i) -> void:
	_mesh_placement_manager.clear_scene_meshes(loc)
	for region in _terrain.data.get_regions_active():
		var region_loc: Vector2i = _get_region_location(region)
		if region_loc == loc:
			_terrain.data.remove_region(region)
			return

static func _get_region_location(region: Variant) -> Vector2i:
	if region == null:
		return Vector2i.ZERO
	if region.has_method("get_location"):
		return region.get_location()
	var loc: Variant = null
	if region.has_method("get"):
		loc = region.get("location")
	if typeof(loc) == TYPE_VECTOR2I:
		return loc
	return Vector2i.ZERO
