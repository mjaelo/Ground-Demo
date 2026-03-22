@tool
extends Node
class_name Ground

## Main orchestrator for terrain generation, streaming, and enemy activation.
## World-shift has been removed: Godot handles large coordinates fine for
## the distances involved and the complexity was not justified.

# ── Terrain Generation ────────────────────────────────────────────────
var _noise := FastNoiseLite.new()

# ── Node references ──────────────────────────────────────────────────
var main: Main = null
@onready var nav_baker: RuntimeNavigationBaker = $NavBaker

# ── Managers ──────────────────────────────────────────────────────────
var _mesh_placement_manager: MeshAssetManager
var _biome_manager: BiomeManager
var _terrain_manager: GroundManager
var _mob_activation_manager: MobActivationManager # TODO should be placed in Mob directory?

# ── Lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	main = get_parent() as Main
	await main.ready
	_create_managers()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _terrain_manager:
		_terrain_manager.tick(delta)

# ── Setup ─────────────────────────────────────────────────────────────

func _create_managers() -> void:
	_noise.frequency = GroundConstants.NOISE_FREQUENCY

	_mesh_placement_manager = MeshAssetManager.new()
	_mesh_placement_manager.initialize(null)

	_biome_manager = BiomeManager.new()

	_terrain_manager = GroundManager.new()
	_terrain_manager.load_textures()
	_terrain_manager.initialize(self, main.player)

	_mob_activation_manager = MobActivationManager.new()
	_mob_activation_manager.initialize(main.enemy, main.player, nav_baker, _terrain_manager)

	# When the initial bulk load finishes, spawn the player and activate mobs
	_terrain_manager.initial_load_complete.connect(_mob_activation_manager.on_initial_load_complete)
	nav_baker.bake_finished.connect(_mob_activation_manager.on_nav_bake_finished)
