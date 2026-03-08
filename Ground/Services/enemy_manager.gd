extends RefCounted
class_name EnemyManager

## Handles enemy activation and initial placement on the terrain.

var _enemy: CharacterBody3D = null
var _player: CharacterBody3D = null
var _terrain: Terrain3D = null
var _nav_baker: Node = null
var _activated: bool = false

func initialize(enemy: CharacterBody3D, player: CharacterBody3D, terrain: Terrain3D, nav_baker: Node) -> void:
	_enemy = enemy
	_player = player
	_terrain = terrain
	_nav_baker = nav_baker
	# Disable enemy until terrain is ready.
	_enemy.set_process(false)
	_enemy.set_physics_process(false)

## Try to activate the enemy.  Succeeds only once, and only after the
## player has been spawned (caller passes the flag).
func try_activate(player_spawn_done: bool) -> void:
	if _activated or not player_spawn_done:
		return
	_activated = true

	var player_pos: Vector3 = _player.global_transform.origin
	var offset := Vector3(30, 0, 30)
	var enemy_xz: Vector3 = player_pos + offset
	var h: float = _terrain.data.get_height(enemy_xz)
	if is_nan(h):
		h = player_pos.y
	_enemy.global_transform.origin = Vector3(enemy_xz.x, h + 1.0, enemy_xz.z)
	_enemy.set_process(true)
	_enemy.set_physics_process(true)
	_enemy.enable_navigation()
	# Force nav baker to rebake at the new position.
	_nav_baker._current_center = Vector3(INF, INF, INF)

## Called when the nav baker finishes — enable navigation on an already-active enemy.
func on_nav_bake_finished() -> void:
	if _activated:
		_enemy.enable_navigation()

var is_activated: bool:
	get: return _activated
