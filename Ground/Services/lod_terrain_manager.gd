extends RefCounted
class_name LodTerrainManager

## Generates and manages low-resolution placeholder meshes for distant terrain
## regions that haven't been fully generated yet.  These meshes give the player
## a visible horizon while the real heightmap/textures load in the background.
##
## Each LOD chunk is a simple MeshInstance3D with a PlaneMesh whose vertices are
## displaced on the GPU via a per-instance heightmap texture.  Because generating
## a 16×16 heightmap is ~256× cheaper than a full 256×256 one, LOD regions appear
## almost instantly.

# ── Configuration ─────────────────────────────────────────────────────
## Resolution of the LOD heightmap (vertices per side).  16 is plenty for
## distant terrain that's mostly a silhouette.
var lod_resolution: int = 16
## Number of mesh subdivisions for the LOD plane.
var lod_subdivisions: int = 15
## Maximum distance (in region units) at which LOD placeholders are shown.
var lod_radius: int = 20
## Maximum number of LOD meshes to create per frame to avoid stalls.
var max_lod_creates_per_frame: int = 4
## How often (seconds) to scan for missing LOD regions.  The scan itself
## is cheap; the mesh creation is budgeted separately.
var lod_scan_interval: float = 0.5

# ── Internal state ────────────────────────────────────────────────────
# loc -> MeshInstance3D
var _lod_meshes: Dictionary = {}
# loc -> true   — regions that are fully loaded (real heightmap present)
var _loaded_set: Dictionary = {}
# Queue of Vector2i locations that need LOD meshes, sorted closest-first.
var _pending_lod_queue: Array[Vector2i] = []
var _scan_timer: float = 0.0

# ── References ────────────────────────────────────────────────────────
var _generation_job: GenerationJob = null
var _parent: Node = null
var _terrain: Terrain3D = null
var _material: ShaderMaterial = null
var _texture_manager: TerrainTextureManager = null

func initialize(terrain: Terrain3D, generation_job: GenerationJob, parent: Node, texture_manager: TerrainTextureManager = null) -> void:
	_terrain = terrain
	_generation_job = generation_job
	_parent = parent
	_texture_manager = texture_manager
	_material = _create_lod_shader_material()

# ── Public API ────────────────────────────────────────────────────────

## Call from _process.  Creates LOD meshes for nearby-but-unloaded regions
## and removes ones that are too far or now fully loaded.
func update_lod(player_pos: Vector3, loaded_regions: Dictionary, delta: float = 0.016) -> void:
	_loaded_set = loaded_regions
	if not _terrain or not _terrain.data:
		return
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
			mesh_inst.global_transform.origin += position_offset
			new_dict[new_loc] = mesh_inst
	_lod_meshes = new_dict

## Remove every LOD mesh (e.g. during cleanup).
func clear_all() -> void:
	for loc in _lod_meshes.keys():
		_remove_lod(loc)
	_lod_meshes.clear()

# ── Private helpers ───────────────────────────────────────────────────

func _create_lod_mesh(loc: Vector2i, region_size: int) -> void:
	# Build a low-res heightmap image using the same noise as the real generator.
	var res: int = lod_resolution
	var img := Image.create_empty(res, res, false, Image.FORMAT_RF)

	# Track dominant texture for this region and average slope.
	var center_x := loc.x * region_size + region_size * 0.5 + _generation_job.world_offset.x
	var center_z := loc.y * region_size + region_size * 0.5 + _generation_job.world_offset.z
	var dominant_texture_id := 1  # Default to grass texture
	var total_slope := 0.0
	var slope_samples := 0

	for x in res:
		for y in res:
			# Sample at exact grid points (0, 1, 2, ..., res-1) to align with neighbors.
			var u := float(x) / float(res - 1)
			var v := float(y) / float(res - 1)
			var nx := u * region_size + loc.x * region_size + _generation_job.world_offset.x
			var ny := v * region_size + loc.y * region_size + _generation_job.world_offset.z
			var h := _generation_job.noise.get_noise_2d(nx, ny)
			h = (h + 1.0) * 0.5
			var curve_exp: float = _generation_job.biome_manager.get_height_curve(nx, ny)
			h = pow(h, curve_exp)
			var world_h: float = _generation_job.height_min + h * (_generation_job.height_max - _generation_job.height_min)
			img.set_pixel(x, y, Color(world_h, 0.0, 0.0, 1.0))

	# Calculate average slope across the region to decide flat vs steep texture.
	for x in range(res - 1):
		for y in range(res - 1):
			var slope := _calculate_slope_from_heightmap(img, x, y, region_size, res)
			total_slope += slope
			slope_samples += 1
	
	var avg_slope := total_slope / float(slope_samples) if slope_samples > 0 else 0.0

	# Get the biome at region center and pick texture based on slope.
	var biome := _generation_job.biome_manager.get_biome_at(center_x, center_z)
	if biome:
		# Use steep texture if average slope exceeds threshold (30 degrees).
		if avg_slope > 30.0:
			dominant_texture_id = biome.steep_texture_id
		else:
			dominant_texture_id = biome.flat_texture_id

	# Build ArrayMesh from the heightmap so we can displace vertices on the CPU.
	var mesh := _build_heightmap_mesh(img, res, region_size)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Place the mesh at the region's corner (matching Terrain3D coordinate system).
	# Terrain3D region origins are at the corner, not center.
	var origin := Vector3(loc.x * region_size, 0, loc.y * region_size)
	mesh_inst.global_transform.origin = origin

	# Use texture from the terrain if available, otherwise fall back to colored material.
	var mat := _create_lod_material(dominant_texture_id)
	mesh_inst.material_override = mat
	
	# Set visibility range so LOD meshes fade out at extreme distances and when
	# the real terrain loads nearby.
	mesh_inst.visibility_range_end = float(region_size) * 25.0
	mesh_inst.visibility_range_end_margin = float(region_size) * 2.0
	mesh_inst.visibility_range_begin = 0.0
	mesh_inst.visibility_range_begin_margin = float(region_size) * 0.5

	_parent.add_child(mesh_inst)
	_lod_meshes[loc] = mesh_inst

func _build_heightmap_mesh(img: Image, res: int, region_size: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Build vertex grid spanning from (0,0) to (region_size, region_size).
	# Sample at exact grid points (0, 1, ..., res-1) so adjacent regions share edge vertices.
	var verts: Array[Vector3] = []
	verts.resize(res * res)
	for y in res:
		for x in res:
			# Map vertex indices to exact positions: 0 → 0.0, res-1 → region_size
			var u := float(x) / float(res - 1)
			var v := float(y) / float(res - 1)
			var px := u * region_size
			var pz := v * region_size
			var h: float = img.get_pixel(x, y).r
			verts[y * res + x] = Vector3(px, h, pz)

	# Build triangles.
	for y in range(res - 1):
		for x in range(res - 1):
			var i00 := y * res + x
			var i10 := y * res + x + 1
			var i01 := (y + 1) * res + x
			var i11 := (y + 1) * res + x + 1

			# Compute normals for both triangles.
			var n1 := (verts[i10] - verts[i00]).cross(verts[i01] - verts[i00]).normalized()
			var n2 := (verts[i01] - verts[i11]).cross(verts[i10] - verts[i11]).normalized()

			# First triangle
			st.set_normal(n1)
			st.set_uv(Vector2(float(x) / float(res - 1), float(y) / float(res - 1)))
			st.add_vertex(verts[i00])
			st.set_normal(n1)
			st.set_uv(Vector2(float(x + 1) / float(res - 1), float(y) / float(res - 1)))
			st.add_vertex(verts[i10])
			st.set_normal(n1)
			st.set_uv(Vector2(float(x) / float(res - 1), float(y + 1) / float(res - 1)))
			st.add_vertex(verts[i01])

			# Second triangle
			st.set_normal(n2)
			st.set_uv(Vector2(float(x + 1) / float(res - 1), float(y + 1) / float(res - 1)))
			st.add_vertex(verts[i11])
			st.set_normal(n2)
			st.set_uv(Vector2(float(x) / float(res - 1), float(y + 1) / float(res - 1)))
			st.add_vertex(verts[i01])
			st.set_normal(n2)
			st.set_uv(Vector2(float(x + 1) / float(res - 1), float(y) / float(res - 1)))
			st.add_vertex(verts[i10])

	return st.commit()

## Calculate slope in degrees from a heightmap at given pixel coordinates.
func _calculate_slope_from_heightmap(img: Image, px: int, py: int, region_size: int, res: int) -> float:
	var h_c: float = img.get_pixel(px, py).r
	var h_r: float = h_c if px + 1 >= res else img.get_pixel(px + 1, py).r
	var h_d: float = h_c if py + 1 >= res else img.get_pixel(px, py + 1).r
	var cell_size: float = float(region_size) / float(res - 1)
	var dx: float = (h_r - h_c) / cell_size
	var dz: float = (h_d - h_c) / cell_size
	var n := Vector3(-dx, 1.0, -dz).normalized()
	return rad_to_deg(acos(clamp(n.dot(Vector3.UP), -1.0, 1.0)))

func _remove_lod(loc: Vector2i) -> void:
	if _lod_meshes.has(loc):
		var mesh_inst: MeshInstance3D = _lod_meshes[loc]
		if is_instance_valid(mesh_inst):
			mesh_inst.queue_free()
		_lod_meshes.erase(loc)

func _create_lod_shader_material() -> ShaderMaterial:
	# Placeholder — not used in the current CPU-displaced approach but
	# reserved for a future GPU vertex-displacement path.
	return null

## Create a material for LOD meshes using terrain textures if available.
func _create_lod_material(texture_id: int) -> Material:
	var mat := StandardMaterial3D.new()
	# Use UNSHADED mode - distant terrain doesn't need fancy lighting and this
	# prevents the texture from appearing too dark due to coarse vertex normals.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	
	# Set base color first (used if texture fails or as tint).
	# Brighter colors since we're not using lighting now.
	var color := Color(0.5, 0.7, 0.4, 1.0)  # Default bright green
	match texture_id:
		0:  # Rock
			color = Color(0.7, 0.7, 0.72, 1.0)
		1:  # Grass
			color = Color(0.5, 0.75, 0.4, 1.0)
		2:  # Mud
			color = Color(0.65, 0.55, 0.45, 1.0)
	mat.albedo_color = color
	
	var texture_loaded := false
	
	# Try texture manager first (most reliable - has direct texture references).
	if _texture_manager and _texture_manager.loaded_textures.size() > 0:
		# Map texture IDs to names based on texture_values.json.
		var tex_name := ""
		match texture_id:
			0: tex_name = "rock"
			1: tex_name = "grass"
			2: tex_name = "mud"
		
		if _texture_manager.loaded_textures.has(tex_name):
			var tex: Texture2D = _texture_manager.loaded_textures[tex_name]
			if tex:
				mat.albedo_texture = tex
				mat.uv1_scale = Vector3(4.0, 4.0, 4.0)
				mat.uv1_triplanar = false
				mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)  # No tint, use pure texture
				texture_loaded = true
	
	# Fallback: try Terrain3D assets.
	if not texture_loaded and _terrain and _terrain.assets:
		var tex_asset = _terrain.assets.get_texture(texture_id)
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
