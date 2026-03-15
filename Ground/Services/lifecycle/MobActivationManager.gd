extends RefCounted
class_name MobActivationManager

## Handles enemy activation and initial placement on the terrain.
# TODO overlap with player spawn logic. does this file need to exist?

var _enemy: Enemy = null
var _player: Player = null
var _nav_baker: RuntimeNavigationBaker
var _terrain_manager:GroundManager
var _activated: bool = false
var _height_sampler: Callable = Callable()
var _player_spawn_done: bool = false

func initialize(enemy: Enemy, player: Player, nav_baker: RuntimeNavigationBaker,terrain_manager:GroundManager) -> void:
	_enemy = enemy
	_player = player
	_nav_baker = nav_baker
	_terrain_manager = terrain_manager
	_enemy.set_process(false)
	_enemy.set_physics_process(false)

func set_height_sampler(sampler: Callable) -> void:
	_height_sampler = sampler

func try_activate(player_spawn_done: bool) -> void:
	if _activated or not player_spawn_done:
		return
	_activated = true
	var player_pos: Vector3 = _player.global_transform.origin
	var enemy_xz: Vector3 = player_pos + Vector3(30, 0, 30)
	var h: float = NAN
	if _height_sampler.is_valid():
		h = _height_sampler.call(enemy_xz)
	if is_nan(h):
		h = player_pos.y
	_enemy.global_transform.origin = Vector3(enemy_xz.x, h + 1.0, enemy_xz.z)
	_enemy.set_process(true)
	_enemy.set_physics_process(true)
	_enemy.enable_navigation()
	_nav_baker._current_center = Vector3(INF, INF, INF)

func on_nav_bake_finished() -> void:
	if _activated:
		_enemy.enable_navigation()

var is_activated: bool:
	get: return _activated

# ── Player spawning ──────────────────────────────────────────────────
func _try_player_spawn() -> void:
	if _player_spawn_done:
		return
	if not _terrain_manager.has_collision_at(_player.global_transform.origin):
		return
	var h: float = _terrain_manager.get_height_at(_player.global_transform.origin)
	print("[Ground] Spawning player at height %.1f" % h)
	_player.global_transform.origin.y = h + 5.0
	_player.gravity_enabled = true
	_player.collision_enabled = true
	_player_spawn_done = true
	try_activate(true)
