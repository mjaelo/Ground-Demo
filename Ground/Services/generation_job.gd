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

var noise := FastNoiseLite.new()
var biome_manager: BiomeManager = null
var heightmap_resolution: int = 256
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
	heightmap_resolution = terrain.region_size
	noise.frequency = noise_frequency
	if terrain and terrain.data:
		_initial_player_region = terrain.data.get_region_location(player.global_transform.origin)

# ── Thread entry point ────────────────────────────────────────────────

func _generate_region_job(loc: Vector2i, region_size: int) -> Dictionary:
	var region_origin_m := Vector3(loc.x * region_size, 0, loc.y * region_size)
	var res: int = heightmap_resolution
	var img: Image = Image.create_empty(res, res, false, Image.FORMAT_RF)
	var ctrl: Image = Image.create_empty(res, res, false, Image.FORMAT_RF)
	var import_scale: float = height_max - height_min

	# First pass: generate heights
	for x in res:
		for y in res:
			var nx := (x / float(res)) * region_size + loc.x * region_size + world_offset.x
			var ny := (y / float(res)) * region_size + loc.y * region_size + world_offset.z
			var h := noise.get_noise_2d(nx, ny)
			h = (h + 1.0) * 0.5
			var curve_exp: float = biome_manager.get_height_curve(nx, ny)
			h = pow(h, curve_exp)
			var world_h: float = height_min + h * import_scale
			img.set_pixel(x, y, Color(world_h, 0., 0., 1.))

	# Second pass: build control map (needs height neighbours for slope)
	for x in res:
		for y in res:
			var nx := (x / float(res)) * region_size + loc.x * region_size + world_offset.x
			var ny := (y / float(res)) * region_size + loc.y * region_size + world_offset.z
			var slope_deg: float = _slope_deg_from_image(img, x, y, region_size, res, 1.0)
			var encoded: float = biome_manager.get_encoded_control(nx, ny, slope_deg)
			ctrl.set_pixel(x, y, Color(encoded, 0., 0., 1.))

	# Generate mesh placements
	var transforms_by_mesh: Dictionary = {}
	if mesh_placement_manager:
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
	}

# ── Terrain sampling ──────────────────────────────────────────────────

func _slope_deg_from_image(img: Image, px: int, py: int, region_size: int, res: int, import_scale: float) -> float:
	var h_c: float = img.get_pixel(px, py).r * import_scale
	var h_r: float = h_c if px + 1 >= res else img.get_pixel(px + 1, py).r * import_scale
	var h_d: float = h_c if py + 1 >= res else img.get_pixel(px, py + 1).r * import_scale
	var cell_size: float = float(region_size) / float(res)
	var dx: float = (h_r - h_c) / cell_size
	var dz: float = (h_d - h_c) / cell_size
	var n := Vector3(-dx, 1.0, -dz).normalized()
	return rad_to_deg(acos(clamp(n.dot(Vector3.UP), -1.0, 1.0)))

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
	var imported_images: Array[Image]
	imported_images.resize(Terrain3DRegion.TYPE_MAX)
	imported_images[Terrain3DRegion.TYPE_HEIGHT] = result.get("image", null)
	imported_images[Terrain3DRegion.TYPE_CONTROL] = result.get("control_image", null)
	var region_origin_m: Vector3 = result.get("region_origin", Vector3.ZERO)
	if imported_images[Terrain3DRegion.TYPE_HEIGHT] != null:
		_terrain.data.import_images.call_deferred(imported_images, region_origin_m, 0.0, 1.0)
		_terrain.data.calc_height_range.call_deferred(true)

	# Spawn meshes
	var loc: Vector2i = result.get("loc", Vector2i.ZERO)
	var transforms_by_name: Dictionary = result.get("transforms_by_mesh", {})
	for asset_name in transforms_by_name.keys():
		var transforms: Array = transforms_by_name[asset_name]
		if transforms.size() > 0 and mesh_placement_manager:
			mesh_placement_manager.spawn_meshes(asset_name, transforms, _main, loc)

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
