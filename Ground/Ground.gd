extends Node

@onready var player: CharacterBody3D = get_node("../Player")
@onready var enemy: CharacterBody3D = get_node("Enemy")
@onready var nav_baker: Node = get_node("NavBaker")
@onready var ui: Control = get_node("../UI")
@onready var terrain: Terrain3D = $Terrain3D

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

# ── World shifting ─────────────────────────────────────────────────────
## Cumulative offset applied to keep coordinates within Terrain3D limits.
## True world position = local position + world_offset.
var world_offset := Vector3.ZERO

## The Terrain3D coordinate limit (±4096 by default). We shift when the
## player reaches half this distance from the terrain-local origin.
@export var terrain_coord_limit: float = 4096.0

## We trigger a shift when the player's terrain-local XZ distance from
## the origin exceeds this fraction of the coordinate limit.
@export var shift_threshold_fraction: float = 0.5

## How many region re-imports to perform per frame during a world shift.
## Keep low (2-4) to avoid overwhelming the GPU with texture creation.
@export var max_shift_imports_per_frame: int = 2

var _shifting := false

var _player_spawn_done: bool = false
var _enemy_activated: bool = false
var _cached_terrain: Terrain3D = null

# ── Code-only managers (no scene nodes) ────────────────────────────────
var _texture_manager: TerrainTextureManager = null
var _mesh_placement_manager: MeshPlacementManager = null
var _generation_job: GenerationJob = null

func _ready() -> void:
	ui.player = player
	NavigationServer3D.set_debug_enabled(true)
	player.gravity_enabled = false
	player.collision_enabled = false
	# Disable enemy movement until terrain + nav mesh are ready
	enemy.set_process(false)
	enemy.set_physics_process(false)
	if terrain and terrain.data:
		pass  # _initial_player_region set after generation_job init below
	terrain.collision.mode = Terrain3DCollision.DYNAMIC_EDITOR

	# Wait one frame to ensure child nodes are ready
	await get_tree().process_frame

	# Instantiate code-only managers (no child nodes added to the scene tree).
	_texture_manager = TerrainTextureManager.new()
	_mesh_placement_manager = MeshPlacementManager.new()
	_generation_job = GenerationJob.new()
	var _biome_manager := BiomeManager.new()

	# Load ground textures from JSON and register with Terrain3D.
	_texture_manager.initialize(terrain)

	# Load mesh assets from disk, register with Terrain3D, and load placement rules.
	_mesh_placement_manager.initialize(terrain)

	# Initialize the generation job with references it needs.
	_generation_job.mesh_placement_manager = _mesh_placement_manager
	_generation_job.world_offset = world_offset
	_generation_job.initialize(terrain, player, self, _biome_manager)

	if terrain and terrain.data:
		_generation_job._initial_player_region = terrain.data.get_region_location(player.global_transform.origin)

	start_missing_generation_threads()

	nav_baker.terrain = terrain
	nav_baker.player = player
	nav_baker.enabled = true

	# Connect signals for enemy spawning — enemy only spawns once BOTH terrain around
	# the player is ready (player_spawned) AND the first nav mesh bake is done.
	_generation_job.player_spawned.connect(_on_player_spawned)
	nav_baker.bake_finished.connect(_on_nav_bake_finished)


func _on_player_spawned(_t: Variant = null) -> void:
	_player_spawn_done = true
	_cached_terrain = terrain
	_try_activate_enemy()

func _on_nav_bake_finished() -> void:
	# Nav mesh is now available — enable navigation pathfinding on the enemy if
	# it is already active, otherwise activation happens in _try_activate_enemy.
	if _enemy_activated:
		enemy.enable_navigation()

func _try_activate_enemy() -> void:
	if _enemy_activated:
		return
	if not _player_spawn_done:
		return
	_enemy_activated = true

	# Place the enemy near the player on the terrain surface.
	var player_pos: Vector3 = player.global_transform.origin
	var offset := Vector3(30, 0, 30)
	var enemy_xz: Vector3 = player_pos + offset
	var h: float = _cached_terrain.data.get_height(enemy_xz)
	if is_nan(h):
		h = player_pos.y
	enemy.global_transform.origin = Vector3(enemy_xz.x, h + 1.0, enemy_xz.z)
	enemy.set_process(true)
	enemy.set_physics_process(true)
	# Enable navigation immediately — the enemy has a fallback direct-chase
	# if no nav mesh is available yet.
	enemy.enable_navigation()
	# Force the nav baker to re-bake now that terrain data is loaded.
	# Resetting _current_center to INF guarantees the distance check passes next frame.
	nav_baker._current_center = Vector3(INF, INF, INF)

## Called by GenerationJob (deferred) when the player's initial region is ready.
func _deferred_player_spawn() -> void:
	_generation_job.initiate_player_spawn()

## Called by GenerationJob (deferred) to apply a generation result on the main thread.
func _apply_generation_result_deferred(result: Dictionary) -> void:
	_generation_job.apply_generation_result_deferred(result)

func _process(delta: float) -> void:
	# Check if we need to shift the world back to origin.
	if not _shifting:
		_check_world_shift()
	if _shifting:
		return

	# Always collect finished thread results.
	update_thread_results()

	# Get player region for priority sorting and distance checks.
	var p_player_region := Vector2i.ZERO
	var has_terrain: bool = terrain != null and terrain.data != null
	if has_terrain:
		p_player_region = terrain.data.get_region_location(player.global_transform.origin)

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
		_generation_job.apply_generation_result(result)
		applied += 1

	# Periodically check if we need to generate new regions.
	_stream_timer += delta
	if _stream_timer >= stream_check_interval:
		_stream_timer = 0.0
		start_missing_generation_threads()


func start_missing_generation_threads() -> void:
	var player_pos: Vector3 = player.global_transform.origin
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
			_remove_region(loc)
			_loaded_regions.erase(loc)

func _start_region_generation(loc: Vector2i) -> void:
	var thread := Thread.new()
	_loading_regions[loc] = true
	_generation_threads[loc] = thread
	var err := thread.start(Callable(_generation_job, "_generate_region_job").bind(loc, terrain.region_size))
	if err != OK:
		_loading_regions.erase(loc)
		_generation_threads.erase(loc)
		push_error("Failed to start region generation thread: %s" % err)

func update_thread_results() -> void:
	var player_region := Vector2i.ZERO
	var has_terrain: bool = terrain != null and terrain.data != null
	if has_terrain:
		player_region = terrain.data.get_region_location(player.global_transform.origin)

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

func _remove_region(loc: Vector2i) -> void:
	_mesh_placement_manager.clear_scene_meshes(loc)
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

# ── World shifting ─────────────────────────────────────────────────────

## Check if the player is far enough from the terrain-local origin to trigger a shift.
func _check_world_shift() -> void:
	if not terrain or not terrain.data:
		return
	var player_pos: Vector3 = player.global_transform.origin
	var threshold: float = terrain_coord_limit * shift_threshold_fraction
	if absf(player_pos.x) >= threshold or absf(player_pos.z) >= threshold:
		_perform_world_shift()

## Shift the entire world so the player is re-centered near the terrain-local origin.
## All existing terrain regions, spawned meshes, and entities are moved — nothing is
## regenerated.  This is an async coroutine: it yields between batches of region
## re-imports to avoid overwhelming the Vulkan renderer with texture allocations.
func _perform_world_shift() -> void:
	_shifting = true
	var region_size: int = terrain.region_size

	# The shift amount: player's current position snapped to region boundaries.
	var player_pos: Vector3 = player.global_transform.origin
	var shift_regions_x: int = roundi(player_pos.x / float(region_size))
	var shift_regions_z: int = roundi(player_pos.z / float(region_size))
	var shift := Vector3(shift_regions_x * region_size, 0, shift_regions_z * region_size)

	if shift.is_zero_approx():
		_shifting = false
		return

	print("[WorldShift] Shifting by ", shift, " (regions: ", shift_regions_x, ", ", shift_regions_z, ")")

	# Update cumulative world offset (true world pos = local pos + world_offset).
	world_offset += shift

	# 1) Wait for all in-flight generation threads to finish.
	for loc in _generation_threads.keys():
		var thread: Thread = _generation_threads[loc]
		thread.wait_to_finish()
	_generation_threads.clear()
	# Discard any pending results — they used old coordinates.
	# We need to re-key them with the shifted region locations.
	var old_results := thread_results.duplicate()
	thread_results.clear()

	# 2) Shift entities and meshes FIRST so everything stays visually consistent
	#    while we re-import terrain data over the next several frames.
	player.global_transform.origin -= shift
	enemy.global_transform.origin -= shift

	var shift_loc := Vector2i(shift_regions_x, shift_regions_z)
	_mesh_placement_manager.shift_all_meshes(-shift, shift_loc)

	# 3) Re-key the _loaded_regions and _loading_regions dictionaries.
	var new_loaded: Dictionary = {}
	for loc in _loaded_regions.keys():
		new_loaded[loc - shift_loc] = true
	_loaded_regions = new_loaded

	var new_loading: Dictionary = {}
	for loc in _loading_regions.keys():
		new_loading[loc - shift_loc] = true
	_loading_regions = new_loading

	# 4) Re-key pending thread results.
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
		thread_results.push_back(result)

	# 5) Update GenerationJob's world_offset so noise samples at correct world coordinates.
	_generation_job.world_offset = world_offset

	# 6) Update the nav baker so it rebakes at the new position.
	nav_baker._current_center = Vector3(INF, INF, INF)

	# 7) Collect all active regions and their image data BEFORE removing them.
	var region_data: Array = []
	for region in terrain.data.get_regions_active():
		var old_loc: Vector2i = _get_region_location(region)
		var new_loc: Vector2i = old_loc - shift_loc
		var height_img: Image = null
		var control_img: Image = null
		if region.has_method("get_map"):
			height_img = region.get_map(Terrain3DRegion.TYPE_HEIGHT)
			control_img = region.get_map(Terrain3DRegion.TYPE_CONTROL)
		elif region.has_method("get_height_map"):
			height_img = region.get_height_map()
			control_img = region.get_control_map()
		if height_img:
			height_img = height_img.duplicate()
		if control_img:
			control_img = control_img.duplicate()
		region_data.push_back({
			"new_loc": new_loc,
			"height_img": height_img,
			"control_img": control_img,
		})

	# 8) Remove ALL regions from Terrain3D.
	for region in terrain.data.get_regions_active():
		terrain.data.remove_region(region)

	# Let the renderer clean up freed resources before we start re-importing.
	await get_tree().process_frame
	await get_tree().process_frame

	# 9) Re-import regions at their new shifted positions in small batches,
	#    yielding between batches so the GPU can process texture allocations.
	var imported_count := 0
	for rd in region_data:
		var new_loc: Vector2i = rd["new_loc"]
		var new_origin := Vector3(new_loc.x * region_size, 0, new_loc.y * region_size)
		if absf(new_origin.x) > terrain_coord_limit or absf(new_origin.z) > terrain_coord_limit:
			continue
		if rd["height_img"] == null:
			continue
		var imported_images: Array[Image]
		imported_images.resize(Terrain3DRegion.TYPE_MAX)
		imported_images[Terrain3DRegion.TYPE_HEIGHT] = rd["height_img"]
		imported_images[Terrain3DRegion.TYPE_CONTROL] = rd["control_img"]
		terrain.data.import_images(imported_images, new_origin, 0.0, 1.0)
		imported_count += 1
		if imported_count % max_shift_imports_per_frame == 0:
			# Yield to let the renderer digest the new textures.
			await get_tree().process_frame
	terrain.data.calc_height_range(true)

	print("[WorldShift] Complete. New world_offset: ", world_offset, " (re-imported ", imported_count, " regions)")
	_shifting = false
