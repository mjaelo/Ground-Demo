extends Node
class_name RuntimeNavigationBaker

signal bake_finished # TODO never emitted

var terrain: Node
var player: Player
var _scene_geometry: NavigationMeshSourceGeometryData3D
var _current_center := Vector3(INF,INF,INF)
var _bake_task_id: int = -1
var _bake_task_timer: float = 0.0
var _bake_cooldown_timer: float = 0.0
var _nav_region: NavigationRegion3D


# TODO inline setters
var is_enabled: bool = true : set = set_enabled
func set_enabled(p_value: bool) -> void:
	is_enabled = p_value
	if _nav_region:
		_nav_region.enabled = is_enabled
	set_process(is_enabled and template)

var enter_cost: float = 0.0 : set = set_enter_cost
func set_enter_cost(p_value: bool) -> void:
	enter_cost = p_value
	if _nav_region:
		_nav_region.enter_cost = enter_cost

var travel_cost: float = 1.0 : set = set_travel_cost
func set_travel_cost(p_value: bool) -> void:
	travel_cost = p_value
	if _nav_region:
		_nav_region.travel_cost = travel_cost

var navigation_layers: int = 1 : set = set_navigation_layers
func set_navigation_layers(p_value: int) -> void:
	navigation_layers = p_value
	if _nav_region:
		_nav_region.navigation_layers = navigation_layers

var template: NavigationMesh : set = set_template
func set_template(p_value: NavigationMesh) -> void:
	template = p_value
	set_process(is_enabled and template)
	_update_map_cell_size()


func _ready():
	_nav_region = NavigationRegion3D.new()
	_nav_region.navigation_layers = navigation_layers
	_nav_region.enabled = is_enabled
	_nav_region.enter_cost = enter_cost
	_nav_region.travel_cost = travel_cost
	
	# Enabling edge connections comes with a performance penalty that causes hitches whenever
	# the nav mesh is updated. The navigation server has to compare each edge, and it does this on
	# the main thread.
	_nav_region.use_edge_connections = false
	
	add_child(_nav_region)
	
	_update_map_cell_size()
	
	# If you're using ProtonScatter, you will want to delay this next call until after all
	# your scatter nodes have finished setting up. Here, we just defer one frame so that nodes
	# after this one in the tree get set up first
	parse_scene.call_deferred()

func parse_scene() -> void:
	if not template:
		return
	_scene_geometry = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(template, _scene_geometry, self)


func _update_map_cell_size() -> void:
	if get_viewport() and template:
		var map := get_viewport().find_world_3d().navigation_map
		NavigationServer3D.map_set_cell_size(map, template.cell_size)
		NavigationServer3D.map_set_cell_height(map, template.cell_height)


func _process(p_delta: float) -> void:
	if _bake_task_id != -1:
		_bake_task_timer += p_delta
	
	if not player or _bake_task_id != -1:
		return
	
	if _bake_cooldown_timer > 0.0:
		_bake_cooldown_timer -= p_delta
		return
	
	var track_pos := player.global_position
	if player:
		# Center on where the player is likely _going to be_:
		track_pos += player.velocity * GroundConstants.BAKE_COOLDOWN
	
	if track_pos.distance_squared_to(_current_center) >= GroundConstants.MIN_REBASE_DIST * GroundConstants.MIN_REBASE_DIST:
		_current_center = track_pos
		_rebake(_current_center)


func _rebake(p_center: Vector3) -> void: # TODO is never called
	if not template:
		return
	_bake_task_id = WorkerThreadPool.add_task(_task_bake.bind(p_center), false, "RuntimeNavigationBaker")
	_bake_task_timer = 0.0
	_bake_cooldown_timer = GroundConstants.BAKE_COOLDOWN


func _task_bake(p_center: Vector3) -> void:
	var nav_mesh: NavigationMesh = template.duplicate()
	nav_mesh.filter_baking_aabb = AABB(-GroundConstants.MESH_SIZE * 0.5, GroundConstants.MESH_SIZE)
	nav_mesh.filter_baking_aabb_offset = p_center
	var source_geometry: NavigationMeshSourceGeometryData3D
	source_geometry = _scene_geometry.duplicate()
	
	if terrain:
		var aabb: AABB = nav_mesh.filter_baking_aabb
		aabb.position += nav_mesh.filter_baking_aabb_offset
		var faces: PackedVector3Array = terrain.generate_nav_mesh_source_geometry(aabb, false)
		if faces.size() > 0:
			source_geometry.add_faces(faces, Transform3D.IDENTITY)
	
	if source_geometry.has_data():
		NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_geometry)
		_bake_finished.call_deferred(nav_mesh)
	else:
		_bake_finished.call_deferred(null)


func _bake_finished(p_nav_mesh: NavigationMesh) -> void:
	_bake_task_timer = 0.0
	_bake_task_id = -1
	
	if p_nav_mesh:
		_nav_region.navigation_mesh = p_nav_mesh
	
	bake_finished.emit()
	assert(!NavigationServer3D.region_get_use_edge_connections(_nav_region.get_region_rid()))
