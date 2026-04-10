extends Resource
class_name ChunkThreadResult

var lod_tier: int
var chunk_data: ChunkData

func init(_lod_tier: int, _chunk_data: ChunkData) -> ChunkThreadResult:
	lod_tier = _lod_tier
	chunk_data = _chunk_data
	return self
