@tool
extends Node
class_name Ground

## Main orchestrator for terrain generation, streaming, world-shifting and enemy activation.

# Terrain Generation
var _noise := FastNoiseLite.new()
var noise_frequency: float = 0.0009
var _world_offset := Vector3.ZERO

# ── Node references ──────────────────────────────────────────────────
@onready var player: CharacterBody3D = get_node_or_null("../Player")
@onready var enemy: CharacterBody3D = get_node_or_null("Enemy")
@onready var nav_baker: RuntimeNavigationBaker = get_node_or_null("NavBaker")
@onready var ui: Control = get_node_or_null("../UI")

# ── Managers ──────────────────────────────────────────────────────────
var _mesh_placement_manager: MeshAssetManager
var _biome_manager: BiomeManager
var _terrain_manager: GroundManager
var _shift_manager: WorldShiftManager
var _mob_activation_manager: MobActivationManager

# ── Lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_setup_ui_and_player()
	_create_managers()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _shift_manager:
		if _shift_manager.shifting:
			return
		_shift_manager.check_and_shift()
	if _terrain_manager:
		_terrain_manager.tick(delta)
		if !_mob_activation_manager._player_spawn_done:
			_mob_activation_manager._try_player_spawn()

# ── Setup ─────────────────────────────────────────────────────────────

func _setup_ui_and_player() -> void:
	if ui and player:
		ui.player = player
		NavigationServer3D.set_debug_enabled(true)
		player.gravity_enabled = false
		player.collision_enabled = false
		await get_tree().process_frame # TODO is this needed?

func _create_managers() -> void:
	_noise.frequency = noise_frequency

	_mesh_placement_manager = MeshAssetManager.new()
	_mesh_placement_manager.initialize(null)

	_biome_manager = BiomeManager.new()

	_terrain_manager = GroundManager.new()
	_terrain_manager.load_textures()
	_terrain_manager.initialize(self, player)

	_shift_manager = WorldShiftManager.new()
	_shift_manager.initialize(self)

	_mob_activation_manager = MobActivationManager.new()
	_mob_activation_manager.initialize(enemy, player, nav_baker, _terrain_manager)
	_mob_activation_manager.set_height_sampler(Callable(_terrain_manager, "get_height_at"))

	nav_baker.is_enabled = true # TODO for some reason, Invalid assignment of property or key 'is_enabled' with value of type 'bool' on a base object of type 'Node (RuntimeNavigationBaker)'.
	nav_baker.bake_finished.connect(_mob_activation_manager.on_nav_bake_finished)

func on_world_shifted(new_offset: Vector3) -> void:
	_world_offset = new_offset
	_terrain_manager.set_world_offset(new_offset)
