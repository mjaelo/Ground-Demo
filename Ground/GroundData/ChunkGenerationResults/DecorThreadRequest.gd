extends Resource
class_name DecorThreadRequest

var loc: Vector2i
var decor_idx: int = -1
var blocked: Dictionary = {}

func init(_loc: Vector2i, _decor_idx: int, _blocked:Dictionary) -> DecorThreadRequest:
	loc = _loc
	decor_idx = _decor_idx
	blocked = _blocked
	return self
