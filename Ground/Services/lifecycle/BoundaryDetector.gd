extends RefCounted
class_name BoundaryDetector

var player: Player = null

func initialize(_player: Player) -> void:
	player = _player

func update(chunk: GroundChunk) -> void:
	if not is_instance_valid(player):
		return
	if chunk == null || chunk.data.lod_tier > GroundConstants.LOD_LEVELS.CLOSE:
		player.velocity = Vector3.ZERO
		player.set_physics_process(false)
	else:
		player.set_physics_process(true)
