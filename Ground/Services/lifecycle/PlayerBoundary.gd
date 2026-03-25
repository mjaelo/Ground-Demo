extends RefCounted
class_name PlayerBoundary

## Prevents the player from walking into chunks that lack collision.
## Instead of a safety floor, the player is simply blocked from crossing into any chunk that has not yet generated collision geometry.

var parent: Ground

func initialize(_parent: Ground) -> void:
	parent = _parent

func update(player_loc) -> void:
	var chunk: GroundChunk = parent.chunk_manager.chunks.get(player_loc, null)
	# Current chunk already has collision — nothing to block.
	if chunk and chunk.collision_body != null:
		return
	# TODO prevent player from moving