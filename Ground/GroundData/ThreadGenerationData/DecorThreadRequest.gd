extends Resource
class_name DecorThreadRequest

var loc: Vector2i
var decor_idx: int = -1
var blocked: Dictionary = {} # x,z -> true
var decor_transforms: Array[Transform3D] = []

func init(_loc: Vector2i, _decor_idx: int, _blocked: Dictionary, _decor_transforms: Array[Transform3D]) -> DecorThreadRequest:
	loc = _loc
	decor_idx = _decor_idx
	blocked = _blocked
	decor_transforms = _decor_transforms
	return self
