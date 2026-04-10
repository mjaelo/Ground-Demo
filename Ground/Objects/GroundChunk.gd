extends Node3D
class_name GroundChunk

## Scene-node wrapper for a terrain chunk.
var data: ChunkData = null
var mesh_instance: MeshInstance3D = null
var collision_body: StaticBody3D = null
var decor_nodes: Array[Node3D] = [] # Node Array of decors in the chunks

var are_decors_spawned: bool = false
var lod_tier: int = GroundConstants.LOD_LEVELS.FAR # LOD tier used to generate this chunk.
