extends Resource
class_name DecorThreadResult

var loc: Vector2i
var transforms_by_mesh: Dictionary
var priority: DecorData = null
var blocked: Dictionary = {}

func init(_loc: Vector2i, _transforms_by_mesh: Dictionary, _priority: DecorData = null, _blocked: Dictionary = {}) -> DecorThreadResult:
	loc = _loc
	transforms_by_mesh = _transforms_by_mesh
	priority = _priority
	blocked = _blocked
	return self
