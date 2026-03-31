extends Resource
class_name DecorThreadResult

var loc: Vector2i
var transforms_by_mesh: Dictionary
var decor: DecorData = null # TODO unneeded since decor_idx is used
var blocked: Dictionary = {}
var decor_idx: int = -1

func init(_loc: Vector2i, _transforms_by_mesh: Dictionary, _decor: DecorData = null, _blocked: Dictionary = {}, _decor_idx: int = -1) -> DecorThreadResult:
	loc = _loc
	transforms_by_mesh = _transforms_by_mesh
	decor = _decor
	blocked = _blocked
	decor_idx = _decor_idx
	return self
