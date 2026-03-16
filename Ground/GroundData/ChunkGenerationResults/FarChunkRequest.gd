extends Resource
class_name FarChunkRequest

var loc: Vector2i
var dist: float

func init(_loc: Vector2i, _dist: float) -> FarChunkRequest:
	loc = _loc
	dist = _dist
	return self
