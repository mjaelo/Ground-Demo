@tool
extends Node
class_name Ground

## Main orchestrator for terrain generation, streaming, and enemy activation.
## World-shift has been removed: Godot handles large coordinates fine for
## the distances involved and the complexity was not justified.

# ── Terrain Generation ────────────────────────────────────────────────
var noise := FastNoiseLite.new()

# ── Node references ──────────────────────────────────────────────────
var main: Main = null
@onready var nav_baker: RuntimeNavigationBaker = $NavBaker

# ── Managers ──────────────────────────────────────────────────────────
var decor_manager: DecorManager
var biome_manager: BiomeManager
var terrain_manager: GroundManager
var mob_activation_manager: MobActivationManager # TODO should be placed in Mob directory?

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
	if terrain_manager:
		terrain_manager.tick(delta)

# ── Setup ─────────────────────────────────────────────────────────────

func _create_managers() -> void:
	noise.frequency = GroundConstants.NOISE_FREQUENCY

	decor_manager = DecorManager.new()
	decor_manager.initialize(null)

	biome_manager = BiomeManager.new()

	terrain_manager = GroundManager.new()
	terrain_manager.load_textures()
	terrain_manager.initialize(self, main.player)

	mob_activation_manager = MobActivationManager.new()
	mob_activation_manager.initialize(main.enemy, main.player, nav_baker, terrain_manager)

	# When the initial bulk load finishes, spawn the player and activate mobs
	terrain_manager.initial_load_complete.connect(mob_activation_manager.on_initial_load_complete)
	nav_baker.bake_finished.connect(mob_activation_manager.on_nav_bake_finished)
