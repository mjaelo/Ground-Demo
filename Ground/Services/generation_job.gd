extends RefCounted
class_name GenerationJob

signal player_spawned

# ── Terrain noise ──────────────────────────────────────────────────────
var noise_frequency: float = 0.0009

# ── Height range ──────────────────────────────────────────────────────
var height_min: float = 0.0
var height_max: float = 800.0

var _player_spawn_complete := false
var _initial_player_region: Vector2i = Vector2i.ZERO
## Regions whose heightmap is loaded but mesh decoration was skipped (far at
## generation time).  Key: Vector2i loc, Value: Vector3 region_origin_m.
var _regions_needing_meshes: Dictionary = {}
## Mesh backfill distance — when a region with pending meshes is within this
## many region-units of the player, we generate its meshes on a thread.
var mesh_backfill_distance: float = 5.0

var noise := FastNoiseLite.new()
var biome_manager: BiomeManager = null
var mesh_placement_manager: MeshPlacementManager = null

## Cumulative world shift offset.
var world_offset := Vector3.ZERO

## References set during initialization.
var _terrain: Terrain3D = null
var _player: CharacterBody3D = null
var _main: Node = null

func initialize(terrain: Terrain3D, player: CharacterBody3D, main: Node, p_biome_manager: BiomeManager, p_mesh_placement: MeshPlacementManager) -> void:
	_terrain = terrain
	_player = player
	_main = main
	biome_manager = p_biome_manager
	mesh_placement_manager = p_mesh_placement
	noise.frequency = noise_frequency
	if terrain and terrain.data:
		_initial_player_region = terrain.data.get_region_location(player.global_transform.origin)

# ── Thread entry point ────────────────────────────────────────────────

func _generate_region_job(loc: Vector2i, region_size: int) -> Dictionary:
	var region_origin_m := Vector3(loc.x * region_size, 0, loc.y * region_size)
	# Terrain3D requires images at region_size resolution for import_images.
	var res: int = region_size
	var import_scale: float = height_max - height_min

	# Determine distance from player region for LOD decisions.
	var player_region: Vector2i = _initial_player_region
	if _terrain and _terrain.data:
		player_region = _terrain.data.get_region_location(_player.global_transform.origin)
	var dist_to_player: float = loc.distance_to(player_region)
	var is_far: bool = dist_to_player > 6.0

	var img: Image = Image.create_empty(res, res, false, Image.FORMAT_RF)
	var ctrl: Image = Image.create_empty(res, res, false, Image.FORMAT_RF)
	var inv_res := 1.0 / float(res)
	var base_x: float = loc.x * region_size + world_offset.x
	var base_z: float = loc.y * region_size + world_offset.z

	# Pass 1: heightmap (must complete before slope can be calculated)
	for x in res:
		var nx: float = (x * inv_res) * region_size + base_x
		for y in res:
			var ny: float = (y * inv_res) * region_size + base_z
			var h: float = noise.get_noise_2d(nx, ny)
			h = (h + 1.0) * 0.5
			var curve_exp: float = biome_manager.get_height_curve(nx, ny)
			h = pow(h, curve_exp)
			img.set_pixel(x, y, Color(height_min + h * import_scale, 0., 0., 1.))

	# Pass 2: control map (slope needs neighbor heights)
	var cell_size: float = float(region_size) / float(res - 1)
	for x in res:
		var nx: float = (x * inv_res) * region_size + base_x
		for y in res:
			var ny: float = (y * inv_res) * region_size + base_z
			var h_c: float = img.get_pixel(x, y).r
			var h_r: float = h_c if x + 1 >= res else img.get_pixel(x + 1, y).r
			var h_d: float = h_c if y + 1 >= res else img.get_pixel(x, y + 1).r
			var dx: float = (h_r - h_c) / cell_size
			var dz: float = (h_d - h_c) / cell_size
			var slope_deg: float = rad_to_deg(acos(clampf(Vector3(-dx, 1.0, -dz).normalized().dot(Vector3.UP), -1.0, 1.0)))
			ctrl.set_pixel(x, y, Color(biome_manager.get_encoded_control(nx, ny, slope_deg), 0., 0., 1.))

	# Generate mesh placements — skip for far regions to speed up generation.
	var transforms_by_mesh: Dictionary = {}
	if mesh_placement_manager and not is_far:
		transforms_by_mesh = mesh_placement_manager.generate_transforms(
			region_origin_m, region_size,
			_sample_height, _sample_normal, biome_manager
		)

	return {
		"loc": loc,
		"region_origin": region_origin_m,
		"image": img,
		"control_image": ctrl,
		"transforms_by_mesh": transforms_by_mesh,
		"needs_meshes": is_far,
	}

# ── Terrain sampling ──────────────────────────────────────────────────


func _sample_height(world_x: float, world_z: float) -> float:
	var wx := world_x + world_offset.x
	var wz := world_z + world_offset.z
	var h := noise.get_noise_2d(wx, wz)
	h = (h + 1.0) * 0.5
	var curve_exp: float = biome_manager.get_height_curve(wx, wz)
	h = pow(h, curve_exp)
	return height_min + h * (height_max - height_min)

func _sample_normal(world_x: float, world_z: float) -> Vector3:
	var base_height := _sample_height(world_x, world_z)
	var dx := _sample_height(world_x + 1.0, world_z) - base_height
	var dz := _sample_height(world_x, world_z + 1.0) - base_height
	return Vector3(-dx, 1.0, -dz).normalized()

# ── Result application (main thread) ─────────────────────────────────

func apply_generation_result(result: Dictionary) -> void:
	_main.call_deferred("_apply_generation_result_deferred", result)

func apply_generation_result_deferred(result: Dictionary) -> void:
	if not _terrain or not _terrain.data:
		return
	var is_backfill: bool = result.get("mesh_backfill", false)
	var imported_images: Array[Image]
	imported_images.resize(Terrain3DRegion.TYPE_MAX)
	imported_images[Terrain3DRegion.TYPE_HEIGHT] = result.get("image", null)
	imported_images[Terrain3DRegion.TYPE_CONTROL] = result.get("control_image", null)
	var region_origin_m: Vector3 = result.get("region_origin", Vector3.ZERO)
	if not is_backfill and imported_images[Terrain3DRegion.TYPE_HEIGHT] != null:
		_terrain.data.import_images.call_deferred(imported_images, region_origin_m, 0.0, 1.0)
		_terrain.data.calc_height_range.call_deferred(true)

	# Spawn meshes (or track for later if this was a far region)
	var loc: Vector2i = result.get("loc", Vector2i.ZERO)
	var needs_meshes: bool = result.get("needs_meshes", false)
	var transforms_by_name: Dictionary = result.get("transforms_by_mesh", {})

	if needs_meshes and transforms_by_name.is_empty():
		# Mark this region for deferred mesh generation when player approaches.
		_regions_needing_meshes[loc] = region_origin_m
	else:
		for asset_name in transforms_by_name.keys():
			var transforms: Array = transforms_by_name[asset_name]
			if transforms.size() > 0 and mesh_placement_manager:
				mesh_placement_manager.spawn_meshes(asset_name, transforms, _main, loc)
		# If it was previously queued, remove it.
		_regions_needing_meshes.erase(loc)

	# Notify the region stream manager via the main node.
	_main.call_deferred("_mark_region_loaded", loc)

	# Trigger player spawn if this was the initial region.
	if not _player_spawn_complete and loc == _initial_player_region:
		_main.call_deferred("_deferred_player_spawn")

func initiate_player_spawn() -> void:
	var target_pos: Vector3 = _player.global_transform.origin
	var h := _terrain.data.get_height(target_pos)
	if is_nan(h):
		h = height_min + 5.0
	_player.global_transform.origin.y = h + 5.0
	_player.gravity_enabled = true
	_player.collision_enabled = true
	_player_spawn_complete = true
	player_spawned.emit(_terrain)

# ── Mesh backfill ─────────────────────────────────────────────────────

## Returns a list of region locations that need mesh generation and are close
## enough to the player.  Called by the stream manager to schedule backfill threads.
func get_regions_needing_mesh_backfill(player_region: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for loc in _regions_needing_meshes.keys():
		if loc.distance_to(player_region) <= mesh_backfill_distance:
			result.push_back(loc)
	# Sort by proximity.
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_to(player_region) < b.distance_to(player_region)
	)
	return result

## Thread entry-point for mesh-only backfill.  Generates only the mesh
## transforms for a region whose heightmap is already loaded.
func _generate_mesh_backfill_job(loc: Vector2i, region_size: int) -> Dictionary:
	var region_origin_m: Vector3 = _regions_needing_meshes.get(loc, Vector3(loc.x * region_size, 0, loc.y * region_size))
	var transforms_by_mesh: Dictionary = {}
	if mesh_placement_manager:
		transforms_by_mesh = mesh_placement_manager.generate_transforms(
			region_origin_m, region_size,
			_sample_height, _sample_normal, biome_manager
		)
	return {
		"loc": loc,
		"region_origin": region_origin_m,
		"image": null,
		"control_image": null,
		"transforms_by_mesh": transforms_by_mesh,
		"needs_meshes": false,
		"mesh_backfill": true,
	}

## Called when a mesh backfill result is applied.
func mark_mesh_backfill_complete(loc: Vector2i) -> void:
	_regions_needing_meshes.erase(loc)

## Shift the pending-mesh dictionary after a world shift.
func shift_regions_needing_meshes(shift_loc: Vector2i, shift: Vector3) -> void:
	var new_dict: Dictionary = {}
	for loc in _regions_needing_meshes.keys():
		var new_loc: Vector2i = loc - shift_loc
		new_dict[new_loc] = _regions_needing_meshes[loc] - shift
	_regions_needing_meshes = new_dict
