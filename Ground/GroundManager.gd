@tool
extends Node
class_name GroundManager

## Main orchestrator for ground generation and streaming
var boundary_detector: BoundaryDetector # TODO after implementing, should be placed in Mob directory?

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

var lod_chunks_nr := 0
var spawned_chunks_nr := 0
var decor_chunks_nr := 0
var total_chunk_nr := 0

var is_activated := false # TODO duplicate from main

# ── Lifecycle ─────────────────────────────────────────────────────────
func init(_player:Player, _enemy:Enemy) -> void:
	player = _player
	enemy = _enemy
	noise.frequency = GroundConstants.NOISE_FREQUENCY
	
	biome_manager = BiomeManager.new()
	texture_manager = TextureManager.new()
	boundary_detector = BoundaryDetector.new()
	
	decor_manager = DecorManager.new()
	decor_manager.initialize(self)
	ground_thread_manager = GroundThreadManager.new()
	ground_thread_manager.initialize(self)
	chunk_manager = ChunkManager.new()
	chunk_manager.initialize(self)

func unloaded_tick(player_chunk_loc: Vector2i) -> void:
	ground_thread_manager.handle_thread_results(player_chunk_loc)
	chunk_manager.update_visible_chunks(player_chunk_loc)

func loaded_tick(player_chunk_loc: Vector2i) -> void:
	ground_thread_manager.handle_thread_results(player_chunk_loc)
	chunk_manager.update_visible_chunks(player_chunk_loc)
	var chunk: GroundChunk = chunk_manager.chunks.get(player_chunk_loc, null)
	boundary_detector.update(chunk)

# ── Initial load check ────────────────────────────────────────────────
func are_nearby_chunks_ready(player_loc: Vector2i) -> bool:
	var cr := GroundConstants.initial_chunk_radius
	decor_chunks_nr = 0
	spawned_chunks_nr = 0
	lod_chunks_nr = 0
	total_chunk_nr = 0
	var is_ready := true
	for x in range(player_loc.x - cr, player_loc.x + cr + 1):
		for y in range(player_loc.y - cr, player_loc.y + cr + 1):
			var loc := Vector2i(x, y)
			total_chunk_nr += 1
			var chunk: GroundChunk = chunk_manager.chunks.get(loc, null)
			if !chunk:
				is_ready = false
				continue
			lod_chunks_nr += 1
			if chunk.lod_tier > GroundConstants.LOD_LEVELS.CLOSE:
				is_ready = false
				continue
			spawned_chunks_nr += 1
			if !chunk.are_decors_spawned:
				is_ready = false
				continue
			decor_chunks_nr += 1
	return is_ready

func activate():
	ground_thread_manager.set_steady_values()
	is_activated = true
	
func get_load_status() -> String:
	return (
		"LOD:    %2d / %2d\n" % [lod_chunks_nr, total_chunk_nr] +
		"Chunks: %2d / %2d\n" % [spawned_chunks_nr, total_chunk_nr] +
		"Decor:  %2d / %2d"   % [decor_chunks_nr, total_chunk_nr]
	)
