extends Node

# Number of chunks to keep loaded around the player (1 = 3x3 grid, 2 = 5x5, 3 = 7x7, etc).
@export var stream_radius_chunks: int = 2

# How often (seconds) to check for streaming updates.
@export var stream_check_interval: float = 2
var _stream_timer := 0.0

# Track regions currently being generated off the main thread.
var _loaded_regions: Dictionary = {}
var _loading_regions: Dictionary = {}
var _generation_threads: Dictionary = {}
var thread_results: Array = []

@export var max_region_distance: int = 6

func _ready() -> void:
	$UI.player = $Player
	NavigationServer3D.set_debug_enabled(false)
	$Player.gravity_enabled = false
	$Player.collision_enabled = false
	# Disable enemy movement until terrain + nav mesh are ready
	$Enemy.set_process(false)
	$Enemy.set_physics_process(false)
	if $Terrain3D and $Terrain3D.data:
		$GenerationJob._initial_player_region = $Terrain3D.data.get_region_location($Player.global_transform.origin)
	$Terrain3D.collision.mode = Terrain3DCollision.DYNAMIC_EDITOR

	# Wait one frame to ensure MeshPlacementManager is ready
	await get_tree().process_frame
	
	# Load assets from disk, register with Terrain3D, and load placement rules.
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
var _first_nav_bake_done: bool = false
var _enemy_activated: bool = false
var _cached_terrain: Terrain3D = null

func _on_player_spawned(terrain: Terrain3D) -> void:
	_player_spawn_done = true
	_cached_terrain = terrain
	_try_activate_enemy()

func _on_nav_bake_finished() -> void:
	if not _first_nav_bake_done:
		_first_nav_bake_done = true
		_try_activate_enemy()

func _try_activate_enemy() -> void:
	if _enemy_activated:
		return
	if not _player_spawn_done or not _first_nav_bake_done:
		return
	_enemy_activated = true

	# Place the enemy near the player on the terrain surface
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
	# Nav mesh is ready — allow the enemy to start pathfinding immediately
	$Enemy.enable_navigation()
	print("Enemy activated at: ", $Enemy.global_transform.origin)

func _process(delta: float) -> void:
	_stream_timer += delta
	if _stream_timer >= stream_check_interval:
		_stream_timer = 0.0
		start_missing_generation_threads()
	
		# apply generation results on the main thread
		if thread_results.size() > 0:
			var result: Dictionary = thread_results.pop_front()
			$GenerationJob._apply_generation_result(result)

	update_thread_results()

func start_missing_generation_threads() -> void:
	if _generation_threads.size():
		return # Already generating regions, wait for next check.
	var terrain: Terrain3D = $Terrain3D
	if not terrain or not terrain.data:
		return
	var player_pos: Vector3 = $Player.global_transform.origin
	var player_region: Vector2i = terrain.data.get_region_location(player_pos)
	var needed_loc: Array[Vector2i]
	for x in range(player_region.x - stream_radius_chunks, player_region.x + stream_radius_chunks + 1):
		for y in range(player_region.y - stream_radius_chunks, player_region.y + stream_radius_chunks + 1):
			needed_loc.push_back(Vector2i(x, y))

	# Sort needed_loc by distance to player_region
	needed_loc.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_to(player_region) < b.distance_to(player_region)
	)

	# Add missing regions
	for loc in needed_loc:
		if _loaded_regions.has(loc) or _loading_regions.has(loc):
			continue
		_start_region_generation(loc)

	# Remove distant regions only if further than max_region_distance
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
	for loc in _generation_threads.keys():
		var thread: Thread = _generation_threads[loc]
		if thread.is_alive():
			continue
		var result = thread.wait_to_finish()
		_generation_threads.erase(loc)
		if typeof(result) == TYPE_DICTIONARY:
			thread_results.push_back(result)
		else:
			_loading_regions.erase(loc)

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
