extends Node
class_name Main


# ── Node references ──────────────────────────────────────────────────
@onready var player: Player = $Player
@onready var ui: Control = $UI
@onready var enemy: Enemy = $Ground/Enemy # TODO enemy should be spawned by the decor / chunk when it generates

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_setup_ui_and_player()
	
func _setup_ui_and_player() -> void:
	if ui and player:
		ui.player = player
		NavigationServer3D.set_debug_enabled(true)
		player.gravity_enabled = false
		player.collision_enabled = false
		await get_tree().process_frame
