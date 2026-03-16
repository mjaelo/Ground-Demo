extends RefCounted
class_name PlayerBoundary

## Prevents the player from walking into chunks that lack collision.
## Instead of a safety floor, the player is simply blocked from crossing
## into any chunk that has not yet generated collision geometry.

var _player: Player = null
var _chunks: Dictionary  # reference to GroundManager._chunks

func initialize(player: Player, chunks: Dictionary) -> void:
	_player = player
	_chunks = chunks

func update() -> void:
	if not _player or not _player.is_inside_tree():
		return
	if not _player.gravity_enabled or not _player.collision_enabled:
		return

	var ppos: Vector3 = _player.global_transform.origin
	var loc := GroundConstants.world_pos_to_chunk_loc(ppos)

	# Current chunk already has collision — nothing to block.
	if _chunks.has(loc) and _chunks[loc].collision_body != null:
		return

	# Player is in a chunk without collision. Push them back to the nearest
	# neighbouring chunk that DOES have collision.
	var cs: float = float(GroundConstants.CHUNK_SIZE)
	var chunk_min_x: float = loc.x * cs
	var chunk_max_x: float = chunk_min_x + cs
	var chunk_min_z: float = loc.y * cs
	var chunk_max_z: float = chunk_min_z + cs
	var margin: float = 0.5

	var new_pos := ppos
	var pushed := false

	# Check each cardinal neighbour and push player back toward collision.
	var has_left := _has_collision(Vector2i(loc.x - 1, loc.y))
	var has_right := _has_collision(Vector2i(loc.x + 1, loc.y))
	var has_up := _has_collision(Vector2i(loc.x, loc.y - 1))
	var has_down := _has_collision(Vector2i(loc.x, loc.y + 1))

	# X-axis push
	if has_left and not has_right:
		new_pos.x = chunk_min_x - margin; pushed = true
	elif has_right and not has_left:
		new_pos.x = chunk_max_x + margin; pushed = true
	elif has_left:
		new_pos.x = chunk_min_x - margin; pushed = true
	elif has_right:
		new_pos.x = chunk_max_x + margin; pushed = true

	# Z-axis push
	if has_up and not has_down:
		new_pos.z = chunk_min_z - margin; pushed = true
	elif has_down and not has_up:
		new_pos.z = chunk_max_z + margin; pushed = true
	elif has_up:
		new_pos.z = chunk_min_z - margin; pushed = true
	elif has_down:
		new_pos.z = chunk_max_z + margin; pushed = true

	if pushed:
		_player.global_transform.origin = new_pos
		_player.velocity.x = 0
		_player.velocity.z = 0
		return

	# Absolute fallback: no neighbouring chunk has collision either.
	# Use heightmap floor if available so the player doesn't fall through.
	var floor_y: float
	if _chunks.has(loc) and _chunks[loc].heightmap:
		floor_y = GroundConstants.height_from_heightmap(_chunks[loc].heightmap, ppos, loc)
	else:
		floor_y = ppos.y
	if ppos.y < floor_y + 0.5:
		_player.global_transform.origin.y = floor_y + 0.5
		if _player.velocity.y < 0:
			_player.velocity.y = 0

func _has_collision(loc: Vector2i) -> bool:
	return _chunks.has(loc) and _chunks[loc].collision_body != null
