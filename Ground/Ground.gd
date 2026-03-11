@tool
extends Node

## Main orchestrator for terrain generation, streaming, world-shifting,
## and enemy activation.  Fully custom mesh-based system.

# ── Editor-exposed generation settings ────────────────────────────────
@export_group("Terrain Generation")
@export var noise_frequency: float = 0.0009
@export var height_min: float = 0.0
@export var height_max: float = 800.0
@export var region_size: int = 256

@export_group("Chunk LOD")
@export var close_radius: int = 4
@export var medium_radius: int = 10
@export var far_radius: int = 22
@export_range(16, 128, 8) var close_resolution: int = 64
@export_range(8, 64, 4) var medium_resolution: int = 24
@export_range(4, 32, 4) var far_resolution: int = 8

@export_group("Streaming")
@export_range(1, 16) var max_threads: int = 8
@export_range(1, 16) var max_chunks_per_frame: int = 6

@export_group("Editor Preview")
@export_range(1, 10) var editor_preview_radius: int = 3
@export var generate_in_editor: bool = false:
	set(v):
		generate_in_editor = false
		if v and Engine.is_editor_hint() and is_inside_tree():
			call_deferred("_editor_generate")
@export var clear_editor_terrain: bool = false:
	set(v):
		clear_editor_terrain = false
		if v and Engine.is_editor_hint() and is_inside_tree():
			call_deferred("_editor_clear")

# ── Node references ──────────────────────────────────────────────────
@onready var player: CharacterBody3D = $"../Player"
@onready var enemy: CharacterBody3D = $"Enemy"
@onready var nav_baker: Node = $"NavBaker"
@onready var ui: Control = $"../UI"

# ── Managers ──────────────────────────────────────────────────────────
var _texture_manager: TerrainTextureManager = null
var _mesh_placement_manager: MeshPlacementManager = null
var _biome_manager: BiomeManager = null
var _custom_terrain: CustomTerrainManager = null
var _world_shift: WorldShiftManager = null
var _enemy_manager: EnemyManager = null

# ── Noise ─────────────────────────────────────────────────────────────
var _noise := FastNoiseLite.new()

# ── State ─────────────────────────────────────────────────────────────
var _player_spawn_done: bool = false
var _world_offset := Vector3.ZERO

# ── Lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_setup_ui_and_player()
	_create_managers()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _world_shift and not _world_shift.shifting:
		_world_shift.check_and_shift()
	if _world_shift and _world_shift.shifting:
		return
	if _custom_terrain:
		_custom_terrain.tick(delta)
		if not _player_spawn_done:
			_try_player_spawn()

# ── Setup ─────────────────────────────────────────────────────────────

func _setup_ui_and_player() -> void:
	ui.player = player
	NavigationServer3D.set_debug_enabled(true)
	player.gravity_enabled = false
	player.collision_enabled = false
	await get_tree().process_frame

func _create_managers() -> void:
	_noise.frequency = noise_frequency

	_texture_manager = TerrainTextureManager.new()
	_texture_manager.load_textures()

	_mesh_placement_manager = MeshPlacementManager.new()
	_mesh_placement_manager.initialize(null)

	_biome_manager = BiomeManager.new()

	_custom_terrain = CustomTerrainManager.new()
	_custom_terrain.close_radius = close_radius
	_custom_terrain.medium_radius = medium_radius
	_custom_terrain.far_radius = far_radius
	_custom_terrain.close_resolution = close_resolution
	_custom_terrain.medium_resolution = medium_resolution
	_custom_terrain.far_resolution = far_resolution
	_custom_terrain.region_size = region_size
	_custom_terrain.max_chunks_per_frame = max_chunks_per_frame
	_custom_terrain.max_concurrent_threads = max_threads
	_custom_terrain.initialize(
		self, player, _noise, _biome_manager,
		_mesh_placement_manager, _texture_manager,
		height_min, height_max,
		Callable(self, "_sample_height"),
		Callable(self, "_sample_normal"),
	)

	_world_shift = WorldShiftManager.new()
	_world_shift.initialize(
		player, enemy, nav_baker,
		_custom_terrain, _mesh_placement_manager, region_size,
	)

	_enemy_manager = EnemyManager.new()
	_enemy_manager.initialize(enemy, player, nav_baker)
	_enemy_manager.set_height_sampler(Callable(_custom_terrain, "get_height_at"))

	nav_baker.player = player
	nav_baker.enabled = true
	nav_baker.bake_finished.connect(_enemy_manager.on_nav_bake_finished)

# ── Height / normal sampling ─────────────────────────────────────────

func _sample_height(world_x: float, world_z: float) -> float:
	var wx := world_x + _world_offset.x
	var wz := world_z + _world_offset.z
	var h := _noise.get_noise_2d(wx, wz)
	h = (h + 1.0) * 0.5
	h = pow(h, _biome_manager.get_height_curve(wx, wz))
	return height_min + h * (height_max - height_min)

func _sample_normal(world_x: float, world_z: float) -> Vector3:
	var bh := _sample_height(world_x, world_z)
	var dx := _sample_height(world_x + 1.0, world_z) - bh
	var dz := _sample_height(world_x, world_z + 1.0) - bh
	return Vector3(-dx, 1.0, -dz).normalized()

# ── Player spawning ──────────────────────────────────────────────────

func _try_player_spawn() -> void:
	if _player_spawn_done:
		return
	if not _custom_terrain.has_collision_at(player.global_transform.origin):
		return
	var h: float = _custom_terrain.get_height_at(player.global_transform.origin)
	print("[Ground] Spawning player at height %.1f" % h)
	player.global_transform.origin.y = h + 5.0
	player.gravity_enabled = true
	player.collision_enabled = true
	_player_spawn_done = true
	_enemy_manager.try_activate(true)

func on_world_shifted(new_offset: Vector3) -> void:
	_world_offset = new_offset
	_custom_terrain.set_world_offset(new_offset)

# ── Editor preview generation (uses our own mesh chunks) ──────────────

func _editor_generate() -> void:
	# Remove old editor preview children first
	_editor_clear()

	var tex_mgr := TerrainTextureManager.new()
	tex_mgr.load_textures()

	var biome_mgr := BiomeManager.new()
	var gen_noise := FastNoiseLite.new()
	gen_noise.frequency = noise_frequency
	var scale: float = height_max - height_min
	var r: int = editor_preview_radius
	var total: int = (2 * r + 1) * (2 * r + 1)

	# Build shader material for preview chunks
	var shader: Shader = load("res://Ground/Services/terrain_blend.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var tmap := tex_mgr.loaded_textures
	if tmap.has("rock"):  mat.set_shader_parameter("tex_rock", tmap["rock"])
	if tmap.has("grass"): mat.set_shader_parameter("tex_grass", tmap["grass"])
	if tmap.has("mud"):   mat.set_shader_parameter("tex_mud", tmap["mud"])
	mat.set_shader_parameter("texture_scale", 16.0)
	mat.set_shader_parameter("region_size", float(region_size))

	print("[EditorGen] Generating %d chunks at res %d..." % [total, close_resolution])

	var ChunkClass = preload("res://Ground/Services/custom_terrain_chunk.gd")

	for rx in range(-r, r + 1):
		for ry in range(-r, r + 1):
			var loc := Vector2i(rx, ry)
			var res: int = close_resolution
			var inv := 1.0 / float(res - 1)
			var bx: float = loc.x * region_size
			var bz: float = loc.y * region_size

			# Heightmap
			var hm := Image.create_empty(res, res, false, Image.FORMAT_RF)
			for x in res:
				var nx: float = float(x) * inv * region_size + bx
				for y in res:
					var ny: float = float(y) * inv * region_size + bz
					var h: float = gen_noise.get_noise_2d(nx, ny)
					h = (h + 1.0) * 0.5
					h = pow(h, biome_mgr.get_height_curve(nx, ny))
					hm.set_pixel(x, y, Color(height_min + h * scale, 0, 0, 1))

			# Splatmap
			var sm := Image.create_empty(res, res, false, Image.FORMAT_RGBA8)
			var cs: float = float(region_size) / float(res - 1)
			for x in res:
				var nx: float = float(x) * inv * region_size + bx
				for y in res:
					var ny: float = float(y) * inv * region_size + bz
					var hc: float = hm.get_pixel(x, y).r
					var hr: float = hc if x + 1 >= res else hm.get_pixel(x + 1, y).r
					var hd: float = hc if y + 1 >= res else hm.get_pixel(x, y + 1).r
					var slope: float = rad_to_deg(acos(clampf(
						Vector3(-(hr - hc) / cs, 1.0, -(hd - hc) / cs).normalized().dot(Vector3.UP), -1.0, 1.0)))
					var bw := biome_mgr._biome_weights(nx, ny)
					var wr := 0.0; var wg := 0.0; var wb := 0.0
					for i in bw.size():
						if bw[i] < 0.01: continue
						var bd: BiomeData = biome_mgr.biomes[i]
						var bt: int = bd.steep_texture_id if slope > BiomeManager.STEEP_THRESHOLD else bd.flat_texture_id
						if bt == 0:   wr += bw[i]
						elif bt == 1: wg += bw[i]
						elif bt == 2: wb += bw[i]
					sm.set_pixel(x, y, Color(wr, wg, wb, 1.0))

			var chunk = ChunkClass.build_chunk(loc, 0, region_size, hm, sm, mat, false)
			chunk.mesh_instance.name = "EditorChunk_%d_%d" % [rx, ry]
			add_child(chunk.mesh_instance)
			chunk.mesh_instance.owner = get_tree().edited_scene_root
			print("[EditorGen] (%d, %d) done" % [rx, ry])

	print("[EditorGen] Done! %d chunks." % total)

func _editor_clear() -> void:
	var to_remove: Array[Node] = []
	for child in get_children():
		if child.name.begins_with("EditorChunk_"):
			to_remove.push_back(child)
	for child in to_remove:
		child.queue_free()
	print("[EditorGen] Cleared %d preview chunks." % to_remove.size())
