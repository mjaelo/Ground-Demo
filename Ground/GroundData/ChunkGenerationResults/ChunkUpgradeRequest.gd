extends Resource
class_name ChunkUpgradeRequest

var loc: Vector2i
var lod_tier: int
var dist: float

func init(_loc: Vector2i, _lod_tier: int, _dist: float) -> ChunkUpgradeRequest:
	loc = _loc
	lod_tier = _lod_tier
	dist = _dist
	return self

