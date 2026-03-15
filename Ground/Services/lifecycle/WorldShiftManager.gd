extends RefCounted
class_name WorldShiftManager

## Handles world-origin shifting. Synchronous and fast — just repositions

# ── State ─────────────────────────────────────────────────────────────
var world_offset := Vector3.ZERO
var shifting := false

# ── References (set via initialize) ──────────────────────────────────
var _ground: Ground = null    # Parent Ground node for callback

func initialize(ground:Ground) -> void:
	_ground = ground

func check_and_shift() -> void:
	if shifting:
		return
	var pos: Vector3 = _ground.player.global_transform.origin
	if absf(pos.x) >= GroundConstants.shift_threshold or absf(pos.z) >= GroundConstants.shift_threshold:
		_perform_world_shift()

func _perform_world_shift() -> void:
	shifting = true
	_ground.player.set_physics_process(false)

	var pos: Vector3 = _ground.player.global_transform.origin
	var sx: int = roundi(pos.x / float(GroundConstants.CHUNK_SIZE))
	var sz: int = roundi(pos.z / float(GroundConstants.CHUNK_SIZE))
	var shift := Vector3(sx * GroundConstants.CHUNK_SIZE, 0, sz * GroundConstants.CHUNK_SIZE)

	if shift.is_zero_approx():
		_ground.player.set_physics_process(true)
		shifting = false
		return

	world_offset += shift
	var shift_loc := Vector2i(sx, sz)
	print("[WorldShift] Shifting by %s" % shift)

	_ground.player.global_transform.origin -= shift
	_ground.enemy.global_transform.origin -= shift

	shift_all(-shift, shift_loc)
	
	# Notify Ground to update its world offset for sampling
	if _ground and _ground.has_method("on_world_shifted"):
		_ground.on_world_shifted(world_offset)

	_ground.nav_baker._current_center = Vector3(INF, INF, INF)
	_ground.player.set_physics_process(true)

	print("[WorldShift] Complete. offset: %s" % world_offset)
	shifting = false

func shift_all(offset: Vector3, shift_loc: Vector2i) -> void:
	for loc in _ground._terrain_manager._generating.keys():
		var result = _ground._terrain_manager._generating[loc].wait_to_finish()
		if typeof(result) == TYPE_DICTIONARY:
			_ground._terrain_manager.pending_chunk_results.push_back(result)
	_ground._terrain_manager._generating.clear()
	var new_chunks: Dictionary = {}
	for loc in _ground._terrain_manager._chunks.keys():
		var nl: Vector2i = loc - shift_loc
		var c = _ground._terrain_manager._chunks[loc]
		c.loc = nl
		c.shift(offset)
		new_chunks[nl] = c
	_ground._terrain_manager._chunks = new_chunks
	for r in _ground._terrain_manager.pending_chunk_results:
		r["loc"] = r["loc"] - shift_loc
