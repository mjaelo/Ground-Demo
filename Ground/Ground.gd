@tool
extends Node
class_name Ground

## Main orchestrator for terrain generation, streaming, and enemy activation.
## World-shift has been removed: Godot handles large coordinates fine for
## the distances involved and the complexity was not justified.

# ── Terrain Generation ────────────────────────────────────────────────
var noise := FastNoiseLite.new()
var is_initial_load_done: bool = false
var _focus_loc: Vector2i = Vector2i.ZERO

# ── Node references ──────────────────────────────────────────────────
var main: Main = null
@onready var nav_baker: RuntimeNavigationBaker = $NavBaker

# ── Managers ──────────────────────────────────────────────────────────
var decor_manager: DecorManager
var biome_manager: BiomeManager
var texture_manager: TextureManager
var chunk_manager: ChunkManager
var ground_thread_manager: GroundThreadManager
var mob_activation_manager: MobActivationManager # TODO should be placed in Mob directory?
var player_boundary: PlayerBoundary

# ── Lifecycle ─────────────────────────────────────────────────────────

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	main = get_parent() as Main
	await main.ready
	noise.frequency = GroundConstants.NOISE_FREQUENCY
	_create_managers()

func _process(_delta: float) -> void: # TODO can be done more rarely
	if Engine.is_editor_hint():
		return
	var focus_loc := _focus_loc
	if main != null and main.player != null:
		focus_loc = GroundUtils.world_pos_to_chunk_loc(main.player.global_transform.origin)
		_focus_loc = focus_loc
	ground_thread_manager.handle_thread_results(focus_loc)
	chunk_manager.update_visible_chunks(focus_loc)
	if is_initial_load_done:
		player_boundary.update(focus_loc)
	elif are_nearby_chunks_ready(focus_loc):
		ground_thread_manager.set_steady_values()
		mob_activation_manager.activate_mobs()
		is_initial_load_done = true

# ── Setup ─────────────────────────────────────────────────────────────
func _create_managers() -> void:
	biome_manager = BiomeManager.new()
	texture_manager = TextureManager.new()
	
	decor_manager = DecorManager.new()
	decor_manager.initialize(self)
	
	ground_thread_manager = GroundThreadManager.new()
	ground_thread_manager.initialize(self)
	
	chunk_manager = ChunkManager.new()
	chunk_manager.initialize(self)
	
	mob_activation_manager = MobActivationManager.new()
	mob_activation_manager.initialize(main.enemy, main.player, nav_baker, self)
	
	player_boundary = PlayerBoundary.new()
	player_boundary.initialize(self)


# ── Initial load check ────────────────────────────────────────────────
func are_nearby_chunks_ready(player_loc:Vector2i) ->bool:
	var cr := GroundConstants.initial_chunk_radius
	for x in range(player_loc.x - cr, player_loc.x + cr + 1):
		for y in range(player_loc.y - cr, player_loc.y + cr + 1):
			var loc := Vector2i(x, y)
			if loc.distance_to(player_loc) > cr:
				continue
			var chunk: GroundChunk = chunk_manager.chunks.get(loc, null)
			if !chunk || chunk.lod_tier > GroundConstants.LOD_LEVELS.CLOSE || !chunk.are_decors_spawned:
				return false
	return true
