extends Resource
class_name ChunkData

var loc: Vector2i = Vector2i.ZERO # Grid location of this chunk (in chunk-space, not world-space).
var heightmap: Image = null # heights of vertex
var splatmap: Image = null # texture weights per vertex.
var prominent_biome_ids: Array[int] = [] # ids of prominent biomes in the chunk. used for is_decor_allowed_in_chunk
var has_water: bool = false # Whether this chunk should render water at y=0 (set during chunk generation)
var decor_transforms: Dictionary = {} # decor_id -> Array[Transforms3D]