extends Resource
class_name DecorThreadResult

var loc: Vector2i
var decor_transforms: Array[Transform3D]
var blocked: Dictionary = {} # x,z -> true
var decor_idx: int = -1

func init(_loc: Vector2i, _decor_transforms: Array[Transform3D], _blocked: Dictionary = {}, _decor_idx: int = -1) -> DecorThreadResult:
	loc = _loc
	decor_transforms = _decor_transforms
	blocked = _blocked
	decor_idx = _decor_idx
	return self
