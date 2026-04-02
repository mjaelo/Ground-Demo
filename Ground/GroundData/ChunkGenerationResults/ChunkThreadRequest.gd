extends Resource
class_name ChunkThreadRequest

var loc: Vector2i
var lod_tier: int
var dist: float
var visible: bool = true  # whether the chunk is currently in camera frustum

func init(_loc: Vector2i, _lod_tier: int, _dist: float, _visible: bool) -> ChunkThreadRequest:
	loc = _loc
	lod_tier = _lod_tier
	dist = _dist
	visible = _visible
	return self
