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
	mob_activation_manager.activate_mobs()

func get_player_chunk_loc() -> Vector2i:
	return GroundUtils.world_pos_to_chunk_loc(player.global_transform.origin)

func get_load_status() -> String:
	return " Player ready: %s\nEnemy ready: %s" % [mob_activation_manager.is_player_activated, mob_activation_manager.is_enemy_activated]