extends Node

# Number of chunks to keep loaded around the player (1 = 3x3 grid, 2 = 5x5, 3 = 7x7, etc).
@export var stream_radius_chunks: int = 15

# How often (seconds) to check for streaming updates.
@export var stream_check_interval: float = 2
var _stream_timer := 0.0

# Track regions currently being generated off the main thread.
var _loaded_regions: Dictionary = {}
var _loading_regions: Dictionary = {}
var _generation_threads: Dictionary = {}
var thread_results: Array = []

## Max region generation threads running at the same time.
@export var max_concurrent_threads: int = 2
## Max results to apply per frame to avoid overwhelming the GPU/Terrain3D.
@export var max_results_per_frame: int = 1

@export var max_region_distance: int = 15

func _ready() -> void:
	$UI.player = $Player
	NavigationServer3D.set_debug_enabled(true)
	$Player.gravity_enabled = false
	$Player.collision_enabled = false
	# Disable enemy movement until terrain + nav mesh are ready
	$Enemy.set_process(false)
	$Enemy.set_physics_process(false)
	if $Terrain3D and $Terrain3D.data:
		$GenerationJob._initial_player_region = $Terrain3D.data.get_region_location($Player.global_transform.origin)
	$Terrain3D.collision.mode = Terrain3DCollision.DYNAMIC_EDITOR

	# Wait one frame to ensure child nodes are ready
	await get_tree().process_frame

	# Load ground textures from assets/textures/ and register with Terrain3D.
	$TerrainTextureManager.initialize($Terrain3D)

	# Load mesh assets from disk, register with Terrain3D, and load placement rules.
	$MeshPlacementManager.initialize($Terrain3D)

	# Set the mesh placement manager reference for generation job (needed for threaded generation)
	$GenerationJob.mesh_placement_manager = $MeshPlacementManager
	
	start_missing_generation_threads()

	$NavBaker.terrain = $Terrain3D
	$NavBaker.player = $Player
	$NavBaker.enabled = true

	# Connect signals for enemy spawning — enemy only spawns once BOTH terrain around
	# the player is ready (player_spawned) AND the first nav mesh bake is done.
	$GenerationJob.player_spawned.connect(_on_player_spawned)
	$NavBaker.bake_finished.connect(_on_nav_bake_finished)

var _player_spawn_done: bool = false
var _enemy_activated: bool = false
var _cached_terrain: Terrain3D = null

func _on_player_spawned(terrain: Terrain3D) -> void:
	_player_spawn_done = true
	_cached_terrain = terrain
	_try_activate_enemy()

func _on_nav_bake_finished() -> void:
	# Nav mesh is now available — enable navigation pathfinding on the enemy if
	# it is already active, otherwise activation happens in _try_activate_enemy.
	if _enemy_activated:
		$Enemy.enable_navigation()

func _try_activate_enemy() -> void:
	if _enemy_activated:
		return
	if not _player_spawn_done:
		return
	_enemy_activated = true

	# Place the enemy near the player on the terrain surface.
	var terrain: Terrain3D = _cached_terrain
	var player_pos: Vector3 = $Player.global_transform.origin
	var offset := Vector3(30, 0, 30)
	var enemy_xz: Vector3 = player_pos + offset
	var h: float = terrain.data.get_height(enemy_xz)
	if is_nan(h):
		h = player_pos.y
	$Enemy.global_transform.origin = Vector3(enemy_xz.x, h + 1.0, enemy_xz.z)
	$Enemy.set_process(true)
	$Enemy.set_physics_process(true)
	# Enable navigation immediately — the enemy has a fallback direct-chase
	# if no nav mesh is available yet.
	$Enemy.enable_navigation()
	# Force the nav baker to re-bake now that terrain data is loaded.
	# Resetting _current_center to INF guarantees the distance check passes next frame.
	$NavBaker._current_center = Vector3(INF, INF, INF)

func _process(delta: float) -> void:
	# Always collect finished thread results.
	update_thread_results()

	# Get player region for priority sorting and distance checks.
	var p_terrain: Terrain3D = $Terrain3D
	var p_player_region := Vector2i.ZERO
	var has_terrain: bool = p_terrain != null and p_terrain.data != null
	if has_terrain:
		p_player_region = p_terrain.data.get_region_location($Player.global_transform.origin)

	# Apply queued results every frame, but limit how many per frame.
	# Prioritize results closest to the player.
	if has_terrain and thread_results.size() > 1:
		thread_results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var la: Vector2i = a.get("loc", Vector2i.ZERO)
			var lb: Vector2i = b.get("loc", Vector2i.ZERO)
			return la.distance_to(p_player_region) < lb.distance_to(p_player_region)
		)

	var applied := 0
	while thread_results.size() > 0 and applied < max_results_per_frame:
		var result: Dictionary = thread_results.pop_front()
		# Discard results for regions that are now too far from the player.
		var loc: Vector2i = result.get("loc", Vector2i.ZERO)
		if has_terrain and loc.distance_to(p_player_region) > max_region_distance:
			_loading_regions.erase(loc)
			continue
		$GenerationJob._apply_generation_result(result)
		applied += 1

	# Periodically check if we need to generate new regions.
	_stream_timer += delta
	if _stream_timer >= stream_check_interval:
		_stream_timer = 0.0
		start_missing_generation_threads()


func start_missing_generation_threads() -> void:
	var terrain: Terrain3D = $Terrain3D
	if not terrain or not terrain.data:
		return
	var player_pos: Vector3 = $Player.global_transform.origin
	var player_region: Vector2i = terrain.data.get_region_location(player_pos)

	# Collect all needed locations, sorted by distance to player.
	var needed_loc: Array[Vector2i] = []
	for x in range(player_region.x - stream_radius_chunks, player_region.x + stream_radius_chunks + 1):
		for y in range(player_region.y - stream_radius_chunks, player_region.y + stream_radius_chunks + 1):
			var loc := Vector2i(x, y)
			if not _loaded_regions.has(loc) and not _loading_regions.has(loc):
				needed_loc.push_back(loc)

	needed_loc.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_to(player_region) < b.distance_to(player_region)
	)

	# Check if there are close regions still needed (within 2 chunks of player).
	# If so, reserve all thread slots for close work — don't start far threads.
	var close_needed: Array[Vector2i] = []
	var far_needed: Array[Vector2i] = []
	for loc in needed_loc:
		if loc.distance_to(player_region) <= 2.0:
			close_needed.push_back(loc)
		else:
			far_needed.push_back(loc)

	# Prioritize close regions: fill all slots with close work first.
	var slots_available: int = max_concurrent_threads - _generation_threads.size()
	for loc in close_needed:
		if slots_available <= 0:
			break
		_start_region_generation(loc)
		slots_available -= 1

	# Only start far regions if no close ones are pending.
	if close_needed.size() == 0:
		for loc in far_needed:
			if slots_available <= 0:
				break
			_start_region_generation(loc)
			slots_available -= 1

	# Remove distant regions.
	for loc in _loaded_regions.keys():
		if loc.distance_to(player_region) > max_region_distance:
			_remove_region(terrain, loc)
			_loaded_regions.erase(loc)

func _start_region_generation(loc: Vector2i) -> void:
	var thread := Thread.new()
	_loading_regions[loc] = true
	_generation_threads[loc] = thread
	var err := thread.start(Callable($GenerationJob, "_generate_region_job").bind(loc,$Terrain3D.region_size))
	if err != OK:
		_loading_regions.erase(loc)
		_generation_threads.erase(loc)
		push_error("Failed to start region generation thread: %s" % err)

func update_thread_results() -> void:
	var terrain: Terrain3D = $Terrain3D
	var player_region := Vector2i.ZERO
	var has_terrain: bool = terrain != null and terrain.data != null
	if has_terrain:
		player_region = terrain.data.get_region_location($Player.global_transform.origin)

	for loc in _generation_threads.keys():
		var thread: Thread = _generation_threads[loc]
		if thread.is_alive():
			continue
		var result = thread.wait_to_finish()
		_generation_threads.erase(loc)
		if typeof(result) != TYPE_DICTIONARY:
			_loading_regions.erase(loc)
			continue
		# Discard if the region is now too far from the player.
		if has_terrain and loc.distance_to(player_region) > max_region_distance:
			_loading_regions.erase(loc)
			continue
		thread_results.push_back(result)

func _remove_region(terrain: Terrain3D, loc: Vector2i) -> void:
	$MeshPlacementManager.clear_scene_meshes(loc)
	for region in terrain.data.get_regions_active():
		var region_loc: Vector2i = _get_region_location(region)
		if region_loc == loc:
			terrain.data.remove_region(region)
			return

func _get_region_location(region: Variant) -> Vector2i:
	if region == null:
		return Vector2i.ZERO
	# Try common access patterns on the region object without throwing.
	if region.has_method("get_location"):
		return region.get_location()
	var loc: Variant = null
	if region.has_method("get"):
		loc = region.get("location")
	if typeof(loc) == TYPE_VECTOR2I:
		return loc
	return Vector2i.ZERO
