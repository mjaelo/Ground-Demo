extends Node
class_name MeshPlacementManager
# TODO house scenes are not rotated

# Distance between placed foliage instances; lower = denser.
@export var foliage_step: int = 2
@export var empty_chance: float = 0.3 # Probability (0-1) that a coordinate is left empty (no asset placed)

const MESH_ASSETS_PATH: String = "res://assets/mesh_assets/"
# Per-mesh placement controls loaded from JSON file.
@export_file("*.json") var placement_rules_file: String = MESH_ASSETS_PATH + "decor_placement_rules.json"

# asset_name (lowercase) -> PackedScene
var _scene_assets: Dictionary = {}

var _placement_layers: Array[DecorData] = []
# Key: Vector3i(loc.x, loc.y, asset_hash) -> Array[Node]
var _scene_nodes: Dictionary = {}

func initialize(_terrain: Node) -> void:
	_load_assets_from_disk()
	_load_placement_rules()

func _load_assets_from_disk() -> void:
	var dir := DirAccess.open(MESH_ASSETS_PATH)
	if dir == null:
		push_error("Cannot open mesh assets directory: %s" % MESH_ASSETS_PATH)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "tscn":
			var scene: PackedScene = load(MESH_ASSETS_PATH + file_name)
			if scene:
				var key: String = file_name.get_basename().to_lower()
				_scene_assets[key] = scene
		file_name = dir.get_next()
	dir.list_dir_end()

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
			var decor := DecorData.from_dict(layer)
			var key: String = decor.asset_name.to_lower()
			if not _scene_assets.has(key):
				push_warning("placement_rules: no loaded scene matches name '%s', layer will be skipped" % decor.asset_name)
			_placement_layers.push_back(decor)

# Returns a Dictionary of asset_name (String) -> Array[Transform3D].
func generate_transforms(region_origin_m: Vector3, region_size: int, height_sampler: Callable, normal_sampler: Callable) -> Dictionary:
	var step: int = max(1, int(foliage_step))
	var origin: Vector3 = region_origin_m + Vector3(-region_size * 0.5, 0, -region_size * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if _placement_layers.is_empty():
		push_warning("No placement layers found")

	# Split layers: large-footprint assets are placed first so their blocked
	# zones are established before small assets fill remaining space.
	var large_layers: Array[DecorData] = []
	var small_layers: Array[DecorData] = []
	for decor in _placement_layers:
		if decor.mesh_size.x > 0 or decor.mesh_size.y > 0:
			large_layers.append(decor)
		else:
			small_layers.append(decor)

	# transforms_by_name: asset_name (lowercase) -> Array[Transform3D]
	var transforms_by_name: Dictionary = {}
	# Tracks grid coords (Vector2i in step-space) blocked by large-footprint assets.
	var blocked: Dictionary = {}

	# Pass 1: large-footprint assets only.
	if not large_layers.is_empty():
		for x in range(0, region_size, step):
			for z in range(0, region_size, step):
				var gx: int = x / step
				var gz: int = z / step
				if blocked.has(Vector2i(gx, gz)):
					continue
				if rng.randf() < empty_chance:
					continue
				var pos_x := x + origin.x
				var pos_z := z + origin.z
				_pick_and_place(transforms_by_name, pos_x, pos_z, rng, blocked, gx, gz, step, large_layers, height_sampler, normal_sampler)

	# Pass 2: small assets, skipping coords blocked by large assets.
	if not small_layers.is_empty():
		for x in range(0, region_size, step):
			for z in range(0, region_size, step):
				var gx: int = x / step
				var gz: int = z / step
				if blocked.has(Vector2i(gx, gz)):
					continue
				if rng.randf() < empty_chance:
					continue
				var pos_x := x + origin.x
				var pos_z := z + origin.z
				_pick_and_place(transforms_by_name, pos_x, pos_z, rng, blocked, gx, gz, step, small_layers, height_sampler, normal_sampler)

	return transforms_by_name

func _pick_and_place(transforms_by_name: Dictionary, pos_x: float, pos_z: float, rng: RandomNumberGenerator, blocked: Dictionary, gx: int, gz: int, step: int, layers: Array[DecorData], height_sampler: Callable, normal_sampler: Callable) -> void:
	var center_h: float = height_sampler.call(pos_x, pos_z)
	var center_slope: float = _slope_deg_at(pos_x, pos_z, normal_sampler)

	var candidates: Array[DecorData] = []
	var weights: Array[float] = []
	var total_weight: float = 0.0
	for decor in layers:
		if decor.asset_name.is_empty():
			continue
		if not _scene_assets.has(decor.asset_name.to_lower()):
			continue
		if decor.weight <= 0.0:
			continue
		if center_h < decor.min_height or center_h > decor.max_height:
			continue
		# Slope check: for assets with a footprint, check all covered sample points.
		if not _check_slope_footprint(decor, pos_x, pos_z, center_slope, normal_sampler):
			continue
		if rng.randf() >= decor.spawn_chance:
			continue
		total_weight += decor.weight
		candidates.append(decor)
		weights.append(total_weight)
	if candidates.is_empty():
		return
	var roll: float = rng.randf() * total_weight
	# Pick a random Y rotation: 0, 90, 180, or 270 degrees
	var rot_index: int = rng.randi() % 4
	var rot_y: float = rot_index * PI * 0.5
	for i in candidates.size():
		if roll <= weights[i]:
			_place_instance(candidates[i], transforms_by_name, pos_x, pos_z, blocked, gx, gz, step, height_sampler, rot_y)
			return
	_place_instance(candidates[-1], transforms_by_name, pos_x, pos_z, blocked, gx, gz, step, height_sampler, rot_y)

## Check slope at the center and, for meshes with a footprint, at the perimeter too.
func _check_slope_footprint(decor: DecorData, cx: float, cz: float, center_slope: float, normal_sampler: Callable) -> bool:
	if center_slope > decor.max_slope:
		return false
	var ms: Vector2i = decor.mesh_size
	if ms.x <= 0 and ms.y <= 0:
		return true  # single-point asset, center check is enough
	# Sample slope at footprint corners and edge midpoints.
	var hx: float = ms.x * 0.5
	var hz: float = ms.y * 0.5
	var sample_offsets: Array[Vector2] = [
		Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz),  # corners
		Vector2(0, -hz), Vector2(0, hz), Vector2(-hx, 0), Vector2(hx, 0),         # edge midpoints
	]
	for off in sample_offsets:
		var slope: float = _slope_deg_at(cx + off.x, cz + off.y, normal_sampler)
		if slope > decor.max_slope:
			return false
	return true

## Place the mesh at the highest ground point within its footprint so Y=0 vertices
## are never above ground.
func _place_instance(decor: DecorData, transforms_by_name: Dictionary, pos_x: float, pos_z: float, blocked: Dictionary, gx: int, gz: int, step: int, height_sampler: Callable, rot_y: float = 0.0) -> void:
	var key: String = decor.asset_name.to_lower()
	var best_h: float = height_sampler.call(pos_x, pos_z)

	var ms: Vector2i = decor.mesh_size
	if ms.x > 0 or ms.y > 0:
		# Sample height at corners, edge midpoints and a few interior points.
		var hx: float = ms.x * 0.5
		var hz: float = ms.y * 0.5
		var sample_offsets: Array[Vector2] = [
			Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz),
			Vector2(0, -hz), Vector2(0, hz), Vector2(-hx, 0), Vector2(hx, 0),
			Vector2(-hx * 0.5, -hz * 0.5), Vector2(hx * 0.5, -hz * 0.5),
			Vector2(-hx * 0.5, hz * 0.5), Vector2(hx * 0.5, hz * 0.5),
		]
		for off in sample_offsets:
			var h: float = height_sampler.call(pos_x + off.x, pos_z + off.y)
			if h > best_h:
				best_h = h

	if not transforms_by_name.has(key):
		transforms_by_name[key] = []
	# Build a transform with Y rotation applied
	var rot_basis := Basis(Vector3.UP, rot_y)
	(transforms_by_name[key] as Array).push_back(Transform3D(rot_basis, Vector3(pos_x, best_h, pos_z)))

	# Block grid coords covered by this asset's mesh_size.
	if ms.x > 0 or ms.y > 0:
		var rx: int = int(ceil(float(ms.x) / float(2 * step)))
		var rz: int = int(ceil(float(ms.y) / float(2 * step)))
		for dx in range(-rx, rx + 1):
			for dz in range(-rz, rz + 1):
				blocked[Vector2i(gx + dx, gz + dz)] = true

static func _slope_deg_at(wx: float, wz: float, normal_sampler: Callable) -> float:
	var n: Vector3 = normal_sampler.call(wx, wz)
	return rad_to_deg(acos(clamp(n.dot(Vector3.UP), -1.0, 1.0)))

func spawn_meshes(asset_name: String, transforms: Array, parent: Node, loc: Vector2i) -> void:
	var key: String = asset_name.to_lower()
	var scene: PackedScene = _scene_assets.get(key, null)
	if not scene:
		push_warning("spawn_meshes: no scene loaded for '%s'" % asset_name)
		return

	# Find visibility_range from placement rules for this asset.
	var vis_range: float = 0.0
	for decor in _placement_layers:
		if decor.asset_name.to_lower() == key and decor.visibility_range > 0.0:
			vis_range = decor.visibility_range
			break

	# Use a stable int slot key derived from the asset name hash.
	var name_hash: int = key.hash()
	var slot_key := Vector3i(loc.x, loc.y, name_hash)
	var nodes: Array = _scene_nodes.get(slot_key, [])
	for t in transforms:
		var node: Node3D = scene.instantiate()
		# Set local transform before add_child so _ready() sees the correct position.
		# global_transform is unreliable before the node enters the tree; since parent
		# is a plain Node (no 3-D offset) local == global, so this is equivalent.
		node.transform = t
		parent.add_child(node)
		if vis_range > 0.0:
			_apply_visibility_range_recursive(node, vis_range)
		nodes.append(node)
	_scene_nodes[slot_key] = nodes

func _apply_visibility_range_recursive(node: Node, range_end: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visibility_range_end = range_end
		(node as GeometryInstance3D).visibility_range_end_margin = range_end * 0.1
	for child in node.get_children():
		_apply_visibility_range_recursive(child, range_end)

func clear_scene_meshes(loc: Vector2i) -> void:
	for slot_key in _scene_nodes.keys():
		if slot_key is Vector3i and slot_key.x == loc.x and slot_key.y == loc.y:
			for node in _scene_nodes[slot_key]:
				if is_instance_valid(node):
					node.queue_free()
			_scene_nodes.erase(slot_key)
