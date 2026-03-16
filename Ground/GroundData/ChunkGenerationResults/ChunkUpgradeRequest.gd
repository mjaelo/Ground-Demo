extends Resource
class_name ChunkUpgradeRequest

var loc: Vector2i
var tier: int
var dist: float

func init(_loc: Vector2i, _tier: int, _dist: float) -> ChunkUpgradeRequest:
	loc = _loc
	tier = _tier
	dist = _dist
	return self

