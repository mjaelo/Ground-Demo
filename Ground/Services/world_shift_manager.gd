extends RefCounted
class_name WorldShiftManager

## Handles world-origin shifting. Synchronous and fast — just repositions
## chunk nodes and re-keys dictionaries. No Terrain3D involvement.

# ── Configuration ─────────────────────────────────────────────────────
var terrain_coord_limit: float = 4096.0
var shift_threshold_fraction: float = 0.5

# ── State ─────────────────────────────────────────────────────────────
var world_offset := Vector3.ZERO
var shifting := false

# ── References (set via initialize) ──────────────────────────────────
var _player: Node3D = null
var _enemy: Node3D = null
var _nav_baker: Node = null
var _custom_terrain: CustomTerrainManager = null
var _mesh_placement = null  # MeshPlacementManager
var _region_size: int = 256
var _ground: Node = null    # Parent Ground node for callback

func initialize(
	player: Node3D,
	enemy: Node3D,
	nav_baker: Node,
	custom_terrain: CustomTerrainManager,
	mesh_placement,
	region_size: int,
) -> void:
	_player = player
	_enemy = enemy
	_nav_baker = nav_baker
	_custom_terrain = custom_terrain
	_mesh_placement = mesh_placement
	_region_size = region_size
	_ground = player.get_parent().get_node_or_null("Ground")

func check_and_shift() -> void:
	if shifting:
		return
	var pos: Vector3 = _player.global_transform.origin
	var threshold: float = terrain_coord_limit * shift_threshold_fraction
	if absf(pos.x) >= threshold or absf(pos.z) >= threshold:
		_perform_world_shift()

func _perform_world_shift() -> void:
	shifting = true
	_player.set_physics_process(false)

	var pos: Vector3 = _player.global_transform.origin
	var sx: int = roundi(pos.x / float(_region_size))
	var sz: int = roundi(pos.z / float(_region_size))
	var shift := Vector3(sx * _region_size, 0, sz * _region_size)

	if shift.is_zero_approx():
		_player.set_physics_process(true)
		shifting = false
		return

	world_offset += shift
	var shift_loc := Vector2i(sx, sz)
	print("[WorldShift] Shifting by %s" % shift)

	_player.global_transform.origin -= shift
	_enemy.global_transform.origin -= shift

	_custom_terrain.shift_all(-shift, shift_loc)

	if _mesh_placement and _mesh_placement.has_method("shift_all_meshes"):
		_mesh_placement.shift_all_meshes(-shift, shift_loc)

	# Notify Ground to update its world offset for sampling
	if _ground and _ground.has_method("on_world_shifted"):
		_ground.on_world_shifted(world_offset)

	_nav_baker._current_center = Vector3(INF, INF, INF)
	_player.set_physics_process(true)

	print("[WorldShift] Complete. offset: %s" % world_offset)
	shifting = false
