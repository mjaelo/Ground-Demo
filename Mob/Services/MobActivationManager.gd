extends RefCounted
class_name MobActivationManager

var _enemy: Enemy = null
var _player: Player = null
var _nav_baker: RuntimeNavigationBaker
var parent: GroundManager
var is_enemy_activated: bool = false
var is_player_activated: bool = false
	
func initialize(enemy: Enemy, player: Player, nav_baker: RuntimeNavigationBaker, _parent: GroundManager) -> void:
	_enemy = enemy
	_player = player
	_nav_baker = nav_baker
	parent = _parent
	_enemy.set_process(false)
	_enemy.set_physics_process(false)
	_nav_baker.player = player
	nav_baker.bake_finished.connect(on_nav_bake_finished)
	# Keep player frozen until activate_player() is called
	_player.set_physics_process(false)

func activate_player() -> void:
	if is_player_activated:
		return
	# Ensure height is explicitly cast to float (some return values can be Variant)
	var height_at_player: float = float(parent.chunk_manager.get_height_at(_player.global_transform.origin))
	_player.global_transform.origin.y = height_at_player + 5.0
	_player.gravity_enabled = true
	_player.collision_enabled = true
	_player.set_physics_process(true)
	is_player_activated = true

func activate_enemy() -> void:
	if is_enemy_activated:
		return
	var player_pos: Vector3 = _player.global_transform.origin
	var enemy_xz: Vector3 = player_pos + Vector3(30, 0, 30)
	# Cast height to float to avoid Variant type inference
	var height_at_enemy: float = float(parent.chunk_manager.get_height_at(enemy_xz))
	_enemy.global_transform.origin = Vector3(enemy_xz.x, height_at_enemy + 1.0, enemy_xz.z)
	_enemy.target = _player
	_enemy.set_process(true)
	_enemy.set_physics_process(true)
	_nav_baker._current_center = Vector3(INF, INF, INF)
	is_enemy_activated = true

func on_nav_bake_finished() -> void:
	if is_enemy_activated and not _enemy._navigation_ready:
		# Wait one physics frame so NavigationAgent3D syncs with the freshly baked region.
		await parent.get_tree().physics_frame
		_enemy.enable_navigation()
