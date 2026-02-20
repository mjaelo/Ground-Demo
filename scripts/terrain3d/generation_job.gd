extends Node

# Noise frequency that shapes the terrain slopes/hills.
@export var noise_frequency: float = 0.0009
# Biome noise — very low frequency so biomes are much larger than regions.
# Lower = bigger biomes, higher = smaller biomes.
@export var biome_noise_frequency: float = 0.00015
# Mountains only appear where biome noise exceeds this threshold (0-1).
# 0.75 = top 25% of the world is mountains. Higher = rarer mountains.
@export var biome_mountain_threshold: float = 0.9
# How wide the flat->mountain transition band is (0-1 of noise range after threshold).
# Smaller = sharper edge, larger = wider gradual transition.
@export var biome_transition_width: float = 0.2
# How much the biome noise shapes the terrain.
# biome_curve_flat: exponent in flat biomes — higher = flatter/lower ground (e.g. 4.0).
# biome_curve_mountain: exponent in mountain biomes — lower = taller sharper peaks (e.g. 0.4).
@export var biome_curve_flat: float = 4.0
@export var biome_curve_mountain: float = 0.4
# How far to scatter grass/foliage; 0 uses the full terrain size.
@export var foliage_extent: int = 0
# Distance between placed foliage instances; lower = denser.
@export var foliage_step: int = 2
# Max slope (degrees) where grass/foliage is allowed; steeper spots stay bare/brown.
@export var foliage_max_slope_deg: float = 18.0
# Chance (0-1) to keep a foliage instance after slope check; lower = more sporadic.
@export var foliage_density: float = 0.25
# Lowest and highest terrain elevation (meters) used when importing the heightmap.
@export var height_min: float = 0.0
@export var height_max: float = 800.0
var _player_spawn_complete := false

var _initial_player_region: Vector2i = Vector2i.ZERO
var noise := FastNoiseLite.new()
var biome_noise := FastNoiseLite.new()
@onready var heightmap_resolution: int = $"../Terrain3D".region_size


func _ready() -> void:
	noise.frequency = noise_frequency
	biome_noise.seed = 12345
	biome_noise.frequency = biome_noise_frequency

func _generate_region_job(loc: Vector2i,region_size:int) -> Dictionary:
	var region_origin_m := Vector3(loc.x * region_size, 0, loc.y * region_size)
	# Resolution of the generated heightmap image; higher = smoother but slower.
	var img: Image = Image.create_empty(heightmap_resolution, heightmap_resolution, false, Image.FORMAT_RF)
	for x in img.get_width():
		for y in img.get_height():
			var nx := (x / float(heightmap_resolution)) * region_size + loc.x * region_size
			var ny := (y / float(heightmap_resolution)) * region_size + loc.y * region_size
			var h := noise.get_noise_2d(nx, ny)
			h = (h + 1.0) * 0.5
			# Biome noise: very low frequency, smoothly controls terrain shape per world pos
			var b := biome_noise.get_noise_2d(nx, ny)
			b = (b + 1.0) * 0.5
			# Use smoothstep over transition_width after threshold so mountains are rare and edges smooth
			var threshold: float = biome_mountain_threshold
			var tw: float = max(biome_transition_width, 0.01)
			var t: float = smoothstep(threshold, threshold + tw, b)
			# t=0 -> flat biome, t=1 -> mountain biome
			var curve_exp: float = lerp(
				biome_curve_flat,
				biome_curve_mountain,
				t
			)
			h = pow(h, curve_exp)
			img.set_pixel(x, y, Color(h, 0., 0., 1.))
	var transforms: Array[Transform3D]
	var width: int = foliage_extent
	if width <= 0:
		width = int(region_size)
	var step: int = max(1, int(foliage_step))
	var origin: Vector3 = region_origin_m + Vector3(-region_size * 0.5, 0, -region_size * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for x in range(0, width, step):
		for z in range(0, width, step):
			var pos_x := x + origin.x
			var pos_z := z + origin.z
			var h_val := _sample_height(pos_x, pos_z)
			var pos := Vector3(pos_x, h_val, pos_z)
			var normal: Vector3 = _sample_normal(pos_x, pos_z)
			var slope_deg := rad_to_deg(acos(clamp(normal.dot(Vector3.UP), -1.0, 1.0)))
			if slope_deg > foliage_max_slope_deg:
				continue
			if rng.randf() > foliage_density:
				continue
			transforms.push_back(Transform3D(Basis(), pos))
	return {
		"loc": loc,
		"region_origin": region_origin_m,
		"image": img,
		"transforms": transforms
	}

func _sample_height(world_x: float, world_z: float) -> float:
	var h := noise.get_noise_2d(world_x, world_z)
	h = (h + 1.0) * 0.5
	var b := biome_noise.get_noise_2d(world_x, world_z)
	b = (b + 1.0) * 0.5
	var threshold: float = biome_mountain_threshold
	var tw: float = max(biome_transition_width, 0.01)
	var t: float = smoothstep(threshold, threshold + tw, b)
	var curve_exp: float = lerp(
		biome_curve_flat,
		biome_curve_mountain,
		t
	)
	h = pow(h, curve_exp)
	var height_min_local: float = height_min
	var import_scale: float = height_max - height_min_local
	return height_min_local + h * import_scale

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
	var region_origin_m: Vector3 = result.get("region_origin", Vector3.ZERO)
	if imported_images[Terrain3DRegion.TYPE_HEIGHT] != null:
		terrain.data.import_images.call_deferred(imported_images, region_origin_m, height_min, height_max - height_min)
		terrain.data.calc_height_range.call_deferred(true)
	if result.has("transforms") and result["transforms"].size() > 0:
		# If there are many transforms, batch them in chunks to avoid spikes
		var transforms: Array = result["transforms"]
		var batch_size := 1000
		for i in range(0, transforms.size(), batch_size):
			var batch := transforms.slice(i, i + batch_size)
			terrain.instancer.add_transforms.call_deferred(0, batch)
	
	var loc: Vector2i = result.get("loc", Vector2i.ZERO)
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
