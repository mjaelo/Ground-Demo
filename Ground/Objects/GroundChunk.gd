extends RefCounted
class_name GroundChunk

## Scene-node wrapper for a terrain chunk. Holds the MeshInstance3D, optional collision body, and a reference to the underlying ChunkData.
# ── Per-chunk references ──────────────────────────────────────────────
var data: ChunkData = null # TODO i dont think Chunk needs to store ChunkData, its only needed for initialization.
var mesh_instance: MeshInstance3D = null
var collision_body: StaticBody3D = null
var are_decors_spawned: bool = false

## Free the visual and collision nodes.
func destroy() -> void:
	if is_instance_valid(mesh_instance):
		mesh_instance.queue_free()
	mesh_instance = null
	collision_body = null
