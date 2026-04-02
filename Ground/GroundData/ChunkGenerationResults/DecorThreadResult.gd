extends Resource
class_name DecorThreadResult

var loc: Vector2i
var transforms_by_mesh: Array[Transform3D]
var blocked: Dictionary = {}
var decor_idx: int = -1

func init(_loc: Vector2i, _transforms_by_mesh: Array[Transform3D], _blocked: Dictionary = {}, _decor_idx: int = -1) -> DecorThreadResult:
	loc = _loc
	transforms_by_mesh = _transforms_by_mesh
	blocked = _blocked
	decor_idx = _decor_idx
	return self
