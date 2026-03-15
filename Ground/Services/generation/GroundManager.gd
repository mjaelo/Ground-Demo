extends RefCounted
class_name GroundManager

## Unified terrain chunk manager. Every location gets an instant low-res
## FAR chunk first. CLOSE/MEDIUM chunks upgrade them via worker threads.

# ── Configuration (set before initialize) ─────────────────────────────
var max_chunks_per_frame: int = 6
var max_concurrent_threads: int = 8
var unload_margin: int = 3
var stream_check_interval: float = 0.15
var max_far_per_frame: int = 60
# ── Internal state ────────────────────────────────────────────────────
var _chunks: Dictionary = {}          # Vector2i -> TerrainChunk
var _generating: Dictionary = {}      # Vector2i -> Thread
var pending_chunk_results: Array = []
var _stream_timer: float = 0.0

# ── References ────────────────────────────────────────────────────────
var _parent: Ground = null
var _player: Player = null
var _shader_material: ShaderMaterial = null
var _far_material: StandardMaterial3D = null

var _world_offset: Vector3 = Vector3.ZERO

# -- Texture loading ─────────────────────────────────
var loaded_textures: = [] # Array of TextureData objects


func initialize(parent: Ground, player: CharacterBody3D) -> void:
	_parent = parent
	_player = player
	_shader_material = _build_shader_material()
	_build_far_material()

# ── Materials ─────────────────────────────────────────────────────────

func _build_far_material() -> void:
	_far_material = StandardMaterial3D.new()
	_far_material.albedo_color = Color(0.32, 0.50, 0.22)
	_far_material.roughness = 1.0
	_far_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX

# ── Public API ────────────────────────────────────────────────────────

func set_world_offset(offset: Vector3) -> void:
	_world_offset = offset

func tick(delta: float) -> void:
	_collect_finished_threads()
	_apply_results()
	_stream_timer += delta
	if _stream_timer >= stream_check_interval:
		_stream_timer = 0.0
		update_visible_chunks()

func get_height_at(world_pos: Vector3) -> float:
	var loc := world_pos_to_chunk_loc(world_pos)
	if _chunks.has(loc) and _chunks[loc].heightmap:
		return sample_height_from_heightmap(_chunks[loc].heightmap, world_pos, loc)
	return _sample_height(world_pos.x, world_pos.z)

func has_collision_at(world_pos: Vector3) -> bool:
	var loc := world_pos_to_chunk_loc(world_pos)
	return _chunks.has(loc) and _chunks[loc].collision_body != null

func world_pos_to_chunk_loc(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / float(GroundConstants.CHUNK_SIZE)), floori(pos.z / float(GroundConstants.CHUNK_SIZE)))

func sample_height_from_heightmap(img: Image, world_pos: Vector3, loc: Vector2i) -> float:
	var res: int = img.get_width()
	var chunk_size := GroundConstants.CHUNK_SIZE
	var lx: float = world_pos.x - loc.x * chunk_size
	var lz: float = world_pos.z - loc.y * chunk_size
	var px: int = clampi(int(lx / float(chunk_size) * (res - 1)), 0, res - 1)
	var py: int = clampi(int(lz / float(chunk_size) * (res - 1)), 0, res - 1)
	return img.get_pixel(px, py).r
	
# ── Chunk management ──────────────────────────────────────────────────

func update_visible_chunks() -> void:
	var far_radius := GroundConstants.far_radius
	var medium_radius := GroundConstants.medium_radius
	var close_radius := GroundConstants.close_radius
	if not _parent or not _parent.is_inside_tree():
		return
	if not _player.is_inside_tree():
		return
	var player_pos: Vector3 = _player.global_transform.origin
	var player_loc := world_pos_to_chunk_loc(player_pos)

	# 1) Ensure every visible location has at least a FAR chunk (instant fill)
	var far_created := 0
	for x in range(player_loc.x - far_radius, player_loc.x + far_radius + 1):
		for y in range(player_loc.y - far_radius, player_loc.y + far_radius + 1):
			var loc := Vector2i(x, y)
			if loc.distance_to(player_loc) > far_radius:
				continue
			if _chunks.has(loc):
				continue  # Already has something — will be upgraded below
			if far_created >= max_far_per_frame:
				continue
			_create_far_chunk_sync(loc)
			far_created += 1

	# 2) Collect locations that need upgrades (CLOSE or MEDIUM)
	var upgrades: Array[Dictionary] = []
	for x in range(player_loc.x - medium_radius, player_loc.x + medium_radius + 1):
		for y in range(player_loc.y - medium_radius, player_loc.y + medium_radius + 1):
			var loc := Vector2i(x, y)
			var dist: float = loc.distance_to(player_loc)
			if dist > medium_radius:
				continue
			var desired_lod: int = GroundConstants.LOD_LEVELS.CLOSE if dist <= close_radius else GroundConstants.LOD_LEVELS.MEDIUM
			if _chunks.has(loc) and (_chunks[loc] as GroundChunk).lod_tier <= desired_lod:
				continue
			if _generating.has(loc):
				continue
			# TODO rename tier to lod_tier at least and change returned dictionary into an object
			upgrades.push_back({"loc": loc, "tier": desired_lod, "dist": dist})

	upgrades.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["tier"] != b["tier"]: return a["tier"] < b["tier"]
		return a["dist"] < b["dist"]
	)

	var slots: int = max_concurrent_threads - _generating.size()
	for item in upgrades:
		if slots <= 0:
			break
		_start_generation(item["loc"], item["tier"])
		slots -= 1

	# 3) Unload chunks too far away
	var to_remove: Array[Vector2i] = []
	for loc in _chunks.keys():
		if loc.distance_to(player_loc) > far_radius + unload_margin:
			to_remove.push_back(loc)
	for loc in to_remove:
		_remove_chunk(loc)

# ── FAR chunk: synchronous, minimal ──────────────────────────────────

func _create_far_chunk_sync(loc: Vector2i) -> void:
	var chunk_size := GroundConstants.CHUNK_SIZE
	var res: int = GroundConstants.far_resolution
	var result := _generate_heightmap_and_splatmap(loc, res, GroundConstants.LOD_LEVELS.FAR)
	var hm = result["heightmap"]
	var mesh := GroundChunk._build_mesh(hm, res)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _far_material
	mi.position = Vector3(loc.x * chunk_size, 0, loc.y * chunk_size)

	var chunk := GroundChunk.new()
	chunk.loc = loc
	chunk.lod_tier = GroundConstants.LOD_LEVELS.FAR
	chunk.heightmap = hm
	chunk.mesh_instance = mi
	_parent.add_child(mi)
	_chunks[loc] = chunk

# ── CLOSE / MEDIUM: threaded ─────────────────────────────────────────

func _start_generation(loc: Vector2i, tier: int) -> void:
	var thread := Thread.new()
	_generating[loc] = thread
	if thread.start(_generate_chunk_data.bind(loc, tier)) != OK:
		_generating.erase(loc)

# TODO create a ChunkData class
func _generate_chunk_data(loc: Vector2i, tier: int) -> Dictionary:
	var res: int = GroundConstants.close_resolution if tier == GroundConstants.LOD_LEVELS.CLOSE else GroundConstants.medium_resolution
	var chunk_size := GroundConstants.CHUNK_SIZE
	var result := _generate_heightmap_and_splatmap(loc, res, tier)
	var hm = result["heightmap"]
	var sm = result["splatmap"]

	var tmap: Dictionary = {}
	if tier == GroundConstants.LOD_LEVELS.CLOSE and _parent._mesh_placement_manager:
		tmap = _parent._mesh_placement_manager.generate_transforms(
			Vector3(loc.x * chunk_size, 0, loc.y * chunk_size),
			chunk_size, _sample_height, _sample_normal, _parent._biome_manager)

	return {"loc": loc, "tier": tier, "heightmap": hm, "splatmap": sm, "transforms_by_mesh": tmap}

## Shared logic for generating heightmap and splatmap for a chunk.
func _generate_heightmap_and_splatmap(loc: Vector2i, res: int, tier: int) -> Dictionary:
	var chunk_size := GroundConstants.CHUNK_SIZE
	var bx: float = loc.x * chunk_size + _world_offset.x
	var bz: float = loc.y * chunk_size + _world_offset.z
	var inv := 1.0 / float(res - 1)
	var scale: float = GroundConstants.height_max - GroundConstants.height_min

	var hm := Image.create_empty(res, res, false, Image.FORMAT_RF)
	for x in res:
		var nx: float = float(x) * inv * chunk_size + bx
		for y in res:
			var ny: float = float(y) * inv * chunk_size + bz
			var h: float = _parent._noise.get_noise_2d(nx, ny)
			h = (h + 1.0) * 0.5
			h = pow(h, _parent._biome_manager.get_height_curve(nx, ny))
			hm.set_pixel(x, y, Color(GroundConstants.height_min + h * scale, 0, 0, 1))

	var sm = null
	if tier != GroundConstants.LOD_LEVELS.FAR:
		sm = Image.create_empty(res, res, false, Image.FORMAT_RGBA8)
		var cs: float = float(chunk_size) / float(res - 1)
		for x in res:
			var nx: float = float(x) * inv * chunk_size + bx
			for y in res:
				var ny: float = float(y) * inv * chunk_size + bz
				var hc: float = hm.get_pixel(x, y).r
				var hr: float = hc if x + 1 >= res else hm.get_pixel(x + 1, y).r
				var hd: float = hc if y + 1 >= res else hm.get_pixel(x, y + 1).r
				var slope: float = rad_to_deg(acos(clampf(Vector3(-(hr - hc) / cs, 1.0, -(hd - hc) / cs).normalized().dot(Vector3.UP), -1.0, 1.0)))
				var bw := _parent._biome_manager._biome_weights(nx, ny)
				var r := 0.0; var g := 0.0; var b := 0.0
				for i in bw.size():
					if bw[i] < 0.01: continue
					var bd: BiomeData = _parent._biome_manager.biomes[i]
					var bt: int = bd.steep_texture_id if slope > GroundConstants.STEEP_THRESHOLD else bd.flat_texture_id
					if bt == 0:   r += bw[i]
					elif bt == 1: g += bw[i]
					elif bt == 2: b += bw[i]
				sm.set_pixel(x, y, Color(r, g, b, 1.0))

	return {"heightmap": hm, "splatmap": sm}

func _collect_finished_threads() -> void:
	var done: Array[Vector2i] = []
	for loc in _generating.keys():
		if not _generating[loc].is_alive():
			done.push_back(loc)
	for loc in done:
		var result = _generating[loc].wait_to_finish()
		_generating.erase(loc)
		if typeof(result) == TYPE_DICTIONARY:
			pending_chunk_results.push_back(result)

func _apply_results() -> void:
	if not _parent or not _parent.is_inside_tree():
		return
	var ploc := world_pos_to_chunk_loc(_player.global_transform.origin)
	if pending_chunk_results.size() > 1:
		pending_chunk_results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["loc"] as Vector2i).distance_to(ploc) < (b["loc"] as Vector2i).distance_to(ploc))
	var applied := 0
	while pending_chunk_results.size() > 0 and applied < max_chunks_per_frame:
		_apply_single_result(pending_chunk_results.pop_front())
		applied += 1

func _apply_single_result(result: Dictionary) -> void:
	var loc: Vector2i = result["loc"]
	var tier: int = result["tier"]
	# Remove the old (FAR) chunk this replaces
	if _chunks.has(loc):
		_remove_chunk(loc)
	var chunk := GroundChunk.build_chunk(
		loc, tier,
		result["heightmap"], result["splatmap"],
		_shader_material, tier == GroundConstants.LOD_LEVELS.CLOSE)
	_parent.add_child(chunk.mesh_instance)
	_chunks[loc] = chunk
	if tier == GroundConstants.LOD_LEVELS.CLOSE and _parent._mesh_placement_manager:
		var tmap: Dictionary = result.get("transforms_by_mesh", {})
		for name in tmap.keys():
			if tmap[name].size() > 0:
				_parent._mesh_placement_manager.spawn_meshes(name, tmap[name], _parent, loc)
		chunk.mesh_assets_spawned = true

func _remove_chunk(loc: Vector2i) -> void:
	if _chunks.has(loc):
		_chunks[loc].destroy()
		_chunks.erase(loc)
	if _parent._mesh_placement_manager:
		_parent._mesh_placement_manager.clear_scene_meshes(loc)

# ── Height / normal sampling ─────────────────────────────────────────

func _sample_height(world_x: float, world_z: float) -> float:
	var wx := world_x + _world_offset.x
	var wz := world_z + _world_offset.z
	var h := _parent._noise.get_noise_2d(wx, wz)
	h = (h + 1.0) * 0.5
	h = pow(h, _parent._biome_manager.get_height_curve(wx, wz))
	return GroundConstants.height_min + h * (GroundConstants.height_max - GroundConstants.height_min)

func _sample_normal(world_x: float, world_z: float) -> Vector3:
	var bh := _sample_height(world_x, world_z)
	var dx := _sample_height(world_x + 1.0, world_z) - bh
	var dz := _sample_height(world_x, world_z + 1.0) - bh
	return Vector3(-dx, 1.0, -dz).normalized()

# ── Shader material setup ───────────────────────────────────────────
func _build_shader_material() -> ShaderMaterial:
	var shader: Shader = load("res://Ground/Services/terrain_blend.gdshader")
	var shader_material := ShaderMaterial.new()
	shader_material.shader=shader
	for tData: TextureData in loaded_textures:
		var file_name := tData.texture_path.split('/')[-1].trim_suffix('.png')
		if tData.texture:
			shader_material.set_shader_parameter(file_name, tData.texture)
		else:
			push_warning("TextureData for %s missing texture resource!" % tData.texture_path)
	shader_material.set_shader_parameter("texture_scale", 16.0)
	shader_material.set_shader_parameter("region_size", float(GroundConstants.CHUNK_SIZE))
	return shader_material

## Load textures from JSON. No Terrain3D dependency.
func load_textures() -> void:
	loaded_textures = Utils.load_from_json(GroundConstants.TEXTURES_FILE_PATH, TextureData, "textures")
	# Load the actual Texture2D for each TextureData
	for tex_data in loaded_textures:
		if tex_data.texture_name.is_empty() or tex_data.texture_path.is_empty():
			push_warning("TerrainManager: texture entry missing name or path")
			continue
		var tex = load(tex_data.texture_path)
		if tex:
			tex_data.texture = tex
		else:
			push_warning("TerrainManager: Could not load texture at %s" % tex_data.texture_path)
