extends RefCounted
class_name DecorManager
# TODO house scenes are not rotated

# asset_name (lowercase) -> PackedScene
var decor_scenes: Dictionary = {}
var decor_datas: Array[DecorData] = [] # TODO i dont need 2 variables, just sort it straight away
var decor_datas_sorted: Array[DecorData] = []
var _scene_nodes: Dictionary = {} # TODO refactor. idk what that is
var parent: Ground

func initialize(_parent: Ground) -> void:
	parent = _parent

func _init() -> void:
	#	load_decor_scenes
	var dir := DirAccess.open(GroundConstants.DECOR_PATH)
	if dir == null:
		push_error("Cannot open decor directory: %s" % GroundConstants.DECOR_PATH)
		return
	dir.list_dir_begin()
	var decor_file_name := dir.get_next()
	while decor_file_name != "":
		if not dir.current_is_dir() and decor_file_name.get_extension().to_lower() == "tscn":
			var decor_scene: PackedScene = load(GroundConstants.DECOR_PATH + decor_file_name)
			if decor_scene:
				var decor_name: String = decor_file_name.get_basename().to_lower()
				decor_scenes[decor_name] = decor_scene
		decor_file_name = dir.get_next()
	dir.list_dir_end()
	
	#	load_decor_datas
	decor_datas.append_array(GameUtils.load_from_json(GroundConstants.DECOR_VALUES_FILE, DecorData, "decors"))
	for decor: DecorData in decor_datas:
		var key: String = decor.decor_name.to_lower()
		if not decor_scenes.has(key):
			push_warning("placement_rules: no loaded scene matches name '%s', layer will be skipped" % decor.decor_name)
	decor_datas_sorted = decor_datas.duplicate(false)
	decor_datas_sorted.sort_custom(func(a: DecorData, b: DecorData) -> bool:
		if a.priority == b.priority:
			return a.decor_name.to_lower() < b.decor_name.to_lower()
		return a.priority > b.priority
	)

func generate_transforms_for_decor(region_origin_m: Vector3, region_size: int, blocked: Dictionary, decor_d: DecorData = null) -> Dictionary:
	var step: int = max(1, GroundConstants.DECOR_STEP)
	var origin: Vector3 = region_origin_m + Vector3(-region_size * 0.5, 0, -region_size * 0.5)
	var local_rng :=  RandomNumberGenerator.new()
	if decor_datas.is_empty():
		push_warning("No placement layers found")
	var ignore_blocked: bool = decor_d != null and decor_d.mesh_size == Vector2i.ZERO

	var transforms_by_decor_name: Dictionary = {}
	for x in range(0, region_size, step):
		for z in range(0, region_size, step):
			var gx: int = int(float(x) / float(step))
			var gz: int = int(float(z) / float(step))
			if !ignore_blocked and blocked.has(Vector2i(gx, gz)):
				continue
			if local_rng.randf() < GroundConstants.DECOR_EMPTY_CHANCE:
				continue
			var pos_x := x + origin.x
			var pos_z := z + origin.z
			if is_decor_allowed_in_biome(decor_d, pos_x, pos_z):
				if can_place_decor(pos_x, pos_z, local_rng, decor_d):
					# Pick a random Y rotation: 0, 90, 180, or 270 degrees
					var rot_index: int = local_rng.randi() % 4
					var rot_y: float = rot_index * PI * 0.5
					place_decor(decor_d, transforms_by_decor_name, pos_x, pos_z, blocked, gx, gz, step, rot_y)
	return transforms_by_decor_name

## Return a list of DecorData that are allowed in the biome covering the supplied chunk origin.
func get_allowed_decors_for_biome(biome: BiomeData) -> Array[DecorData]:
	var found :Array[DecorData] = []
	for d in decor_datas:
		if d.decor_name in biome.allowed_decor_ids:
			found.append(d)
	found.sort_custom(func(a: DecorData, b: DecorData) -> bool:
		if a.priority == b.priority:
			return a.decor_name.to_lower() < b.decor_name.to_lower()
		return a.priority > b.priority
	)
	return found

# Helper to filter decor layers by biome at a given world position
func is_decor_allowed_in_biome(decor: DecorData, wx: float, wz: float) -> bool:
	var biome: BiomeData = parent.biome_manager.get_biome_at(wx, wz)
	var allowed: Array = biome.allowed_decor_ids
	return decor.decor_name in allowed

func can_place_decor(pos_x: float, pos_z: float, rng: RandomNumberGenerator, decor: DecorData) -> bool:
	var center_h: float = parent.chunk_manager.sample_height(pos_x, pos_z)
	var center_slope: float = _slope_deg_at(pos_x, pos_z)

	if (decor.decor_name.is_empty() || !decor_scenes.has(decor.decor_name.to_lower()) 
	||	center_h < decor.min_height or center_h > decor.max_height 
	|| !is_slope_allowed(decor, pos_x, pos_z, center_slope) 
	||	rng.randf() >= decor.spawn_chance):
		return false
	return true

## Check slope at the center and, for meshes with a footprint, at the perimeter too.
func is_slope_allowed(decor: DecorData, cx: float, cz: float, center_slope: float) -> bool:
	if center_slope > decor.max_slope:
		return false
	var ms: Vector2i = decor.mesh_size
	if ms.x <= 0 and ms.y <= 0:
		return true  # single-point asset, center check is enough
	# Sample slope at footprint corners and edge midpoints.
	var hx: float = ms.x * 0.5
	var hz: float = ms.y * 0.5
	var corner_offsets: Array[Vector2] = [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz) ]
	for off in corner_offsets:
		var slope: float = _slope_deg_at(cx + off.x, cz + off.y)
		if slope > decor.max_slope:
			return false
	return true

## Place the decor at the lowest available Y level
func place_decor(decor: DecorData, transforms_by_name: Dictionary, pos_x: float, pos_z: float, blocked: Dictionary, gx: int, gz: int, step: int, rot_y: float = 0.0) -> void:
	var decor_name: String = decor.decor_name.to_lower()
	var best_h: float = parent.chunk_manager.sample_height(pos_x, pos_z)

	var ms: Vector2i = decor.mesh_size
	if ms.x > 0 or ms.y > 0:
		# Sample height at corners
		var hx: float = ms.x * 0.5
		var hz: float = ms.y * 0.5
		var sample_offsets: Array[Vector2] = [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]
		for off in sample_offsets:
			var h: float = parent.chunk_manager.sample_height(pos_x + off.x, pos_z + off.y)
			if h < best_h:
				best_h = h

	var rot_basis := Basis(Vector3.UP, rot_y)
	var decor_transforms := Transform3D(rot_basis, Vector3(pos_x, best_h, pos_z))
	if !transforms_by_name.has(decor_name):
		transforms_by_name[decor_name] = []
	transforms_by_name[decor_name].append(decor_transforms)

	# Block grid coords covered by this asset's mesh_size.
	if ms.x > 0 or ms.y > 0:
		var rx: int = int(ceil(float(ms.x) / float(2 * step)))
		var rz: int = int(ceil(float(ms.y) / float(2 * step)))
		for dx in range(-rx, rx + 1):
			for dz in range(-rz, rz + 1):
				blocked[Vector2i(gx + dx, gz + dz)] = true

func _slope_deg_at(wx: float, wz: float) -> float:
	var n: Vector3 = parent.chunk_manager.sample_normal(wx, wz)
	var ny: float = clamp(n.dot(Vector3.UP), -1.0, 1.0)
	# atan2(sin(theta), cos(theta)) == theta and sin(theta)=sqrt(1-ny^2)
	return rad_to_deg(atan2(sqrt(max(0.0, 1.0 - ny * ny)), ny))

func spawn_meshes(decor_name: String, transforms: Array, loc: Vector2i) -> void:
	var scene: PackedScene = decor_scenes.get(decor_name, null)
	if not scene:
		push_warning("spawn_meshes: no scene loaded for '%s'" % decor_name)
		return

	# Find visibility_range from placement rules for this asset.
	var vis_range: float = 0.0
	for decor in decor_datas:
		if decor.decor_name.to_lower() == decor_name and decor.visibility_range > 0.0:
			vis_range = decor.visibility_range
			break

	# Use a stable int slot key derived from the asset name hash.
	var name_hash: int = decor_name.hash()
	var slot_key := Vector3i(loc.x, loc.y, name_hash)
	var nodes: Array = _scene_nodes.get(slot_key, [])
	if transforms.size() == 0:
		# Nothing to spawn
		_scene_nodes[slot_key] = nodes
		return

	print("[DecorManager] spawn_meshes: ", decor_name, " count=", transforms.size(), " chunk=", loc)
	# Heuristic: attempt to batch into a MultiMeshInstance3D when the scene is simple
	# (only a single MeshInstance3D, no collision/physics nodes and no scripts).
	var decor_multimesh_data := get_decor_multimesh_data(scene)
	
	if decor_multimesh_data.can_multimesh:
		nodes.append(get_meshes_multimesh(transforms,decor_multimesh_data.mesh_res,decor_multimesh_data.mesh_local_transform, vis_range))
	else:
		nodes.append_array(get_meshes_simple(transforms, vis_range, scene))
	_scene_nodes[slot_key] = nodes

func get_decor_multimesh_data(scene: PackedScene) ->Dictionary:
	var can_multimesh: bool = true
	var mesh_res: Mesh = null
	var mesh_local_transform: Transform3D = Transform3D.IDENTITY
	var temp_inst: Node = scene.instantiate()
	# Find MeshInstance3D and detect disqualifying nodes
	var mesh_instances := []
	for n in temp_inst.get_children():
		if n is MeshInstance3D:
			mesh_instances.append(n)
		elif n is CollisionObject3D or n is Area3D or n.get_script() != null:
			can_multimesh = false
	# Also inspect root itself
	if temp_inst is MeshInstance3D:
		mesh_instances.append(temp_inst)
	if temp_inst.get_script() != null:
		can_multimesh = false

	if mesh_instances.size() == 1 and can_multimesh:
		mesh_res = (mesh_instances[0] as MeshInstance3D).mesh
		mesh_local_transform = (mesh_instances[0] as MeshInstance3D).transform
		var s := mesh_local_transform.basis.get_scale()
		if abs(s.x - 1.0) > 0.001 or abs(s.y - 1.0) > 0.001 or abs(s.z - 1.0) > 0.001:
			can_multimesh = false
		if mesh_local_transform.origin.length() > 0.001:
			can_multimesh = false
	else:
		can_multimesh = false

	# Free temporary instance used for inspection
	if is_instance_valid(temp_inst):
		temp_inst.free()
		
	return {
		"can_multimesh": can_multimesh,
		"mesh_res": mesh_res,
		"mesh_local_transform": mesh_local_transform
	}
		
func get_meshes_multimesh(transforms:Array, mesh_res: Mesh, mesh_local_transform: Transform3D, vis_range: float) -> MultiMeshInstance3D: # Build a MultiMesh and a single MultiMeshInstance3D for this chunk+asset
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = transforms.size()
	mm.mesh = mesh_res
	for i in range(transforms.size()):
		# Bake the mesh's local transform (scale/offset) into the instance transform
		mm.set_instance_transform(i, transforms[i] * mesh_local_transform)
	var mm_inst: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mm_inst.multimesh = mm
	parent.get_node("Chunks").add_child(mm_inst)
	if vis_range > 0.0:
		_apply_visibility_range_recursive(mm_inst, vis_range)
	return mm_inst
	
func get_meshes_simple(transforms:Array, vis_range: float, scene: PackedScene) ->Array[Node3D]: # instantiate full scenes for each transform (used for houses, colliders, scripts)
	var nodes: Array[Node3D] = []
	for t in transforms:
		var node: Node3D = scene.instantiate()
		node.transform = t
		parent.get_node("Chunks").add_child(node)
		if vis_range > 0.0:
			_apply_visibility_range_recursive(node, vis_range)
		nodes.append(node)
	return nodes

func _apply_visibility_range_recursive(node: Node, range_end: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visibility_range_end = range_end
		(node as GeometryInstance3D).visibility_range_end_margin = range_end * 0.1
	for child in node.get_children():
		_apply_visibility_range_recursive(child, range_end)

func clear_decors(loc: Vector2i) -> void:
	var to_erase: Array = []
	for slot_key in _scene_nodes.keys():
		if slot_key is Vector3i and slot_key.x == loc.x and slot_key.y == loc.y:
			to_erase.append(slot_key)
	for slot_key in to_erase:
		for node in _scene_nodes[slot_key]:
			if is_instance_valid(node):
				node.queue_free()
		_scene_nodes.erase(slot_key)
		if parent.ground_thread_manager and parent.ground_thread_manager.decor_threads.has(loc):
			parent.ground_thread_manager.decor_threads.erase(loc)
