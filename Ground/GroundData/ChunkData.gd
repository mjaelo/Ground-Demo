extends Resource
class_name ChunkData

## Pure data describing a generated terrain chunk.
## Produced by ChunkGenerator on a worker thread, consumed by GroundChunk
## on the main thread to build the visual/collision scene nodes.

var loc: Vector2i = Vector2i.ZERO # Grid location of this chunk (in chunk-space, not world-space).
var lod_tier: int = GroundConstants.LOD_LEVELS.FAR # LOD tier that was used to generate this chunk.
var heightmap: Image = null # Single-channel (FORMAT_RF) heightmap image. Width = resolution.
var splatmap: Image = null # RGB splatmap image encoding texture weights per vertex.
var dominant_biome: BiomeData = null # The dominant BiomeData at the chunk centre (determined during generation).
var decor_spawned: bool = false # Whether mesh-asset decor has been spawned on this chunk.
var spawned_decor_names: Array[String] = [] # List of decor names spawned on this chunk, for bookkeeping.
