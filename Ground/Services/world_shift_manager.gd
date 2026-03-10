extends RefCounted
class_name WorldShiftManager

## Handles world-origin shifting to keep floating-point precision high.
## When the player moves too far from the terrain-local origin the entire
## world (terrain regions, spawned meshes, entities) is translated so the
## player ends up near the origin again.

# ── Configuration ─────────────────────────────────────────────────────
var terrain_coord_limit: float = 4096.0
var shift_threshold_fraction: float = 0.5
var max_shift_imports_per_frame: int = 2

# ── State ─────────────────────────────────────────────────────────────
var world_offset := Vector3.ZERO
var shifting := false

# ── References (set via initialize) ──────────────────────────────────
var _terrain: Terrain3D = null
var _player: Node3D = null
var _enemy: Node3D = null
var _nav_baker: Node = null
var _region_stream: RegionStreamManager = null
var _mesh_placement: MeshPlacementManager = null
var _generation_job: GenerationJob = null
var _lod_terrain: LodTerrainManager = null
var _scene_tree: SceneTree = null

func initialize(
	terrain: Terrain3D,
	player: Node3D,
	enemy: Node3D,
	nav_baker: Node,
	region_stream: RegionStreamManager,
	mesh_placement: MeshPlacementManager,
	generation_job: GenerationJob,
	scene_tree: SceneTree,
	lod_terrain: LodTerrainManager = null,
) -> void:
	_terrain = terrain
	_player = player
	_enemy = enemy
	_nav_baker = nav_baker
	_region_stream = region_stream
	_mesh_placement = mesh_placement
	_generation_job = generation_job
	_scene_tree = scene_tree
	_lod_terrain = lod_terrain

# ── Public API ────────────────────────────────────────────────────────

## Returns true when a shift is currently in progress (caller should skip normal work).
func check_and_shift() -> void:
	if shifting:
		return
	if not _terrain or not _terrain.data:
		return
	var player_pos: Vector3 = _player.global_transform.origin
	var threshold: float = terrain_coord_limit * shift_threshold_fraction
	if absf(player_pos.x) >= threshold or absf(player_pos.z) >= threshold:
		await _perform_world_shift()

# ── Core shift routine (async — yields between batches) ──────────────

func _perform_world_shift() -> void:
	shifting = true
	var region_size: int = _terrain.region_size

	# Disable player physics/collision during shift
	if _player.has_method("set_physics_process"):
		_player.set_physics_process(false)
	if _player.has_method("set_collision_layer"):
		_player.set_collision_layer(0)
	if _player.has_method("set_collision_mask"):
		_player.set_collision_mask(0)

	var player_pos: Vector3 = _player.global_transform.origin
	var shift_regions_x: int = roundi(player_pos.x / float(region_size))
	var shift_regions_z: int = roundi(player_pos.z / float(region_size))
	var shift := Vector3(shift_regions_x * region_size, 0, shift_regions_z * region_size)

	if shift.is_zero_approx():
		shifting = false
		return
	
	world_offset += shift
	var shift_loc := Vector2i(shift_regions_x, shift_regions_z)

	# 1) Drain in-flight generation threads.
	var old_results: Array = _region_stream.drain_threads()

	# 2) Shift entities.
	_player.global_transform.origin -= shift
	_enemy.global_transform.origin -= shift

	# 3) Shift spawned meshes.
	_mesh_placement.shift_all_meshes(-shift, shift_loc)

	# 4) Re-key region tracking dictionaries.
	_region_stream.shift_regions(shift_loc)

	# 5) Re-key and shift pending thread results.
	_region_stream.shift_pending_results(old_results, shift, shift_loc)

	# 6) Update generation job's world offset.
	_generation_job.world_offset = world_offset

	# 6b) Shift the generation job's pending-mesh-backfill dictionary.
	_generation_job.shift_regions_needing_meshes(shift_loc, shift)

	# 6c) Shift LOD placeholder meshes.
	if _lod_terrain:
		_lod_terrain.shift_all(-shift, shift_loc)

	# 7) Force nav baker to rebake.
	_nav_baker._current_center = Vector3(INF, INF, INF)

	# 8) Collect all active region data BEFORE removing them.
	var region_data: Array = _collect_region_data(shift_loc)

	# 9) Remove ALL regions in batches to avoid freeze.
	var regions_to_remove := _terrain.data.get_regions_active()
	var remove_batch := 2
	var removed := 0
	while regions_to_remove.size() > 0:
		for i in range(min(remove_batch, regions_to_remove.size())):
			var region = regions_to_remove.pop_back()
			_terrain.data.remove_region(region)
			removed += 1
		if removed % remove_batch == 0:
			await _scene_tree.process_frame
			await _scene_tree.process_frame
			await _scene_tree.process_frame
			await _scene_tree.process_frame

	# 10) Sort region_data by distance to player for prioritized import.
	region_data.sort_custom(func(a, b):
		var apos = Vector2(a["new_loc"].x, a["new_loc"].y)
		var bpos = Vector2(b["new_loc"].x, b["new_loc"].y)
		var ppos = Vector2(roundi(_player.global_transform.origin.x / region_size), roundi(_player.global_transform.origin.z / region_size))
		return apos.distance_to(ppos) < bpos.distance_to(ppos)
	)

	# 11) Re-import in small batches.
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
		_terrain.data.import_images(imported_images, new_origin, 0.0, 1.0)
		imported_count += 1
		if imported_count % 1 == 0:
			await _scene_tree.process_frame
			await _scene_tree.process_frame
			await _scene_tree.process_frame
			await _scene_tree.process_frame
		# Re-enable player as soon as the region under them is loaded
		if imported_count == 1:
			if _player.has_method("set_physics_process"):
				_player.set_physics_process(true)
			if _player.has_method("set_collision_layer"):
				_player.set_collision_layer(1)
			if _player.has_method("set_collision_mask"):
				_player.set_collision_mask(1)

	_terrain.data.calc_height_range(true)
	shifting = false

# ── Helpers ───────────────────────────────────────────────────────────

func _collect_region_data(shift_loc: Vector2i) -> Array:
	var region_data: Array = []
	for region in _terrain.data.get_regions_active():
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
	return region_data

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
