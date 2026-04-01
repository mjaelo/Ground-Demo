@tool
extends Node
class_name GroundManager

## Main orchestrator for terrain generation, streaming, and enemy activation.
## World-shift has been removed: Godot handles large coordinates fine for
## the distances involved and the complexity was not justified.
var player_boundary: BoundaryDetector # TODO after implementing, should be placed in Mob directory?

# ── Terrain Generation ────────────────────────────────────────────────
var noise := FastNoiseLite.new()

# ── Node references ──────────────────────────────────────────────────
var player:Player
var enemy:Enemy

# ── Managers ──────────────────────────────────────────────────────────
var decor_manager: DecorManager
var biome_manager: BiomeManager
var texture_manager: TextureManager
var chunk_manager: ChunkManager
var ground_thread_manager: GroundThreadManager

var is_activated:= false # TODO duplicate from main

# ── Lifecycle ─────────────────────────────────────────────────────────
func init(_player:Player, _enemy:Enemy) -> void:
	player = _player
	enemy = _enemy
	noise.frequency = GroundConstants.NOISE_FREQUENCY
	
	biome_manager = BiomeManager.new()
	texture_manager = TextureManager.new()
	
	decor_manager = DecorManager.new()
	decor_manager.initialize(self)
	ground_thread_manager = GroundThreadManager.new()
	ground_thread_manager.initialize(self)
	chunk_manager = ChunkManager.new()
	chunk_manager.initialize(self)
	
	player_boundary = BoundaryDetector.new()

func unloaded_tick(player_chunk_loc: Vector2i) -> void:
	ground_thread_manager.handle_thread_results(player_chunk_loc)
	chunk_manager.update_visible_chunks(player_chunk_loc)

func loaded_tick(player_chunk_loc: Vector2i) -> void:
	ground_thread_manager.handle_thread_results(player_chunk_loc)
	chunk_manager.update_visible_chunks(player_chunk_loc)
	var chunk: GroundChunk = chunk_manager.chunks.get(player_chunk_loc, null)
	player_boundary.update(chunk)

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

func activate_ground():
	ground_thread_manager.set_steady_values()
	is_activated = true
