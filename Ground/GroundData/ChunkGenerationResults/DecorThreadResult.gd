extends Resource
class_name DecorThreadResult

var loc: Vector2i
var transforms_by_mesh: Dictionary

func init(_loc: Vector2i, _transforms_by_mesh: Dictionary) -> DecorThreadResult:
	loc = _loc
	transforms_by_mesh = _transforms_by_mesh
	return self
