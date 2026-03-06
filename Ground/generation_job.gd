extends Node

signal player_spawned

# ── Terrain noise ──────────────────────────────────────────────────────
@export var noise_frequency: float = 0.0009


# ── Height range ──────────────────────────────────────────────────────
@export var height_min: float = 0.0
@export var height_max: float = 800.0

var _player_spawn_complete := false

var _initial_player_region: Vector2i = Vector2i.ZERO
var noise := FastNoiseLite.new()
var biome_manager := BiomeManager.new()
@onready var heightmap_resolution: int = $"../Terrain3D".region_size
var mesh_placement_manager: MeshPlacementManager = null

## Cumulative world shift offset. When generating terrain, this is added to
## local coordinates so noise sampling produces the correct terrain even after
## the world has been shifted back to the origin.
var world_offset := Vector3.ZERO


func _ready() -> void:
	noise.frequency = noise_frequency

func _generate_region_job(loc: Vector2i, region_size: int) -> Dictionary:
	var region_origin_m := Vector3(loc.x * region_size, 0, loc.y * region_size)
	var res: int = heightmap_resolution
	var img: Image = Image.create_empty(res, res, false, Image.FORMAT_RF)
	var ctrl: Image = Image.create_empty(res, res, false, Image.FORMAT_RF)
	var import_scale: float = height_max - height_min

	# First pass: generate heights — store actual world heights directly
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
			# Approximate slope from height image neighbours (heights are already world-scale)
			var slope_deg: float = _slope_deg_from_image(img, x, y, region_size, res, 1.0)
			var encoded: float = biome_manager.get_encoded_control(nx, ny, slope_deg)
			ctrl.set_pixel(x, y, Color(encoded, 0., 0., 1.))

	# Generate mesh placements
	var transforms_by_mesh: Dictionary = {}
	if mesh_placement_manager and mesh_placement_manager.has_method("generate_transforms"):
		# Pass the world-coordinate origin (with offset) so mesh placement uses
		# correct world positions for height/normal sampling and placement coordinates.
		# The returned transforms will be in local coordinates (without offset).
		transforms_by_mesh = mesh_placement_manager.generate_transforms(
			region_origin_m,
			region_size,
			_sample_height,
			_sample_normal
		)

	return {
		"loc": loc,
		"region_origin": region_origin_m,
		"image": img,
		"control_image": ctrl,
		"transforms_by_mesh": transforms_by_mesh,
	}

## Estimate slope in degrees from the heightmap image at pixel (px, py).
func _slope_deg_from_image(img: Image, px: int, py: int, region_size: int, res: int, import_scale: float) -> float:
	var h_c: float = img.get_pixel(px, py).r * import_scale
	var h_r: float
	var h_d: float
	if px + 1 < res:
		h_r = img.get_pixel(px + 1, py).r * import_scale
	else:
		h_r = h_c
	if py + 1 < res:
		h_d = img.get_pixel(px, py + 1).r * import_scale
	else:
		h_d = h_c
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
	var import_scale: float = height_max - height_min
	return height_min + h * import_scale

func _sample_normal(world_x: float, world_z: float) -> Vector3:
	var base_height := _sample_height(world_x, world_z)
	var dx := _sample_height(world_x + 1.0, world_z) - base_height
	var dz := _sample_height(world_x, world_z + 1.0) - base_height
	return Vector3(-dx, 1.0, -dz).normalized()

func _apply_generation_result(result: Dictionary) -> void:
	call_deferred("_apply_generation_result_defered",result)

func _apply_generation_result_defered(result: Dictionary) -> void:
	var terrain: Terrain3D = $"../Terrain3D"
	if not terrain or not terrain.data:
		return
	var imported_images: Array[Image]
	imported_images.resize(Terrain3DRegion.TYPE_MAX)
	imported_images[Terrain3DRegion.TYPE_HEIGHT] = result.get("image", null)
	# Import the control map so Terrain3D uses our per-pixel texture assignments.
	imported_images[Terrain3DRegion.TYPE_CONTROL] = result.get("control_image", null)
	var region_origin_m: Vector3 = result.get("region_origin", Vector3.ZERO)
	if imported_images[Terrain3DRegion.TYPE_HEIGHT] != null:
		# Heights are pre-baked to world scale, so offset=0 scale=1.
		# This is critical: import_scale != 1 could corrupt control map bit patterns.
		terrain.data.import_images.call_deferred(imported_images, region_origin_m, 0.0, 1.0)
		terrain.data.calc_height_range.call_deferred(true)
	var transforms_by_name: Dictionary = result.get("transforms_by_mesh", {})
	var loc: Vector2i = result.get("loc", Vector2i.ZERO)
	for asset_name in transforms_by_name.keys():
		var transforms: Array = transforms_by_name[asset_name]
		if transforms.size() == 0:
			continue
		if mesh_placement_manager:
			mesh_placement_manager.spawn_meshes(asset_name, transforms, get_parent(), loc)
	# Mark region as loaded so the streaming system doesn't regenerate it.
	var main: Node = get_parent()
	if main.has_method("get") and main.get("_loaded_regions") != null:
		main._loaded_regions[loc] = true
	if main.get("_loading_regions") != null:
		main._loading_regions.erase(loc)
	if not _player_spawn_complete and loc == _initial_player_region:
		call_deferred("initiate_player_spawn", terrain)

func initiate_player_spawn(terrain: Terrain3D) -> void:
	var player:CharacterBody3D = $"../Player"
	var target_pos: Vector3 = player.global_transform.origin
	var h := terrain.data.get_height(target_pos)
	if is_nan(h):
		h = height_min + 5.0
	player.global_transform.origin.y = h + 5.0
	player.gravity_enabled = true
	player.collision_enabled = true
	_player_spawn_complete = true
	player_spawned.emit(terrain)
