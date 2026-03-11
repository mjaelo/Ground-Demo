extends RefCounted
class_name CustomTerrainManager

const ChunkClass = preload("res://Ground/Services/custom_terrain_chunk.gd")

## Unified terrain chunk manager. Every location gets an instant low-res
## FAR chunk first. CLOSE/MEDIUM chunks upgrade them via worker threads.

const TIER_CLOSE := 0
const TIER_MEDIUM := 1
const TIER_FAR := 2

# ── Configuration (set before initialize) ─────────────────────────────
var close_radius: int = 4
var medium_radius: int = 10
var far_radius: int = 22
var close_resolution: int = 64
var medium_resolution: int = 24
var far_resolution: int = 8
var region_size: int = 256
var max_chunks_per_frame: int = 6
var max_concurrent_threads: int = 8
var unload_margin: int = 3
var stream_check_interval: float = 0.15
var max_far_per_frame: int = 60

# ── Internal state ────────────────────────────────────────────────────
var _chunks: Dictionary = {}          # Vector2i -> CustomTerrainChunk
var _generating: Dictionary = {}      # Vector2i -> Thread
var _gen_results: Array = []
var _stream_timer: float = 0.0

# ── References ────────────────────────────────────────────────────────
var _noise: FastNoiseLite = null
var _biome_manager: BiomeManager = null
var _mesh_placement = null
var _parent: Node = null
var _player: Node3D = null
var _shader_material: ShaderMaterial = null
var _far_material: StandardMaterial3D = null
var _texture_manager: TerrainTextureManager = null

var _height_min: float = 0.0
var _height_max: float = 800.0
var _world_offset: Vector3 = Vector3.ZERO
var _sample_height_fn: Callable = Callable()
var _sample_normal_fn: Callable = Callable()

func initialize(
	parent: Node, player: Node3D, noise: FastNoiseLite,
	biome_manager: BiomeManager, mesh_placement,
	texture_manager: TerrainTextureManager,
	height_min: float, height_max: float,
	sample_height_fn: Callable, sample_normal_fn: Callable,
) -> void:
	_parent = parent
	_player = player
	_noise = noise
	_biome_manager = biome_manager
	_mesh_placement = mesh_placement
	_texture_manager = texture_manager
	_height_min = height_min
	_height_max = height_max
	_sample_height_fn = sample_height_fn
	_sample_normal_fn = sample_normal_fn
	_build_shader_material()
	_build_far_material()

# ── Materials ─────────────────────────────────────────────────────────

func _build_shader_material() -> void:
	var shader: Shader = load("res://Ground/Services/terrain_blend.gdshader")
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = shader
	if _texture_manager:
		var t := _texture_manager.loaded_textures
		if t.has("rock"):  _shader_material.set_shader_parameter("tex_rock", t["rock"])
		if t.has("grass"): _shader_material.set_shader_parameter("tex_grass", t["grass"])
		if t.has("mud"):   _shader_material.set_shader_parameter("tex_mud", t["mud"])
	_shader_material.set_shader_parameter("texture_scale", 16.0)
	_shader_material.set_shader_parameter("region_size", float(region_size))

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
		_update_chunks()

func get_height_at(world_pos: Vector3) -> float:
	var loc := _world_to_loc(world_pos)
	if _chunks.has(loc) and _chunks[loc].heightmap:
		return _sample_heightmap(_chunks[loc].heightmap, world_pos, loc)
	return _sample_height_fn.call(world_pos.x, world_pos.z)

func has_collision_at(world_pos: Vector3) -> bool:
	var loc := _world_to_loc(world_pos)
	return _chunks.has(loc) and _chunks[loc].collision_body != null

func _world_to_loc(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / float(region_size)), floori(pos.z / float(region_size)))

func _sample_heightmap(img: Image, world_pos: Vector3, loc: Vector2i) -> float:
	var res: int = img.get_width()
	var lx: float = world_pos.x - loc.x * region_size
	var lz: float = world_pos.z - loc.y * region_size
	var px: int = clampi(int(lx / float(region_size) * (res - 1)), 0, res - 1)
	var py: int = clampi(int(lz / float(region_size) * (res - 1)), 0, res - 1)
	return img.get_pixel(px, py).r

# ── World shift ───────────────────────────────────────────────────────

func shift_all(offset: Vector3, shift_loc: Vector2i) -> void:
	for loc in _generating.keys():
		var result = _generating[loc].wait_to_finish()
		if typeof(result) == TYPE_DICTIONARY:
			_gen_results.push_back(result)
	_generating.clear()
	var new_chunks: Dictionary = {}
	for loc in _chunks.keys():
		var nl: Vector2i = loc - shift_loc
		var c = _chunks[loc]
		c.loc = nl
		c.shift(offset)
		new_chunks[nl] = c
	_chunks = new_chunks
	for r in _gen_results:
		r["loc"] = r["loc"] - shift_loc

func drain_threads() -> void:
	for loc in _generating.keys():
		_generating[loc].wait_to_finish()
	_generating.clear()

# ── Chunk management ──────────────────────────────────────────────────

func _update_chunks() -> void:
	if not _parent or not _parent.is_inside_tree():
		return
	if not _player.is_inside_tree():
		return
	var player_pos: Vector3 = _player.global_transform.origin
	var player_loc := _world_to_loc(player_pos)

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
			var desired: int = TIER_CLOSE if dist <= close_radius else TIER_MEDIUM
			if _chunks.has(loc) and _chunks[loc].tier <= desired:
				continue
			if _generating.has(loc):
				continue
			upgrades.push_back({"loc": loc, "tier": desired, "dist": dist})

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
	var res: int = far_resolution
	var inv := 1.0 / float(res - 1)
	var bx: float = loc.x * region_size + _world_offset.x
	var bz: float = loc.y * region_size + _world_offset.z
	var scale: float = _height_max - _height_min

	var hm := Image.create_empty(res, res, false, Image.FORMAT_RF)
	for x in res:
		var nx: float = float(x) * inv * region_size + bx
		for y in res:
			var ny: float = float(y) * inv * region_size + bz
			var h: float = _noise.get_noise_2d(nx, ny)
			h = (h + 1.0) * 0.5
			h = pow(h, _biome_manager.get_height_curve(nx, ny))
			hm.set_pixel(x, y, Color(_height_min + h * scale, 0, 0, 1))

	var mesh := ChunkClass._build_mesh(hm, res, region_size)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _far_material
	mi.position = Vector3(loc.x * region_size, 0, loc.y * region_size)

	var chunk = ChunkClass.new()
	chunk.loc = loc
	chunk.tier = TIER_FAR
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

func _generate_chunk_data(loc: Vector2i, tier: int) -> Dictionary:
	var res: int = close_resolution if tier == TIER_CLOSE else medium_resolution
	var scale: float = _height_max - _height_min
	var bx: float = loc.x * region_size + _world_offset.x
	var bz: float = loc.y * region_size + _world_offset.z
	var inv := 1.0 / float(res - 1)

	var hm := Image.create_empty(res, res, false, Image.FORMAT_RF)
	for x in res:
		var nx: float = float(x) * inv * region_size + bx
		for y in res:
			var ny: float = float(y) * inv * region_size + bz
			var h: float = _noise.get_noise_2d(nx, ny)
			h = (h + 1.0) * 0.5
			h = pow(h, _biome_manager.get_height_curve(nx, ny))
			hm.set_pixel(x, y, Color(_height_min + h * scale, 0, 0, 1))

	var sm := Image.create_empty(res, res, false, Image.FORMAT_RGBA8)
	var cs: float = float(region_size) / float(res - 1)
	for x in res:
		var nx: float = float(x) * inv * region_size + bx
		for y in res:
			var ny: float = float(y) * inv * region_size + bz
			var hc: float = hm.get_pixel(x, y).r
			var hr: float = hc if x + 1 >= res else hm.get_pixel(x + 1, y).r
			var hd: float = hc if y + 1 >= res else hm.get_pixel(x, y + 1).r
			var slope: float = rad_to_deg(acos(clampf(Vector3(-(hr - hc) / cs, 1.0, -(hd - hc) / cs).normalized().dot(Vector3.UP), -1.0, 1.0)))
			var bw := _biome_manager._biome_weights(nx, ny)
			var r := 0.0; var g := 0.0; var b := 0.0
			for i in bw.size():
				if bw[i] < 0.01: continue
				var bd: BiomeData = _biome_manager.biomes[i]
				var bt: int = bd.steep_texture_id if slope > BiomeManager.STEEP_THRESHOLD else bd.flat_texture_id
				if bt == 0:   r += bw[i]
				elif bt == 1: g += bw[i]
				elif bt == 2: b += bw[i]
			sm.set_pixel(x, y, Color(r, g, b, 1.0))

	var tmap: Dictionary = {}
	if tier == TIER_CLOSE and _mesh_placement:
		tmap = _mesh_placement.generate_transforms(
			Vector3(loc.x * region_size, 0, loc.y * region_size),
			region_size, _sample_height_fn, _sample_normal_fn, _biome_manager)

	return {"loc": loc, "tier": tier, "heightmap": hm, "splatmap": sm, "transforms_by_mesh": tmap}

func _collect_finished_threads() -> void:
	var done: Array[Vector2i] = []
	for loc in _generating.keys():
		if not _generating[loc].is_alive():
			done.push_back(loc)
	for loc in done:
		var result = _generating[loc].wait_to_finish()
		_generating.erase(loc)
		if typeof(result) == TYPE_DICTIONARY:
			_gen_results.push_back(result)

func _apply_results() -> void:
	if not _parent or not _parent.is_inside_tree():
		return
	var ploc := _world_to_loc(_player.global_transform.origin)
	if _gen_results.size() > 1:
		_gen_results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["loc"] as Vector2i).distance_to(ploc) < (b["loc"] as Vector2i).distance_to(ploc))
	var applied := 0
	while _gen_results.size() > 0 and applied < max_chunks_per_frame:
		_apply_single_result(_gen_results.pop_front())
		applied += 1

func _apply_single_result(result: Dictionary) -> void:
	var loc: Vector2i = result["loc"]
	var tier: int = result["tier"]
	# Remove the old (FAR) chunk this replaces
	if _chunks.has(loc):
		_remove_chunk(loc)
	var chunk = ChunkClass.build_chunk(
		loc, tier, region_size,
		result["heightmap"], result["splatmap"],
		_shader_material, tier == TIER_CLOSE)
	_parent.add_child(chunk.mesh_instance)
	_chunks[loc] = chunk
	if tier == TIER_CLOSE and _mesh_placement:
		var tmap: Dictionary = result.get("transforms_by_mesh", {})
		for name in tmap.keys():
			if tmap[name].size() > 0:
				_mesh_placement.spawn_meshes(name, tmap[name], _parent, loc)
		chunk.mesh_assets_spawned = true

func _remove_chunk(loc: Vector2i) -> void:
	if _chunks.has(loc):
		_chunks[loc].destroy()
		_chunks.erase(loc)
	if _mesh_placement:
		_mesh_placement.clear_scene_meshes(loc)
