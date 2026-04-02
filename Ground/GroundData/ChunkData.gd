extends Resource
class_name ChunkData

var loc: Vector2i = Vector2i.ZERO # Grid location of this chunk (in chunk-space, not world-space).
var lod_tier: int = GroundConstants.LOD_LEVELS.FAR # LOD tier used to generate this chunk.
var heightmap: Image = null # Single-channel (FORMAT_RF) heightmap image. Width = resolution.
var splatmap: Image = null # RGB splatmap image encoding texture weights per vertex.
var prominent_biomes: Array[BiomeData] = [] # Biomes covering at least 10% of this chunk's pixels.
var has_water: bool = false # Whether this chunk should render water at y=0 (set during chunk generation)
