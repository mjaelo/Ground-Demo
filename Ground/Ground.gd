extends Node

## Main orchestrator for terrain generation, streaming, world-shifting,
## and enemy activation.  All heavy logic lives in dedicated managers
## under Ground/Services/.

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
	_setup_ui_and_player()
	_create_managers()
	_connect_signals()
	_region_stream.start_missing_generation_threads()

func _process(delta: float) -> void:
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

	# Generation job
	_generation_job = GenerationJob.new()
	_generation_job.initialize(terrain, player, self, biome_manager, _mesh_placement_manager)

	# Region streaming
	_region_stream = RegionStreamManager.new()
	_region_stream.initialize(terrain, player, _generation_job, _mesh_placement_manager)

	# LOD terrain (distant placeholder meshes)
	_lod_terrain = LodTerrainManager.new()
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
