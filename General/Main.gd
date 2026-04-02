extends Node
class_name Main

# ── Module references ──────────────────────────────────────────────────
@onready var ground: GroundManager = $Ground
@onready var ui: UiManager = $UI
@onready var mob: MobManager = $Mob

var is_startup_done: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	ui.init(mob.player)
	mob.init(ground)
	ground.init(mob.player, mob.enemy)
	await get_tree().process_frame

func _process(_delta: float) -> void: # TODO can be done more rarely
	if Engine.is_editor_hint():
		return
	var player_chunk_loc: Vector2i = mob.get_player_chunk_loc()
	
	if is_startup_done:
		loaded_tick(player_chunk_loc)
	else:
		unloaded_tick(player_chunk_loc)
		
func loaded_tick(player_chunk_loc: Vector2i) -> void:
	ground.loaded_tick(player_chunk_loc)
	ui.loaded_tick()

func unloaded_tick(player_chunk_loc: Vector2i) -> void:
	ground.unloaded_tick(player_chunk_loc)
	var load_status := ground.get_load_status() + "\n" + mob.get_load_status()
	ui.unloaded_tick(load_status)
	try_activate_modules(player_chunk_loc)

func try_activate_modules(player_chunk_loc: Vector2i) -> void:
	if ground.is_ground_ready(player_chunk_loc):
		ui.activate()
		ground.activate()
		mob.activate()
		is_startup_done = true
