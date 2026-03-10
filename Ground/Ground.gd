@tool
extends Node

## Main orchestrator for terrain generation, streaming, world-shifting,
## and enemy activation.  All heavy logic lives in dedicated managers
## under Ground/Services/.

# ── Editor-exposed generation settings ────────────────────────────────
@export_group("Terrain Generation")
@export var noise_frequency: float = 0.0009
@export var height_min: float = 0.0
@export var height_max: float = 800.0

@export_group("Streaming")
## Radius (in region-chunks) around the player to stream.
@export var stream_radius: int = 20
## Maximum concurrent generation threads.
@export_range(1, 16) var max_threads: int = 8
## How many finished region results are applied per frame.
@export_range(1, 16) var max_results_per_frame: int = 6

@export_group("LOD")
## LOD placeholder mesh resolution (vertices per side).
@export_range(4, 64, 4) var lod_resolution: int = 16
## LOD radius in region-chunks.
@export var lod_radius: int = 20

@export_group("Editor Preview")
## How many regions to generate around origin in the editor preview.
@export_range(1, 10) var editor_preview_radius: int = 3
## Check this box to generate terrain in the editor viewport.
@export var generate_in_editor: bool = false:
	set(v):
		generate_in_editor = v
		if v and Engine.is_editor_hint():
			# Use call_deferred so the node tree is fully ready
			call_deferred("_editor_generate")
## Check this box to clear all terrain regions in the editor.
@export var clear_editor_terrain: bool = false:
	set(v):
		clear_editor_terrain = v
		if v and Engine.is_editor_hint():
			call_deferred("_editor_clear")

# ── Node references ──────────────────────────────────────────────────
@onready var player: CharacterBody3D = $"../Player"
@onready var enemy: CharacterBody3D = $"Enemy"
@onready var nav_baker: Node = $"NavBaker"
@onready var ui: Control = $"../UI"
@onready var terrain: Terrain3D = $Terrain3D

# ── Managers (code-only, created in _ready) ──────────────────────────
var _texture_manager: TerrainTextureManager = null
var _mesh_placement_manager: MeshPlacementManager = null
var _generation_job: GenerationJob = null
var _region_stream: RegionStreamManager = null
var _world_shift: WorldShiftManager = null
var _enemy_manager: EnemyManager = null
var _lod_terrain: LodTerrainManager = null

# ── State ─────────────────────────────────────────────────────────────
var _player_spawn_done: bool = false

# ── Lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_setup_ui_and_player()
	_create_managers()
	_connect_signals()
	# Register any regions already present in Terrain3D (e.g. editor-
	# pregenerated) so they aren't regenerated or covered by LOD meshes.
	_region_stream.register_existing_regions()
	# If the player's starting region already has valid height data,
	# spawn them immediately instead of waiting for a generation result.
	_try_immediate_player_spawn()
	_region_stream.start_missing_generation_threads()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _world_shift.shifting:
		_world_shift.check_and_shift()
	if _world_shift.shifting:
		return
	_region_stream.tick(delta)
	# Update LOD placeholders for distant regions.
	if _lod_terrain:
		_lod_terrain.update_lod(
			player.global_transform.origin,
			_region_stream.get_loaded_regions(),
			delta
		)

# ── Setup helpers ─────────────────────────────────────────────────────

func _setup_ui_and_player() -> void:
	ui.player = player
	NavigationServer3D.set_debug_enabled(true)
	player.gravity_enabled = false
	player.collision_enabled = false
	terrain.collision.mode = Terrain3DCollision.DYNAMIC_EDITOR
	await get_tree().process_frame

func _create_managers() -> void:
	# Texture manager
	_texture_manager = TerrainTextureManager.new()
	_texture_manager.initialize(terrain)

	# Mesh placement
	_mesh_placement_manager = MeshPlacementManager.new()
	_mesh_placement_manager.initialize(terrain)

	# Biome manager
	var biome_manager := BiomeManager.new()

	# Generation job — apply editor-exposed settings
	_generation_job = GenerationJob.new()
	_generation_job.noise_frequency = noise_frequency
	_generation_job.height_min = height_min
	_generation_job.height_max = height_max
	_generation_job.initialize(terrain, player, self, biome_manager, _mesh_placement_manager)

	# Region streaming — apply editor-exposed settings
	_region_stream = RegionStreamManager.new()
	_region_stream.stream_radius_chunks = stream_radius
	_region_stream.max_concurrent_threads = max_threads
	_region_stream.max_results_per_frame = max_results_per_frame
	_region_stream.initialize(terrain, player, _generation_job, _mesh_placement_manager)

	# LOD terrain (distant placeholder meshes) — apply editor-exposed settings
	_lod_terrain = LodTerrainManager.new()
	_lod_terrain.lod_resolution = lod_resolution
	_lod_terrain.lod_radius = lod_radius
	_lod_terrain.initialize(terrain, _generation_job, self, _texture_manager)

	# World shifting
	_world_shift = WorldShiftManager.new()
	_world_shift.initialize(
		terrain, player, enemy, nav_baker,
		_region_stream, _mesh_placement_manager,
		_generation_job, get_tree(), _lod_terrain
	)

	# Enemy manager
	_enemy_manager = EnemyManager.new()
	_enemy_manager.initialize(enemy, player, terrain, nav_baker)

	# Nav baker
	nav_baker.terrain = terrain
	nav_baker.player = player
	nav_baker.enabled = true

func _connect_signals() -> void:
	_generation_job.player_spawned.connect(_on_player_spawned)
	nav_baker.bake_finished.connect(_enemy_manager.on_nav_bake_finished)

## If the player's starting region already has valid terrain data
## (editor-pregenerated), spawn them immediately without waiting for
## a generation thread result.
func _try_immediate_player_spawn() -> void:
	if _player_spawn_done:
		return
	if not terrain or not terrain.data:
		return
	var h: float = terrain.data.get_height(player.global_transform.origin)
	if is_nan(h):
		# No terrain under the player yet — will spawn via generation result.
		return
	print("[Ground] Pregenerated terrain detected under player — spawning immediately")
	# Mark the generation job as spawn-complete so it doesn't try again.
	_generation_job._player_spawn_complete = true
	# Place the player on the terrain.
	player.global_transform.origin.y = h + 5.0
	player.gravity_enabled = true
	player.collision_enabled = true
	_generation_job.player_spawned.emit(terrain)

# ── Signal callbacks ──────────────────────────────────────────────────

func _on_player_spawned(_t: Variant = null) -> void:
	_player_spawn_done = true
	_enemy_manager.try_activate(_player_spawn_done)

# ── Deferred callbacks (called by GenerationJob) ─────────────────────

func _deferred_player_spawn() -> void:
	_generation_job.initiate_player_spawn()

func _apply_generation_result_deferred(result: Dictionary) -> void:
	_generation_job.apply_generation_result_deferred(result)

## Called by GenerationJob when a region finishes importing.
func _mark_region_loaded(loc: Vector2i) -> void:
	_region_stream.mark_loaded(loc)
	if _lod_terrain:
		_lod_terrain.mark_loaded(loc)

# ── Editor terrain generation ─────────────────────────────────────────

func _editor_generate() -> void:
	# Reset the toggle so it can be pressed again
	generate_in_editor = false

	var t: Terrain3D = get_node_or_null("Terrain3D")
	if not t:
		push_error("[EditorGen] No Terrain3D child node found")
		return
	if not t.data:
		push_error("[EditorGen] Terrain3D has no data resource. Make sure data_directory is set.")
		return

	# Setup texture manager for editor
	var tex_mgr := TerrainTextureManager.new()
	tex_mgr.initialize(t)

	var biome_mgr := BiomeManager.new()
	var gen_noise := FastNoiseLite.new()
	gen_noise.frequency = noise_frequency
	var region_size: int = t.region_size
	# Must use region_size as resolution — Terrain3D requires it.
	var res: int = region_size
	var import_scale: float = height_max - height_min
	var r: int = editor_preview_radius
	var total_regions: int = (2 * r + 1) * (2 * r + 1)

	print("[EditorGen] Generating %d regions at %dx%d resolution (region_size=%d)..." % [total_regions, res, res, region_size])

	for rx in range(-r, r + 1):
		for ry in range(-r, r + 1):
			var loc := Vector2i(rx, ry)
			var img: Image = Image.create_empty(res, res, false, Image.FORMAT_RF)
			var ctrl: Image = Image.create_empty(res, res, false, Image.FORMAT_RF)
			var inv_res := 1.0 / float(res)
			var base_x: float = loc.x * region_size
			var base_z: float = loc.y * region_size

			# Pass 1: heightmap
			for x in res:
				var nx: float = (x * inv_res) * region_size + base_x
				for y in res:
					var ny: float = (y * inv_res) * region_size + base_z
					var h: float = gen_noise.get_noise_2d(nx, ny)
					h = (h + 1.0) * 0.5
					var curve_exp: float = biome_mgr.get_height_curve(nx, ny)
					h = pow(h, curve_exp)
					img.set_pixel(x, y, Color(height_min + h * import_scale, 0., 0., 1.))

			# Pass 2: control map
			var cell_size: float = float(region_size) / float(res - 1)
			for x in res:
				var nx: float = (x * inv_res) * region_size + base_x
				for y in res:
					var ny: float = (y * inv_res) * region_size + base_z
					var h_c: float = img.get_pixel(x, y).r
					var h_r: float = h_c if x + 1 >= res else img.get_pixel(x + 1, y).r
					var h_d: float = h_c if y + 1 >= res else img.get_pixel(x, y + 1).r
					var dx_val: float = (h_r - h_c) / cell_size
					var dz_val: float = (h_d - h_c) / cell_size
					var slope_deg: float = rad_to_deg(acos(clampf(Vector3(-dx_val, 1.0, -dz_val).normalized().dot(Vector3.UP), -1.0, 1.0)))
					ctrl.set_pixel(x, y, Color(biome_mgr.get_encoded_control(nx, ny, slope_deg), 0., 0., 1.))

			var region_origin := Vector3(loc.x * region_size, 0, loc.y * region_size)
			var imported_images: Array[Image]
			imported_images.resize(Terrain3DRegion.TYPE_MAX)
			imported_images[Terrain3DRegion.TYPE_HEIGHT] = img
			imported_images[Terrain3DRegion.TYPE_CONTROL] = ctrl
			t.data.import_images(imported_images, region_origin, 0.0, 1.0)
			print("[EditorGen] Region (%d, %d) done" % [rx, ry])

	t.data.calc_height_range(true)
	print("[EditorGen] Done! Generated %d regions." % total_regions)

func _editor_clear() -> void:
	# Reset the toggle so it can be pressed again
	clear_editor_terrain = false

	var t: Terrain3D = get_node_or_null("Terrain3D")
	if not t or not t.data:
		return
	var regions = t.data.get_regions_active()
	for region in regions:
		t.data.remove_region(region)
	print("[EditorGen] Cleared all terrain regions.")
