extends Node
class_name MobManager
@onready var nav_baker: RuntimeNavigationBaker = $NavBaker
@onready var player: Player = $Player
@onready var enemy: Enemy = $Enemy # TODO enemy should be spawned by the decor / chunk when it generates

var mob_activation_manager: MobActivationManager

func init(ground:GroundManager) -> void:	
	player.init()
	mob_activation_manager = MobActivationManager.new()
	mob_activation_manager.initialize(enemy, player, nav_baker, ground)

func activate() -> void:
	mob_activation_manager.activate_player()
	mob_activation_manager.activate_enemy()

func get_player_chunk_loc() -> Vector2i:
	return GroundUtils.world_pos_to_chunk_loc(player.global_transform.origin)

func get_player_position() -> Vector3:
	return player.position

func get_load_status() -> String:
	var isready := mob_activation_manager != null and mob_activation_manager.is_player_activated and mob_activation_manager.is_enemy_activated
	return "Mobs ready: %s" % [isready]
