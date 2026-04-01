extends Node
class_name Main

# ── Module references ──────────────────────────────────────────────────
@onready var ground: GroundManager = $Ground
@onready var ui: UiManager = $UI
@onready var mob_manager: MobManager = $Mob

var is_activated: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	ui.init(mob_manager.player)
	mob_manager.init(ground)
	ground.init(mob_manager.player, mob_manager.enemy)
	await get_tree().process_frame

func _process(_delta: float) -> void: # TODO can be done more rarely
	if Engine.is_editor_hint():
		return
	var player_chunk_loc: Vector2i = mob_manager.get_player_chunk_loc()
	
	if is_activated:
		loaded_tick(player_chunk_loc)
	else:
		unloaded_tick(player_chunk_loc)
		
func loaded_tick(player_chunk_loc: Vector2i) -> void:
	ground.loaded_tick(player_chunk_loc)

func unloaded_tick(player_chunk_loc: Vector2i) -> void:
	ground.unloaded_tick(player_chunk_loc)
	if ground.are_nearby_chunks_ready(player_chunk_loc):
		activate_modules()

func activate_modules() -> void:
	# TODO stop loading screen
	ground.activate_ground()
	mob_manager.activate()
	is_activated = true
