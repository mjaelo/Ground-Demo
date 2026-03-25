extends RefCounted
class_name MobActivationManager

## Handles player spawning (on initial load) and enemy activation. TODO move into Mob folder?

var _enemy: Enemy = null
var _player: Player = null
var _nav_baker: RuntimeNavigationBaker
var parent: Ground
var is_enemy_activated: bool = false
var is_player_activated: bool = false
	
func initialize(enemy: Enemy, player: Player, nav_baker: RuntimeNavigationBaker, _parent: Ground) -> void:
	_enemy = enemy
	_player = player
	_nav_baker = nav_baker
	parent = _parent
	_enemy.set_process(false)
	_enemy.set_physics_process(false)
	# When the initial bulk load finishes, spawn the player and activate mobs
	nav_baker.bake_finished.connect(on_nav_bake_finished)

## Called by GroundManager.initial_load_complete signal.
## Spawns the player on the terrain and activates the enemy.
func activate_mobs() -> void:
	if is_player_activated:
		return
	# Ensure height is explicitly cast to float (some return values can be Variant)
	var height_at_player: float = float(parent.chunk_manager.get_height_at(_player.global_transform.origin))
	_player.global_transform.origin.y = height_at_player + 5.0
	_player.gravity_enabled = true
	_player.collision_enabled = true
	is_player_activated = true
	_activate_enemy()

func _activate_enemy() -> void:
	if is_enemy_activated:
		return
	is_enemy_activated = true
	var player_pos: Vector3 = _player.global_transform.origin
	var enemy_xz: Vector3 = player_pos + Vector3(30, 0, 30)
	# Cast height to float to avoid Variant type inference
	var height_at_enemy: float = float(parent.chunk_manager.get_height_at(enemy_xz))
	_enemy.global_transform.origin = Vector3(enemy_xz.x, height_at_enemy + 1.0, enemy_xz.z)
	_enemy.set_process(true)
	_enemy.set_physics_process(true)
	_enemy.enable_navigation()
	_nav_baker._current_center = Vector3(INF, INF, INF)

func on_nav_bake_finished() -> void: # TODO is it called?
	if is_enemy_activated:
		_enemy.enable_navigation()
