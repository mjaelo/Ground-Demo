extends Node
class_name RuntimeNavigationBaker

signal bake_finished

var player: Player
var _current_center := Vector3(INF, INF, INF)
var _bake_task_id: int = -1
var _bake_cooldown_timer: float = 0.0
var _nav_region: NavigationRegion3D


var is_enabled: bool = true :
	set(p_value):
		is_enabled = p_value
		if _nav_region:
			_nav_region.enabled = is_enabled
		set_process(is_enabled and template)

var enter_cost: float = 0.0 :
	set(p_value):
		enter_cost = p_value
		if _nav_region:
			_nav_region.enter_cost = enter_cost

var travel_cost: float = 1.0 :
	set(p_value):
		travel_cost = p_value
		if _nav_region:
			_nav_region.travel_cost = travel_cost

var navigation_layers: int = 1 :
	set(p_value):
		navigation_layers = p_value
		if _nav_region:
			_nav_region.navigation_layers = navigation_layers

var template: NavigationMesh :
	set(p_value):
		template = p_value
		set_process(is_enabled and template)
		_update_map_cell_size()


func _ready() -> void:
	_nav_region = NavigationRegion3D.new()
	_nav_region.navigation_layers = navigation_layers
	_nav_region.enabled = is_enabled
	_nav_region.enter_cost = enter_cost
	_nav_region.travel_cost = travel_cost
	# Edge connections cause main-thread hitches on every nav mesh update.
	_nav_region.use_edge_connections = false
	add_child(_nav_region)

	if not template:
		var t := NavigationMesh.new()
		# Static colliders avoid GPU readback stalls; close-LOD chunks have StaticBody3D.
		t.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		t.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
		t.cell_size = GroundConstants.NAV_CELL_SIZE
		t.cell_height = GroundConstants.NAV_CELL_HEIGHT
		t.agent_height = 2.0
		# Keep radius and climb as exact multiples of cell dimensions to avoid generator warnings.
		t.agent_radius = GroundConstants.NAV_CELL_SIZE
		t.agent_max_climb = GroundConstants.NAV_CELL_HEIGHT
		t.agent_max_slope = 45.0
		template = t
	else:
		_update_map_cell_size()


func _update_map_cell_size() -> void:
	if get_viewport() and template:
		var map := get_viewport().find_world_3d().navigation_map
		NavigationServer3D.map_set_cell_size(map, template.cell_size)
		NavigationServer3D.map_set_cell_height(map, template.cell_height)
		NavigationServer3D.map_set_merge_rasterizer_cell_scale(map, 0.0625)


func _process(p_delta: float) -> void:

	if not player or _bake_task_id != -1:
		return

	if _bake_cooldown_timer > 0.0:
		_bake_cooldown_timer -= p_delta
		return

	var track_pos := player.global_position
	var snap := float(GroundConstants.CHUNK_SIZE) * 0.5
	var snapped_center := Vector3(round(track_pos.x / snap) * snap, track_pos.y, round(track_pos.z / snap) * snap)

	if snapped_center.distance_squared_to(_current_center) >= GroundConstants.MIN_REBASE_DIST * GroundConstants.MIN_REBASE_DIST:
		_current_center = snapped_center
		_rebake(_current_center)


func _rebake(p_center: Vector3) -> void:
	if not template:
		return
	var source_geometry := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(template, source_geometry, get_parent() if get_parent() else self)

	_bake_task_id = WorkerThreadPool.add_task(_task_bake.bind(p_center, source_geometry), false, "RuntimeNavigationBaker")
	_bake_cooldown_timer = GroundConstants.BAKE_COOLDOWN


func _task_bake(p_center: Vector3, p_source_geometry: NavigationMeshSourceGeometryData3D) -> void:
	var nav_mesh: NavigationMesh = template.duplicate()
	var r := GroundConstants.NAV_BAKE_RADIUS
	var h := GroundConstants.NAV_BAKE_HEIGHT
	nav_mesh.filter_baking_aabb = AABB(Vector3(-r, -h * 0.5, -r), Vector3(r * 2.0, h, r * 2.0))
	nav_mesh.filter_baking_aabb_offset = p_center

	if p_source_geometry.has_data():
		NavigationServer3D.bake_from_source_geometry_data(nav_mesh, p_source_geometry)
		_bake_finished.call_deferred(nav_mesh)
	else:
		_bake_finished.call_deferred(null)


func _bake_finished(p_nav_mesh: NavigationMesh) -> void:
	_bake_task_id = -1

	if p_nav_mesh:
		_nav_region.navigation_mesh = p_nav_mesh

	bake_finished.emit()
	assert(!NavigationServer3D.region_get_use_edge_connections(_nav_region.get_region_rid()))
