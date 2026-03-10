extends RefCounted
class_name LodTerrainManager

# ── Configuration ─────────────────────────────────────────────────────
var lod_resolution: int = 16
var lod_radius: int = 20
var max_lod_creates_per_frame: int = 4
var lod_scan_interval: float = 0.5

# ── Internal state ────────────────────────────────────────────────────
var _lod_meshes: Dictionary = {}
var _loaded_set: Dictionary = {}
var _pending_lod_queue: Array[Vector2i] = []
var _scan_timer: float = 0.0

# ── References ────────────────────────────────────────────────────────
var _generation_job: GenerationJob = null
var _parent: Node = null
var _terrain: Terrain3D = null
var _texture_manager: TerrainTextureManager = null

func initialize(terrain: Terrain3D, generation_job: GenerationJob, parent: Node, texture_manager: TerrainTextureManager = null) -> void:
	_terrain = terrain
	_generation_job = generation_job
	_parent = parent
	_texture_manager = texture_manager

# ── Public API ────────────────────────────────────────────────────────

## Call from _process.  Creates LOD meshes for nearby-but-unloaded regions
## and removes ones that are too far or now fully loaded.
func update_lod(player_pos: Vector3, loaded_regions: Dictionary, delta: float = 0.016) -> void:
	if not _parent or not _parent.is_inside_tree():
		return
	if not _terrain or not _terrain.data:
		return
	_loaded_set = loaded_regions
	var region_size: int = _terrain.region_size
	var player_region: Vector2i = _terrain.data.get_region_location(player_pos)

	# Periodic scan: rebuild the pending queue with any regions that still
	# need LOD meshes.  This is cheap (just dictionary lookups).
	_scan_timer += delta
	if _scan_timer >= lod_scan_interval or _pending_lod_queue.is_empty():
		_scan_timer = 0.0
		_rebuild_pending_queue(player_region)

	# Create a few LOD meshes this frame (budget).
	var created := 0
	while _pending_lod_queue.size() > 0 and created < max_lod_creates_per_frame:
		var loc: Vector2i = _pending_lod_queue.pop_front()
		# Skip if it became loaded or already has an LOD mesh in the meantime.
		if _loaded_set.has(loc) or _lod_meshes.has(loc):
			continue
		if loc.distance_to(player_region) > lod_radius:
			continue
		_create_lod_mesh(loc, region_size)
		created += 1

	# Clean up LOD meshes that are out of range or now loaded.
	var to_remove: Array[Vector2i] = []
	for loc in _lod_meshes.keys():
		if _loaded_set.has(loc) or loc.distance_to(player_region) > lod_radius + 2:
			to_remove.push_back(loc)
	for loc in to_remove:
		_remove_lod(loc)

## Rebuild the pending LOD queue sorted closest-first.
func _rebuild_pending_queue(player_region: Vector2i) -> void:
	_pending_lod_queue.clear()
	for x in range(player_region.x - lod_radius, player_region.x + lod_radius + 1):
		for y in range(player_region.y - lod_radius, player_region.y + lod_radius + 1):
			var loc := Vector2i(x, y)
			if loc.distance_to(player_region) > lod_radius:
				continue
			if _loaded_set.has(loc) or _lod_meshes.has(loc):
				continue
			_pending_lod_queue.push_back(loc)
	# Sort closest first so the area around the player fills in first.
	_pending_lod_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_to(player_region) < b.distance_to(player_region)
	)

## Mark a region as fully loaded so its LOD mesh gets cleaned up.
func mark_loaded(loc: Vector2i) -> void:
	_loaded_set[loc] = true
	_remove_lod(loc)

## Shift all LOD meshes after a world-origin shift.
func shift_all(position_offset: Vector3, shift_loc: Vector2i) -> void:
	var new_dict: Dictionary = {}
	for loc in _lod_meshes.keys():
		var new_loc: Vector2i = loc - shift_loc
		var mesh_inst: MeshInstance3D = _lod_meshes[loc]
		if is_instance_valid(mesh_inst):
			mesh_inst.position += position_offset
			new_dict[new_loc] = mesh_inst
	_lod_meshes = new_dict

## Remove every LOD mesh (e.g. during cleanup).
func clear_all() -> void:
	for loc in _lod_meshes.keys():
		_remove_lod(loc)
	_lod_meshes.clear()

# ── Private helpers ───────────────────────────────────────────────────

func _create_lod_mesh(loc: Vector2i, region_size: int) -> void:
	if not _parent or not _parent.is_inside_tree():
		return
	# Use shared utility for heightmap
	var res: int = lod_resolution
	var img := TerrainMeshUtils.generate_heightmap(loc, region_size, res, _generation_job.noise, _generation_job.biome_manager, _generation_job.world_offset, _generation_job.height_min, _generation_job.height_max)

	# Track dominant texture for this region and average slope.
	var center_x := loc.x * region_size + region_size * 0.5 + _generation_job.world_offset.x
	var center_z := loc.y * region_size + region_size * 0.5 + _generation_job.world_offset.z
	var dominant_texture_id := 1  # Default to grass texture
	var total_slope := 0.0
	var slope_samples := 0

	for x in range(res - 1):
		for y in range(res - 1):
			var slope := TerrainMeshUtils.calculate_slope_from_heightmap(img, x, y, region_size, res)
			total_slope += slope
			slope_samples += 1
	var avg_slope := total_slope / float(slope_samples) if slope_samples > 0 else 0.0

	# Get the biome at region center and pick texture based on slope.
	var biome := _generation_job.biome_manager.get_biome_at(center_x, center_z)
	if biome:
		if avg_slope > 30.0:
			dominant_texture_id = biome.steep_texture_id
		else:
			dominant_texture_id = biome.flat_texture_id

	# Use shared utility for mesh
	var mesh := TerrainMeshUtils.build_heightmap_mesh(img, res, region_size)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: Material = _create_lod_material(dominant_texture_id)
	mesh_inst.material_override = mat
	mesh_inst.visibility_range_end = float(region_size) * 25.0
	mesh_inst.visibility_range_end_margin = float(region_size) * 2.0
	mesh_inst.visibility_range_begin = 0.0
	mesh_inst.visibility_range_begin_margin = float(region_size) * 0.5
	_parent.add_child(mesh_inst)
	mesh_inst.position = Vector3(loc.x * region_size, 0, loc.y * region_size)
	_lod_meshes[loc] = mesh_inst

static func _create_lod_material_static(texture_id: int, terrain, texture_manager) -> Material:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var color: Color = Color(0.5, 0.7, 0.4, 1.0)
	match texture_id:
		0: color = Color(0.7, 0.7, 0.72, 1.0)
		1: color = Color(0.5, 0.75, 0.4, 1.0)
		2: color = Color(0.65, 0.55, 0.45, 1.0)
	mat.albedo_color = color
	var texture_loaded := false
	if texture_manager and texture_manager.loaded_textures.size() > 0:
		var tex_name := ""
		match texture_id:
			0: tex_name = "rock"
			1: tex_name = "grass"
			2: tex_name = "mud"
		if texture_manager.loaded_textures.has(tex_name):
			var tex = texture_manager.loaded_textures[tex_name]
			if tex:
				mat.albedo_texture = tex
				mat.uv1_scale = Vector3(4.0, 4.0, 4.0)
				mat.uv1_triplanar = false
				mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
				texture_loaded = true
	if not texture_loaded and terrain and terrain.assets:
		var tex_asset = terrain.assets.get_texture(texture_id)
		if tex_asset:
			var albedo_tex = tex_asset.get_albedo_texture()
			if albedo_tex:
				mat.albedo_texture = albedo_tex
				mat.uv1_scale = Vector3(4.0, 4.0, 4.0)
				mat.uv1_triplanar = false
				mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
				texture_loaded = true
	if not texture_loaded:
		print("[LOD] Using color fallback for texture ID %d (color: %s)" % [texture_id, color])
	return mat

func _remove_lod(loc: Vector2i) -> void:
	if _lod_meshes.has(loc):
		var mesh_inst = _lod_meshes[loc]
		if is_instance_valid(mesh_inst):
			mesh_inst.queue_free()
		_lod_meshes.erase(loc)

func _create_lod_material(texture_id: int) -> Material:
	return LodTerrainManager._create_lod_material_static(texture_id, _terrain, _texture_manager)
