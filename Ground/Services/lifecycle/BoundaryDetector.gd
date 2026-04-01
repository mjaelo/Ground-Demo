extends RefCounted
class_name BoundaryDetector


func update(chunk: GroundChunk) -> void:
	# Current chunk already has collision — nothing to block.
	if chunk and chunk.collision_body != null:
		return
	# TODO prevent player from moving