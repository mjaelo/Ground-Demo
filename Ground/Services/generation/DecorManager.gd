extends RefCounted
class_name DecorManager
# TODO house scenes are not rotated

# asset_name (lowercase) -> PackedScene
var decor_scenes: Dictionary = {}
var decor_datas: Array[DecorData] = []
var _scene_nodes: Dictionary = {} # TODO refactor. idk what that is
# multimesh is only done, when  decor scene is a single mesh (without script), with normal scale and origin
var _multimesh_cache: Dictionary = {}  # decor_name (lowercase) -> {can_multimesh, mesh_res, mesh_local_transform}
var parent: GroundManager

func initialize(_parent: GroundManager) -> void:
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
	decor_datas.sort_custom(func(a: DecorData, b: DecorData) -> bool:
		if a.priority == b.priority:
			return a.decor_name.to_lower() < b.decor_name.to_lower()
		return a.priority > b.priority
	)
	# Pre-compute multimesh eligibility for every loaded scene once at startup.
	for scene_name in decor_scenes:
		_multimesh_cache[scene_name] = get_decor_multimesh_data(decor_scenes[scene_name])

func generate_transforms_for_decor(region_origin_m: Vector3, blocked: Dictionary, decor_d: DecorData) -> Array[Transform3D]:
	var chunk_size := GroundConstants.CHUNK_SIZE
	var step: int = max(1, GroundConstants.DECOR_STEP)
	var origin: Vector3 = region_origin_m + Vector3(-chunk_size * 0.5, 0, -chunk_size * 0.5)
	var local_rng := RandomNumberGenerator.new()
	if decor_datas.is_empty():
		push_warning("No placement layers found")
	var ignore_blocked: bool = decor_d != null and decor_d.mesh_size == Vector2i.ZERO

	# Hoist invariant checks out of the hot loop.
	if decor_d.decor_name.is_empty() or not decor_scenes.has(decor_d.decor_name.to_lower()):
		return []

	var spawn_chance: float = decor_d.spawn_chance
	var empty_chance: float = GroundConstants.DECOR_EMPTY_CHANCE

	var transforms_by_decor_name: Array[Transform3D] = []
	for x in range(0, chunk_size, step):
		for z in range(0, chunk_size, step):
			var gx: int = int(float(x) / float(step))
			var gz: int = int(float(z) / float(step))
			if !ignore_blocked and blocked.has(Vector2i(gx, gz)):
				continue
			if local_rng.randf() < empty_chance:
				continue
			# Check spawn_chance BEFORE any noise sampling – cheapest rejection.
			if local_rng.randf() >= spawn_chance:
				continue
			var pos_x := x + origin.x
			var pos_z := z + origin.z
			# Compute biome scores once and reuse for both checks — avoids 2x noise per cell.
			var biome_scores: Array[float] = parent.biome_manager._compute_biome_scores(pos_x, pos_z)
			if _is_decor_allowed_in_biome(decor_d, biome_scores):
				if _can_place_decor(pos_x, pos_z, decor_d, biome_scores):
					var rot_index: int = local_rng.randi() % 4
					var rot_y: float = rot_index * PI * 0.5
					_place_decor(decor_d, transforms_by_decor_name, pos_x, pos_z, blocked, gx, gz, step, rot_y)
	return transforms_by_decor_name

func _is_decor_allowed_in_biome(decor: DecorData, biome_scores: Array[float]) -> bool:
	var best_i := 0
	for i in range(1, biome_scores.size()):
		if biome_scores[i] > biome_scores[best_i]:
			best_i = i
	return decor.decor_name in parent.biome_manager.biomes[best_i].allowed_decor_ids

func _can_place_decor(pos_x: float, pos_z: float, decor: DecorData, biome_scores: Array[float]) -> bool:
	var center_h: float = parent.biome_manager.get_height_at(pos_x, pos_z, biome_scores)
	if center_h < decor.min_height or center_h > decor.max_height:
		return false
	var center_slope: float = _slope_deg_at(pos_x, pos_z)
	if not _is_slope_allowed(decor, pos_x, pos_z, center_slope):
		return false
	return true

func _is_slope_allowed(decor: DecorData, cx: float, cz: float, center_slope: float) -> bool:
	if center_slope > decor.max_slope:
		return false
	var ms: Vector2i = decor.mesh_size
	if ms.x <= 0 and ms.y <= 0:
		return true
	var hx: float = ms.x * 0.5
	var hz: float = ms.y * 0.5
	for off in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]:
		if _slope_deg_at(cx + off.x, cz + off.y) > decor.max_slope:
			return false
	return true

func _place_decor(decor: DecorData, transforms_by_name: Array[Transform3D], pos_x: float, pos_z: float, blocked: Dictionary, gx: int, gz: int, step: int, rot_y: float) -> void:
	var best_h: float =  parent.biome_manager.get_height_at(pos_x, pos_z)
	var ms: Vector2i = decor.mesh_size
	if ms.x > 0 or ms.y > 0:
		var hx: float = ms.x * 0.5
		var hz: float = ms.y * 0.5
		for off in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]:
			var h: float =  parent.biome_manager.get_height_at(pos_x + off.x, pos_z + off.y)
			if h < best_h:
				best_h = h
	var rot_basis := Basis(Vector3.UP, rot_y)
	transforms_by_name.append(Transform3D(rot_basis, Vector3(pos_x, best_h, pos_z)))
	if ms.x > 0 or ms.y > 0:
		var rx: int = int(ceil(float(ms.x) / float(2 * step)))
		var rz: int = int(ceil(float(ms.y) / float(2 * step)))
		for dx in range(-rx, rx + 1):
			for dz in range(-rz, rz + 1):
				blocked[Vector2i(gx + dx, gz + dz)] = true

func _slope_deg_at(wx: float, wz: float) -> float:
	var n: Vector3 = parent.chunk_manager.sample_normal(wx, wz)
	var ny: float = clamp(n.dot(Vector3.UP), -1.0, 1.0)
	return rad_to_deg(atan2(sqrt(max(0.0, 1.0 - ny * ny)), ny))

func spawn_meshes(decor: DecorData, transforms: Array[Transform3D], loc: Vector2i) -> void:
	var scene: PackedScene = decor_scenes.get(decor.decor_name.to_lower(), null)
	if not scene:
		push_warning("spawn_meshes: no scene loaded for '%s'" % decor)
		return

	# Use a stable int slot key derived from the asset name hash.
	var name_hash: int = decor.decor_name.hash()
	var slot_key := Vector3i(loc.x, loc.y, name_hash)
	var nodes: Array = _scene_nodes.get(slot_key, [])
	if transforms.size() == 0:
		# Nothing to spawn
		_scene_nodes[slot_key] = nodes
		return

	# Use cached multimesh eligibility computed at startup.
	var decor_multimesh_data: Dictionary = _multimesh_cache.get(decor.decor_name.to_lower(), {})
	
	if decor_multimesh_data.can_multimesh:
		nodes.append(get_meshes_multimesh(transforms,decor_multimesh_data.mesh_res,decor_multimesh_data.mesh_local_transform, decor.visibility_range))
	else:
		nodes.append_array(get_meshes_simple(transforms, decor.visibility_range, scene))
	_scene_nodes[slot_key] = nodes

func get_decor_multimesh_data(scene: PackedScene) -> Dictionary:
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
		
func get_meshes_multimesh(transforms:Array[Transform3D], mesh_res: Mesh, mesh_local_transform: Transform3D, vis_range: float) -> MultiMeshInstance3D: # Build a MultiMesh and a single MultiMeshInstance3D for this chunk+asset
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = transforms.size()
	mm.mesh = mesh_res
	for i in range(transforms.size()):
		# Bake the mesh's local transform (scale/offset) into the instance transform
		mm.set_instance_transform(i, transforms[i] * mesh_local_transform)
	var mm_inst: MultiMeshInstance3D = MultiMeshInstance3D.new()
	mm_inst.multimesh = mm
	mm_inst.use_occlusion_culling = true
	parent.get_node("Chunks").add_child(mm_inst)
	if vis_range > 0.0:
		_apply_visibility_range_recursive(mm_inst, vis_range)
	return mm_inst
	
func get_meshes_simple(transforms: Array[Transform3D], vis_range: float, scene: PackedScene) ->Array[Node3D]: # instantiate full scenes for each transform (used for houses, colliders, scripts)
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
		var gi := node as GeometryInstance3D
		gi.visibility_range_end = range_end
		gi.visibility_range_end_margin = range_end * 0.1
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
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
