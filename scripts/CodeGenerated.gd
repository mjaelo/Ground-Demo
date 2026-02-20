extends Node

# Width/height of the terrain region in meters.
@export var chunk_size := Terrain3D.RegionSize.SIZE_512
# Resolution of the generated heightmap image; higher = smoother but slower.
@export var heightmap_resolution: int = 512

# Lowest and highest terrain elevation (meters) used when importing the heightmap.
@export var height_min: float = 0.0
@export var height_max: float = 1000.0
# Noise frequency that shapes the terrain slopes/hills.
@export var noise_frequency: float = 0.0009
# Biome noise — very low frequency so biomes are much larger than regions.
# Lower = bigger biomes, higher = smaller biomes.
@export var biome_noise_frequency: float = 0.00015
# How much the biome noise shapes the terrain.
# biome_curve_flat: exponent in flat biomes — higher = flatter/lower ground (e.g. 4.0).
# biome_curve_mountain: exponent in mountain biomes — lower = taller sharper peaks (e.g. 0.4).
@export var biome_curve_flat: float = 5.0
@export var biome_curve_mountain: float = 0.4
# Mountains only appear where biome noise exceeds this threshold (0-1).
# 0.75 = top 25% of the world is mountains. Higher = rarer mountains.
@export var biome_mountain_threshold: float = 0.75
# How wide the flat->mountain transition band is (0-1 of noise range after threshold).
# Smaller = sharper edge, larger = wider gradual transition.
@export var biome_transition_width: float = 0.2
# Resolution of generated texture assets; higher = sharper textures.
@export var texture_resolution: int = 512
# Auto shader slope angle for texture blending (steeper gets brown). Raise to push brown onto steeper faces.
@export var auto_slope: float = 1.0
# Max slope (degrees) to still consider ground "green"; steeper is brown.
@export var ground_max_slope_deg: float = 28.0
# How sharp the blend is between materials; higher makes brown vs green separation clearer.
@export var blend_sharpness: float = 0.1
# How far to scatter grass/foliage; 0 uses the full terrain size.
@export var foliage_extent: int = 0
# Distance between placed foliage instances; lower = denser.
@export var foliage_step: int = 2
# Max slope (degrees) where grass/foliage is allowed; steeper spots stay bare/brown.
@export var foliage_max_slope_deg: float = 18.0
# Chance (0-1) to keep a foliage instance after slope check; lower = more sporadic.
@export var foliage_density: float = 0.25
# Number of chunks to keep loaded around the player (1 = 3x3 grid).
@export var stream_radius_chunks: int = 1
# How often (seconds) to check for streaming updates.
@export var stream_check_interval: float = 0.5

var _loaded_regions: Dictionary = {}
var _stream_timer := 0.0
# Track regions currently being generated off the main thread.
var _loading_regions: Dictionary = {}
var _generation_threads: Dictionary = {}
var _generation_results: Array = []
var _initial_player_region: Vector2i = Vector2i.ZERO
var _player_spawn_complete := false

func _ready() -> void:
	$UI.player = $Player
	NavigationServer3D.set_debug_enabled(false)
	$Player.gravity_enabled = false
	$Player.collision_enabled = false
	if $Terrain3D and $Terrain3D.data:
		_initial_player_region = $Terrain3D.data.get_region_location($Player.global_transform.origin)
	
	if has_node("RunThisSceneLabel3D"):
		$RunThisSceneLabel3D.queue_free()
	
	# Create textures
	var green_gr := Gradient.new()
	green_gr.set_color(0, Color.from_hsv(100./360., .35, .3))
	green_gr.set_color(1, Color.from_hsv(120./360., .4, .37))
	var green_ta: Terrain3DTextureAsset = create_texture_asset("Grass", green_gr, texture_resolution)
	green_ta.uv_scale = 0.1
	green_ta.detiling_rotation = 0.1

	var brown_gr := Gradient.new()
	brown_gr.set_color(0, Color(.32,.34,.3))
	brown_gr.set_color(1, Color(.4,.4,.4))
	var brown_ta: Terrain3DTextureAsset = create_texture_asset("Dirt", brown_gr, texture_resolution)
	brown_ta.uv_scale = 0.03
	green_ta.detiling_rotation = 0.1
	
	var grass_ma: Terrain3DMeshAsset = create_mesh_asset("Grass", Color.from_hsv(120./360., .4, .37))
	
	var terrain:Terrain3D = $Terrain3D
	configure_terrain_base(terrain, green_ta, brown_ta, grass_ma)

	# Bootstrap streaming around the player.
	_update_streaming(true)

	$NavBaker.terrain = terrain
	$NavBaker.player = $Player
	$NavBaker.enabled = true

func _process(delta: float) -> void:
	_stream_timer += delta
	if _stream_timer >= stream_check_interval:
		_stream_timer = 0.0
		_update_streaming()
	_collect_generation_results()
	_apply_pending_generation_results()

func configure_terrain_base(terrain:Terrain3D, green_ta:Terrain3DTextureAsset, brown_ta:Terrain3DTextureAsset, grass_ma:Terrain3DMeshAsset) -> Terrain3D:
	# Create a terrain
	var mat := Terrain3DMaterial.new()
	if mat == null:
		push_error("Terrain3DMaterial failed to load. Check addon binaries/version.")
		return terrain
	terrain.material = mat

	# Set material and assets
	terrain.material.world_background = Terrain3DMaterial.NONE
	terrain.material.auto_shader = true
	terrain.material.set_shader_param("auto_slope", auto_slope)
	terrain.material.set_shader_param("blend_sharpness", blend_sharpness)
	terrain.assets = Terrain3DAssets.new()
	# Texture 0 will now be the steep/slope (brown) and texture 1 the flatter base (green)
	terrain.assets.set_texture(0, brown_ta)
	terrain.assets.set_texture(1, green_ta)
	terrain.assets.set_mesh_asset(0, grass_ma)

	terrain.region_size = chunk_size
	return terrain

func _update_streaming(force: bool = false) -> void:
	var terrain: Terrain3D = $Terrain3D
	if not terrain or not terrain.data:
		return
	var player_pos: Vector3 = $Player.global_transform.origin
	var player_region: Vector2i = terrain.data.get_region_location(player_pos)
	if not force and _loaded_regions.has(player_region):
		# If player is still inside a loaded region and not forcing, we keep as is.
		pass

	var needed: Array[Vector2i]
	for x in range(player_region.x - stream_radius_chunks, player_region.x + stream_radius_chunks + 1):
		for y in range(player_region.y - stream_radius_chunks, player_region.y + stream_radius_chunks + 1):
			needed.push_back(Vector2i(x, y))
	# Add missing regions
	for loc in needed:
		if _loaded_regions.has(loc) or _loading_regions.has(loc):
			continue
		_start_region_generation(terrain, loc)
	# Remove distant regions
	var to_remove: Array[Vector2i] = []
	for loc in _loaded_regions.keys():
		if not needed.has(loc):
			_remove_region(terrain, loc)
			to_remove.push_back(loc)
	for loc in to_remove:
		_loaded_regions.erase(loc)

func _start_region_generation(terrain: Terrain3D, loc: Vector2i) -> void:
	var thread := Thread.new()
	_loading_regions[loc] = true
	_generation_threads[loc] = thread
	var job := {
		"loc": loc,
		"region_size": terrain.region_size,
		"heightmap_resolution": heightmap_resolution,
		"height_min": height_min,
		"height_max": height_max,
		"noise_frequency": noise_frequency,
		"biome_noise_frequency": biome_noise_frequency,
		"biome_curve_flat": biome_curve_flat,
		"biome_curve_mountain": biome_curve_mountain,
		"biome_mountain_threshold": biome_mountain_threshold,
		"biome_transition_width": biome_transition_width,
		"foliage_extent": foliage_extent,
		"foliage_step": foliage_step,
		"foliage_max_slope_deg": foliage_max_slope_deg,
		"foliage_density": foliage_density
	}
	var err := thread.start(Callable(self, "_generate_region_job").bind(job))
	if err != OK:
		_loading_regions.erase(loc)
		_generation_threads.erase(loc)
		push_error("Failed to start region generation thread: %s" % err)

func _collect_generation_results() -> void:
	for loc in _generation_threads.keys():
		var thread: Thread = _generation_threads[loc]
		if thread.is_alive():
			continue
		var result = thread.wait_to_finish()
		_generation_threads.erase(loc)
		if typeof(result) == TYPE_DICTIONARY:
			_generation_results.push_back(result)
		else:
			_loading_regions.erase(loc)

func _apply_pending_generation_results(max_per_frame: int = 1) -> void:
	var applied := 0
	while applied < max_per_frame and _generation_results.size() > 0:
		var result: Dictionary = _generation_results.pop_front()
		_apply_generation_result(result)
		applied += 1

func _generate_region_job(job: Dictionary) -> Dictionary:
	var loc: Vector2i = job.get("loc", Vector2i.ZERO)
	var region_meters: float = float(job.get("region_size", Terrain3D.RegionSize.SIZE_512))
	var region_origin_m := Vector3(loc.x * region_meters, 0, loc.y * region_meters)
	var noise := FastNoiseLite.new()
	noise.frequency = job.get("noise_frequency", noise_frequency)
	var biome_noise := FastNoiseLite.new()
	biome_noise.seed = 12345
	biome_noise.frequency = job.get("biome_noise_frequency", biome_noise_frequency)
	var hm_res: int = job.get("heightmap_resolution", heightmap_resolution)
	var img: Image = Image.create_empty(hm_res, hm_res, false, Image.FORMAT_RF)
	var world_size: float = region_meters
	for x in img.get_width():
		for y in img.get_height():
			var nx := (x / float(hm_res)) * world_size + loc.x * world_size
			var ny := (y / float(hm_res)) * world_size + loc.y * world_size
			var h := noise.get_noise_2d(nx, ny)
			h = (h + 1.0) * 0.5
			# Biome noise: very low frequency, smoothly controls terrain shape per world pos
			var b := biome_noise.get_noise_2d(nx, ny)
			b = (b + 1.0) * 0.5
			# Use smoothstep over transition_width after threshold so mountains are rare and edges smooth
			var threshold: float = job.get("biome_mountain_threshold", biome_mountain_threshold)
			var tw: float = max(job.get("biome_transition_width", biome_transition_width), 0.01)
			var t: float = smoothstep(threshold, threshold + tw, b)
			# t=0 -> flat biome, t=1 -> mountain biome
			var curve_exp: float = lerp(
				job.get("biome_curve_flat", biome_curve_flat),
				job.get("biome_curve_mountain", biome_curve_mountain),
				t
			)
			h = pow(h, curve_exp)
			img.set_pixel(x, y, Color(h, 0., 0., 1.))
	var transforms: Array[Transform3D]
	var width: int = job.get("foliage_extent", 0)
	if width <= 0:
		width = int(region_meters)
	var step: int = max(1, int(job.get("foliage_step", foliage_step)))
	var origin: Vector3 = region_origin_m + Vector3(-region_meters * 0.5, 0, -region_meters * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for x in range(0, width, step):
		for z in range(0, width, step):
			var pos_x := x + origin.x
			var pos_z := z + origin.z
			var h_val := _sample_height(noise, biome_noise, pos_x, pos_z, job)
			var pos := Vector3(pos_x, h_val, pos_z)
			var normal: Vector3 = _sample_normal(noise, biome_noise, pos_x, pos_z, job)
			var slope_deg := rad_to_deg(acos(clamp(normal.dot(Vector3.UP), -1.0, 1.0)))
			if slope_deg > job.get("foliage_max_slope_deg", foliage_max_slope_deg):
				continue
			if rng.randf() > job.get("foliage_density", foliage_density):
				continue
			transforms.push_back(Transform3D(Basis(), pos))
	return {
		"loc": loc,
		"region_origin": region_origin_m,
		"image": img,
		"transforms": transforms
	}

func _sample_height(noise: FastNoiseLite, biome_noise: FastNoiseLite, world_x: float, world_z: float, job: Dictionary) -> float:
	var h := noise.get_noise_2d(world_x, world_z)
	h = (h + 1.0) * 0.5
	var b := biome_noise.get_noise_2d(world_x, world_z)
	b = (b + 1.0) * 0.5
	var threshold: float = job.get("biome_mountain_threshold", biome_mountain_threshold)
	var tw: float = max(job.get("biome_transition_width", biome_transition_width), 0.01)
	var t: float = smoothstep(threshold, threshold + tw, b)
	var curve_exp: float = lerp(
		job.get("biome_curve_flat", biome_curve_flat),
		job.get("biome_curve_mountain", biome_curve_mountain),
		t
	)
	h = pow(h, curve_exp)
	var height_min_local: float = job.get("height_min", height_min)
	var import_scale: float = float(job.get("height_max", height_max)) - height_min_local
	return height_min_local + h * import_scale

func _sample_normal(noise: FastNoiseLite, biome_noise: FastNoiseLite, world_x: float, world_z: float, job: Dictionary) -> Vector3:
	var base_height := _sample_height(noise, biome_noise, world_x, world_z, job)
	var dx := _sample_height(noise, biome_noise, world_x + 1.0, world_z, job) - base_height
	var dz := _sample_height(noise, biome_noise, world_x, world_z + 1.0, job) - base_height
	return Vector3(-dx, 1.0, -dz).normalized()

func _apply_generation_result(result: Dictionary) -> void:
	var terrain: Terrain3D = $Terrain3D
	if not terrain or not terrain.data:
		return
	var loc: Vector2i = result.get("loc", Vector2i.ZERO)
	var imported_images: Array[Image]
	imported_images.resize(Terrain3DRegion.TYPE_MAX)
	imported_images[Terrain3DRegion.TYPE_HEIGHT] = result.get("image", null)
	var region_origin_m: Vector3 = result.get("region_origin", Vector3.ZERO)
	if imported_images[Terrain3DRegion.TYPE_HEIGHT] != null:
		terrain.data.import_images(imported_images, region_origin_m, height_min, height_max - height_min)
		terrain.data.calc_height_range(true)
	if result.has("transforms"):
		terrain.instancer.add_transforms(0, result["transforms"])
	terrain.collision.mode = Terrain3DCollision.DYNAMIC_EDITOR
	_loaded_regions[loc] = true
	_loading_regions.erase(loc)
	if not _player_spawn_complete and loc == _initial_player_region:
		var target_pos: Vector3 = $Player.global_transform.origin
		var h := terrain.data.get_height(target_pos)
		if is_nan(h):
			h = height_min + 2.0
		target_pos.y = h + 2.0
		$Player.global_transform = Transform3D($Player.global_transform.basis, target_pos)
		$Player.gravity_enabled = true
		$Player.collision_enabled = true
		_player_spawn_complete = true

func add_region(terrain:Terrain3D, xy:Vector2i) -> void:
	var region_meters: float = float(terrain.region_size)
	var region_origin_m := Vector3(xy.x * region_meters, 0, xy.y * region_meters)
	
	var noise := FastNoiseLite.new()
	noise.frequency = noise_frequency
	var img: Image = get_image(noise, Vector2(xy), region_meters)
	var import_scale := height_max - height_min
	var imported_images: Array[Image]
	imported_images.resize(Terrain3DRegion.TYPE_MAX)
	imported_images[Terrain3DRegion.TYPE_HEIGHT] = img
	terrain.data.import_images(imported_images, region_origin_m, height_min, import_scale)
	terrain.data.calc_height_range(true)
	
	var xforms: Array[Transform3D]
	var width: int = foliage_extent if foliage_extent > 0 else int(region_meters)
	var step: int = max(1, foliage_step)
	var origin: Vector3 = region_origin_m + Vector3(-region_meters * 0.5, 0, -region_meters * 0.5)
	for x in range(0, width, step):
		for z in range(0, width, step):
			var pos := Vector3(x, 0, z) + origin
			pos.y = terrain.data.get_height(pos)
			if is_nan(pos.y):
				continue
			var normal: Vector3 = terrain.data.get_normal(pos)
			var slope_deg := rad_to_deg(acos(clamp(normal.dot(Vector3.UP), -1.0, 1.0)))
			if slope_deg > foliage_max_slope_deg:
				continue
			if randf() > foliage_density:
				continue
			xforms.push_back(Transform3D(Basis(), pos))
	terrain.instancer.add_transforms(0, xforms)
	terrain.collision.mode = Terrain3DCollision.DYNAMIC_EDITOR

func get_image(noise:FastNoiseLite, ground_pos:Vector2, region_meters:float)-> Image:
	var img: Image = Image.create_empty(heightmap_resolution, heightmap_resolution, false, Image.FORMAT_RF)
	var world_size: float = region_meters
	for x in img.get_width():
		for y in img.get_height():
			var nx := (x / float(heightmap_resolution)) * world_size + ground_pos.x * world_size
			var ny := (y / float(heightmap_resolution)) * world_size + ground_pos.y * world_size
			var h := noise.get_noise_2d(nx, ny)
			h = (h + 1.0) * 0.5
			img.set_pixel(x, y, Color(h, 0., 0., 1.))
	return img

func create_texture_asset(asset_name: String, gradient: Gradient, texture_size: int = 512) -> Terrain3DTextureAsset:
	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.004
	var img := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	for x in range(texture_size):
		for y in range(texture_size):
			var n := fnl.get_noise_2d(x, y)
			n = (n + 1.0) * 0.5
			var c := gradient.sample(n)
			c.a = c.v
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var albedo := ImageTexture.create_from_image(img)

	var nrm_img := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	for x in range(texture_size):
		for y in range(texture_size):
			var n := fnl.get_noise_2d(x + 123.0, y + 456.0)
			n = (n + 1.0) * 0.5
			var normal := Color(0.5, 0.5, 1.0, 0.8)
			var bump := (n - 0.5) * 0.1
			normal.r = clamp(0.5 + bump, 0.0, 1.0)
			normal.g = clamp(0.5 - bump, 0.0, 1.0)
			nrm_img.set_pixel(x, y, normal)
	nrm_img.generate_mipmaps()
	var normal_tex := ImageTexture.create_from_image(nrm_img)

	var ta := Terrain3DTextureAsset.new()
	ta.name = asset_name
	ta.albedo_texture = albedo
	ta.normal_texture = normal_tex
	return ta

func create_mesh_asset(asset_name: String, color: Color) -> Terrain3DMeshAsset:
	var ma := Terrain3DMeshAsset.new()
	ma.name = asset_name
	ma.generated_type = Terrain3DMeshAsset.TYPE_TEXTURE_CARD
	ma.material_override.albedo_color = color
	return ma

func _remove_region(terrain: Terrain3D, loc: Vector2i) -> void:
	for region in terrain.data.get_regions_active():
		var region_loc: Vector2i = _get_region_location(region)
		if region_loc == loc:
			terrain.data.remove_region(region, true)
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
