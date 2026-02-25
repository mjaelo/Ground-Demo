extends Node
class_name MeshPlacementManager

# How far to scatter grass/foliage; 0 uses the full terrain size.
@export var foliage_extent: int = 0
# Distance between placed foliage instances; lower = denser.
@export var foliage_step: int = 2
# Per-mesh placement controls loaded from JSON file.
@export_file("*.json") var placement_rules_file: String = "res://scripts/terrain3d/placement_rules.json"

const _SCENE_MESHES: Dictionary = {
	1: preload("res://assets/mesh_assets/tree.tscn")
}

var _placement_layers: Array = []
var _scene_nodes: Dictionary = {} # Vector2i -> Array[Node]

func _ready() -> void:
	_load_placement_rules()

func generate_transforms(region_origin_m: Vector3, region_size: int, height_sampler: Callable, normal_sampler: Callable) -> Dictionary:
	"""Generate mesh placement transforms for a region using provided height/normal samplers."""
	var width: int = foliage_extent
	if width <= 0:
		width = int(region_size)
	var step: int = max(1, int(foliage_step))
	var origin: Vector3 = region_origin_m + Vector3(-region_size * 0.5, 0, -region_size * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var asset_layers: Array = _placement_layers
	if asset_layers.is_empty():
		push_warning("No placement layers found")
	var transforms_by_mesh: Dictionary = {}
	for x in range(0, width, step):
		for z in range(0, width, step):
			var pos_x := x + origin.x
			var pos_z := z + origin.z
			var h_val: float = height_sampler.call(pos_x, pos_z)
			var pos := Vector3(pos_x, h_val, pos_z)
			var normal: Vector3 = normal_sampler.call(pos_x, pos_z)
			var slope_deg := rad_to_deg(acos(clamp(normal.dot(Vector3.UP), -1.0, 1.0)))
			for asset in asset_layers:
				_try_place_instance(asset, transforms_by_mesh, pos, slope_deg, rng)
	return transforms_by_mesh

func _try_place_instance(asset: Dictionary, transforms_by_mesh: Dictionary, pos: Vector3, slope_deg: float, rng: RandomNumberGenerator) -> void:
	var mesh_id: int = asset.get("mesh_id", -1)
	if mesh_id < 0:
		return
	var density: float = asset.get("density", 0.0)
	if density <= 0.0:
		return
	var max_slope: float = asset.get("max_slope", 90.0)
	if slope_deg > max_slope:
		return
	var min_height: float = asset.get("min_height", -INF)
	var max_height: float = asset.get("max_height", INF)
	if pos.y < min_height or pos.y > max_height:
		return
	if rng.randf() > density:
		return
	if not transforms_by_mesh.has(mesh_id):
		transforms_by_mesh[mesh_id] = []
	(transforms_by_mesh[mesh_id] as Array).push_back(Transform3D(Basis(), pos))

func _load_placement_rules() -> void:
	if placement_rules_file.is_empty():
		return
	if not FileAccess.file_exists(placement_rules_file):
		push_warning("Placement rules file not found: %s" % placement_rules_file)
		return
	var file := FileAccess.open(placement_rules_file, FileAccess.READ)
	if file == null:
		push_error("Failed to open placement rules: %s" % placement_rules_file)
		return
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_error("JSON parse error in %s at line %d: %s" % [placement_rules_file, json.get_error_line(), json.get_error_message()])
		return
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Expected JSON object in placement rules file")
		return
	var layers: Variant = data.get("layers", [])
	if typeof(layers) != TYPE_ARRAY:
		push_error("Expected 'layers' array in placement rules")
		return
	for layer in layers:
		if typeof(layer) == TYPE_DICTIONARY:
			_placement_layers.push_back(layer)

func spawn_scene_meshes(mesh_id: int, transforms: Array, parent: Node, loc: Vector2i) -> void:
	var scene: PackedScene = _SCENE_MESHES.get(mesh_id)
	if not scene:
		return
	var nodes: Array = []
	for t in transforms:
		var node: Node3D = scene.instantiate()
		node.global_transform = t
		parent.add_child(node)
		nodes.append(node)
	_scene_nodes[loc] = nodes

func clear_scene_meshes(loc: Vector2i) -> void:
	for node in _scene_nodes.get(loc, []):
		if is_instance_valid(node):
			node.queue_free()
	_scene_nodes.erase(loc)
