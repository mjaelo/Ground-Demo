extends Resource
class_name ChunkData

## Pure data describing a generated terrain chunk.
## Produced by ChunkGenerator on a worker thread, consumed by GroundChunk
## on the main thread to build the visual/collision scene nodes.

## Grid location of this chunk (in chunk-space, not world-space).
var loc: Vector2i = Vector2i.ZERO
## LOD tier that was used to generate this chunk.
var lod_tier: int = GroundConstants.LOD_LEVELS.FAR
## Single-channel (FORMAT_RF) heightmap image. Width = resolution.
var heightmap: Image = null
## RGB splatmap image encoding texture weights per vertex.
var splatmap: Image = null
## The dominant BiomeData at the chunk centre (determined during generation).
var dominant_biome: BiomeData = null
## Whether mesh-asset decor has been spawned on this chunk.
var decor_spawned: bool = false
## List of decor asset names spawned on this chunk, for bookkeeping.
var spawned_decor_names: Array[String] = []
